import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:balmatchum_app/features/ads/ads_session.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

class _MemoryAuth implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async => value = data;
}

Future<String> seam(String path) async {
  final http = HttpClient();
  try {
    final response = await (await http.getUrl(
      Uri.parse('http://127.0.0.1:18091$path'),
    )).close();
    expect(response.statusCode, 200);
    return await utf8.decoder.bind(response).join();
  } finally {
    http.close();
  }
}

/// Only the ad presentation is fake. The callback reaches the real raw SSV
/// listener, signature verifier, database transaction and generated HTTP API.
class LocalSsvSdk implements AdsSdk, RewardedPlacement {
  late String owner;
  late String nonce;
  final shown = Completer<void>();
  @override
  Future<AdsSetup> prepare() async => AdsSetup.ready;
  @override
  Future<RewardedPlacement> load(String adUnit) async {
    expect(adUnit, 'local-reward-unit');
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
    shown.complete();
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> privacyOptions() async {}
  @override
  bool get privacyOptionsRequired => false;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual server partial free and verified ad atomic reward', (
    tester,
  ) async {
    final bootstrap =
        jsonDecode(await seam('/session')) as Map<String, dynamic>;
    final client = Client('http://127.0.0.1:18090/')
      ..authSessionManager = FlutterAuthSessionManager(storage: _MemoryAuth());
    await client.auth.updateSignedInUser(
      AuthSuccess.fromJson(bootstrap['auth'] as Map<String, dynamic>),
    );
    final account = client.auth.authInfo!.authUserId.toString();
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final product = ProductController(
      ProductRepository(client, accountId: account),
      steps,
      null,
      account: account,
      isCurrentAccount: () =>
          client.auth.authInfo?.authUserId.toString() == account,
    );
    addTearDown(() {
      product.dispose();
      steps.dispose();
      client.close();
    });
    await product.connect();
    expect(product.error, isNull);
    expect(product.wallet!.balance, 0);
    final date = DateTime.parse(bootstrap['pastDate'] as String);
    var day = await product.loadDay(date);
    expect(day.claimablePoints, 20);
    expect(day.adClaimablePoints, 180);
    final support = await getApplicationSupportDirectory();
    final dir = await Directory('${support.path}/reward-qa')
        .create(recursive: true);
    Future<void> capture(String name) async {
      final bytes = await binding.takeScreenshot(name);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      final http = HttpClient();
      try {
        final request = await http.postUrl(
          Uri.parse('http://127.0.0.1:18091/capture?name=$name'),
        );
        request.add(bytes);
        final response = await request.close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        http.close();
      }
    }

    final opened = Completer<DateTime>();
    final monthLoaded = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: RecordsCalendarScreen(
          initialMonth: date,
          loadMonth: (m) async {
            final result = await product.loadMonth(m);
            if (!monthLoaded.isCompleted) monthLoaded.complete();
            return result;
          },
          onOpenDay: opened.complete,
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.runAsync(
      () => monthLoaded.future.timeout(const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('records_day_${date.day}')));
    expect(await opened.future, date);
    await capture('reward-calendar');
    final sdk = LocalSsvSdk();
    final ads = await createAdsController(client, sdk: sdk);
    final verified = Completer<void>();
    ads!.addListener(() {
      if (ads.status == AdsStatus.verified && !verified.isCompleted) {
        verified.complete();
      }
    });
    var changed = Completer<RecordDay>();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: RewardPanel(
                controller: product,
                day: day,
                createAds: () async => ads,
                onChanged: (value) {
                  if (!changed.isCompleted) changed.complete(value);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('reward-mixed-free');
    await tester.tap(find.byKey(const ValueKey('reward_free_claim')));
    day = (await tester.runAsync(
      () => changed.future.timeout(const Duration(seconds: 20)),
    ))!;
    await tester.pumpAndSettle();
    expect(day.rewardStatus, DayRewardStatus.adRequired);
    expect(day.claimablePoints, 0);
    expect(day.adClaimablePoints, 140);
    expect(product.wallet!.balance, 20);
    expect(find.byKey(const ValueKey('reward_free_claim')), findsNothing);
    await capture('reward-expired-remains');
    await tester.tap(find.byKey(const ValueKey('reward_watch_ad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ads_start')));
    await tester.runAsync(
      () => verified.future.timeout(const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle();
    expect((await product.repository.wallet()).balance, 20);
    await capture('reward-ssv-verified');
    final intentId = ads.intent!.id;
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    expect((await product.repository.wallet()).balance, 20);
    await capture('reward-explicit-ad-claim');
    changed = Completer<RecordDay>();
    await tester.tap(find.byKey(const ValueKey('reward_ad_claim')));
    day = (await tester.runAsync(
      () => changed.future.timeout(const Duration(seconds: 20)),
    ))!;
    await tester.pumpAndSettle();
    expect(day.rewardStatus, DayRewardStatus.paid);
    expect(day.grantedPoints, 160);
    expect(product.wallet!.balance, 160);
    expect((await client.ads.getIntent(intentId)).status, 'consumed');
    expect(product.store, isNull);
    expect(product.quiz, isNull);
    await capture('reward-settled');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
