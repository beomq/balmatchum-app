import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:balmatchum_app/features/ads/ads_session.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

class _MemoryAuth implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async {
    value = data;
  }
}

Future<String> seam(String path) async {
  final http = HttpClient();
  try {
    final response = await (await http.getUrl(
      Uri.parse('http://127.0.0.1:18101$path'),
    )).close();
    expect(response.statusCode, 200);
    return await utf8.decoder.bind(response).join();
  } finally {
    http.close();
  }
}

/// Only presentation is fake; intent, signature verification and consumption
/// use real HTTP endpoints, the SSV listener and isolated PostgreSQL.
class _SsvSdk implements AdsSdk, RewardedPlacement {
  late String owner;
  late String nonce;
  @override
  Future<AdsSetup> prepare() async => AdsSetup.ready;
  @override
  Future<RewardedPlacement> load(String adUnit) async {
    expect(adUnit, 'local-quiz-unit');
    return this;
  }

  @override
  Future<void> setVerification(String userId, String customData) async {
    owner = userId;
    nonce = customData;
  }

  @override
  Future<void> show({
    required void Function() onReward,
    required void Function() onDismiss,
    required void Function() onFailure,
  }) async {
    onReward();
    await seam('/ssv?nonce=$nonce&owner=$owner');
    onDismiss();
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> privacyOptions() async {}
  @override
  bool get privacyOptionsRequired => false;
}

class _ObservedRepository extends QuizRepository {
  _ObservedRepository(super.client, super.accountId);
  Completer<void>? historyRead;
  Completer<void>? reviewRead;
  @override
  Future<List<QuizQuestion>> history(int? before) async {
    final result = await super.history(before);
    historyRead?.complete();
    historyRead = null;
    return result;
  }

  @override
  Future<QuizQuestion> review(int id) async {
    final result = await super.review(id);
    reviewRead?.complete();
    reviewRead = null;
    return result;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native quiz empty bank answer SSV explicit unlock and historical review',
    (tester) async {
      final bootstrap =
          jsonDecode(await seam('/session')) as Map<String, dynamic>;
      final client = Client(
        'http://127.0.0.1:18100/',
      )..authSessionManager = FlutterAuthSessionManager(storage: _MemoryAuth());
      await client.auth.updateSignedInUser(
        AuthSuccess.fromJson(bootstrap['auth'] as Map<String, dynamic>),
      );
      final account = client.auth.authInfo!.authUserId.toString();
      final repository = _ObservedRepository(client, account);
      final controller = QuizController(
        repository,
        isCurrentAccount: () =>
            client.auth.authInfo?.authUserId.toString() == account,
      );
      addTearDown(() {
        controller.dispose();
        client.close();
      });

      Future<void> capture(String name) async {
        final bytes = await binding.takeScreenshot(name);
        final http = HttpClient();
        try {
          final request = await http.postUrl(
            Uri.parse('http://127.0.0.1:18101/capture?name=$name'),
          );
          request.add(bytes);
          final response = await request.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          http.close();
        }
      }

      Future<void> action(Future<void> Function() trigger) async {
        final done = Completer<void>();
        var started = false;
        void changed() {
          if (controller.busy) started = true;
          if (started && !controller.busy && !done.isCompleted) done.complete();
        }

        controller.addListener(changed);
        try {
          await trigger();
          await tester.runAsync(
            () => done.future.timeout(const Duration(seconds: 20)),
          );
          await tester.pumpAndSettle();
        } finally {
          controller.removeListener(changed);
        }
      }

      Future<void> tap(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
      }

      final ads = (await createAdsController(client, sdk: _SsvSdk()))!;
      await action(
        () => tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme(),
            home: AuthenticatedQuizScreen(
              controller: controller,
              onBack: () {},
              onHome: () {},
              createAds: () async => ads,
            ),
          ),
        ),
      );
      expect(controller.today!.status, 'contentUnavailable');
      await capture('quiz-empty-bank');
      await seam('/bank');
      // The empty state has no reload button; entry reads today itself.
      await action(controller.load);
      final free = controller.today!.free!;
      expect(free.fixtureLabel, 'quiz-test-fixture-not-production');
      expect(free.source, isNull);
      await capture('quiz-free-question');
      // One tap is the answer.
      await action(() => tap('quiz_${free.assignmentId}_choice_1'));
      expect(controller.today!.free!.answerIndex, 1);
      expect(controller.today!.free!.correctIndex, 0);
      expect(controller.today!.free!.awardedPoints, 2);
      expect(controller.today!.extraStatus, 'adRequired');
      expect((await client.product.getWallet()).balance, 0);
      await tester.ensureVisible(
        find.byKey(ValueKey('quiz_${free.assignmentId}_award_new')),
      );
      await capture('quiz-wrong-answer');

      // Exhaustion of the available IDs is distinct from an empty bank.
      await seam('/exhausted');
      await action(controller.load);
      expect(controller.today!.extraStatus, 'exhausted');
      await tester.ensureVisible(
        find.byKey(const ValueKey('quiz_extra_exhausted')),
      );
      await capture('quiz-exhausted');
      await seam('/bank');
      await action(controller.load);

      final verified = Completer<void>();
      ads.addListener(() {
        if (ads.status == AdsStatus.verified && !verified.isCompleted) {
          verified.complete();
        }
      });
      await tap('quiz_watch_ad');
      await tester.pumpAndSettle();
      await tap('ads_start');
      await tester.runAsync(
        () => verified.future.timeout(const Duration(seconds: 20)),
      );
      await tester.pumpAndSettle();
      final intent = ads.intent!.id;
      expect((await repository.getToday()).extra, isNull);
      expect((await client.product.getWallet()).balance, 0);
      await capture('quiz-verified-ad');
      await tap('ads_close');
      await tester.pumpAndSettle();
      expect(controller.verifiedIntent, intent);
      expect((await repository.getToday()).extra, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('quiz_unlock')));
      await capture('quiz-explicit-unlock');
      await action(() => tap('quiz_unlock'));
      final extra = controller.today!.extra!;
      expect((await client.ads.getIntent(intent)).status, 'consumed');
      await tester.ensureVisible(
        find.byKey(ValueKey('quiz_${extra.assignmentId}_choice_0')),
      );
      await capture('quiz-extra-question');
      await action(() => tap('quiz_${extra.assignmentId}_choice_0'));
      expect(controller.today!.extra!.awardedPoints, 2);
      expect((await client.product.getWallet()).balance, 0);
      await tester.ensureVisible(
        find.byKey(ValueKey('quiz_${extra.assignmentId}_award_new')),
      );
      await capture('quiz-extra-answer');

      final history = Completer<void>();
      repository.historyRead = history;
      await tap('quiz_history');
      await tester.runAsync(
        () => history.future.timeout(const Duration(seconds: 20)),
      );
      await tester.pumpAndSettle();
      await capture('quiz-history');
      final review = Completer<void>();
      repository.reviewRead = review;
      await tap('quiz_history_${free.assignmentId}');
      await tester.runAsync(
        () => review.future.timeout(const Duration(seconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('quiz_${free.assignmentId}_past_points')),
        findsOneWidget,
      );
      expect((await client.product.getWallet()).balance, 0);
      await capture('quiz-review');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
