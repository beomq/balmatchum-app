import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sheet.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ads/ads_fakes.dart' show FakeAdsSdk;
import 'authenticated_quiz_test.dart';

/// Echoes the requested target like the server. [status] is what the SSV
/// callback has made of the intent so far.
class QuizAdsServer implements AdsServer {
  QuizAdsServer(this.events);
  final List<String> events;
  String status = 'pending';
  String purpose = '';
  String date = '';
  int revision = 0;
  @override
  bool isCurrent = true;
  @override
  void close() {}
  AdIntent get intent => AdIntent(
    id: 'intent-1',
    purpose: purpose,
    targetDate: date,
    targetRevision: revision,
    adUnit: 'unit',
    userId: 'A',
    customData: 'intent-1',
    status: status,
    createdAt: DateTime.utc(2026),
    eventExpiresAt: DateTime.utc(2027),
    acceptUntil: DateTime.utc(2027),
  );
  @override
  Future<AdIntent> create(String purpose, String date, int revision) async {
    events.add('create');
    this.purpose = purpose;
    this.date = date;
    this.revision = revision;
    return intent;
  }

  @override
  Future<AdIntent> get(String id) async {
    events.add('get');
    return intent;
  }
}

/// Keeps each request's answer like the server's request ledger: the same
/// request id returns the kept question and never opens another.
class LedgerQuizzes extends Quizzes {
  final kept = <String, QuizQuestion>{};
  final intents = <String>[];
  int unlocks = 0;

  /// The next unlock commits, then its answer is lost on the way back.
  bool loseNextAnswer = false;

  /// Holds every answer until completed.
  Completer<void>? hold;
  @override
  Future<QuizQuestion> unlockExtra(
    String date,
    int revision,
    String intent,
    String id,
  ) async {
    requests.add((id, null, intent));
    intents.add(intent);
    if (hold case final gate?) await gate.future;
    if (kept[id] case final answer?) return answer;
    unlocks++;
    current = current.copyWith(
      extra: question(2),
      extraStatus: 'issued',
      extraRevision: null,
    );
    final answer = kept[id] = question(2);
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw const SocketException('lost response');
    }
    return answer;
  }
}

void main() {
  late LedgerQuizzes ledger;
  late QuizController controller;
  setUp(() {
    ledger = LedgerQuizzes()
      ..current = QuizToday(
        premiumStatus: 'notChecked',
        date: '2026-10-19',
        status: 'ready',
        free: question(1, answered: true),
        extraStatus: 'adRequired',
        extraRevision: 1,
      );
    controller = QuizController(ledger, isCurrentAccount: () => true);
  });
  tearDown(() {
    controller.dispose();
    ledger.client.close();
  });

  /// The answered free question with its ad step, played by hand.
  Future<(QuizAdsServer, FakeAdsSdk, List<String>)> mount(
    WidgetTester tester,
  ) async {
    final events = <String>[];
    final server = QuizAdsServer(events);
    final sdk = FakeAdsSdk(events);
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: AuthenticatedQuizScreen(
          controller: controller,
          onBack: () {},
          onHome: () {},
          createAds: () async => AdsController(server: server, sdk: sdk),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (server, sdk, events);
  }

  final watch = find.byKey(const ValueKey('quiz_watch_ad'));

  Future<void> startAd(WidgetTester tester, List<String> events) async {
    await tester.ensureVisible(watch);
    await tester.tap(watch);
    // The sheet starts the ad itself; there is no 'ads_start' tap.
    await tester.pump();
    await tester.pump();
    expect(events, containsAllInOrder(['prepare', 'create', 'show']));
    expect(find.byKey(const ValueKey('ads_start')), findsNothing);
  }

  testWidgets('a completed ad opens the extra question once, no second tap', (
    tester,
  ) async {
    final (server, sdk, events) = await mount(tester);
    await startAd(tester, events);
    expect(server.purpose, 'extraQuiz');
    // The SSV callback verifies the view, then the ad closes.
    server.status = 'verified';
    sdk.ad.reward();
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(find.byType(AdsSheet), findsNothing);
    expect(ledger.intents, ['intent-1']);
    expect(ledger.requests, hasLength(1));
    expect(ledger.unlocks, 1);
    expect(find.byKey(const ValueKey('quiz_2_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_unlock')), findsNothing);
    expect(controller.verifiedIntent, isNull);
  });

  testWidgets('an ad closed before the server verifies it opens nothing', (
    tester,
  ) async {
    final (server, sdk, events) = await mount(tester);
    await startAd(tester, events);
    // Closed early: no SSV callback, so the intent stays pending.
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ads_status_pending')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    // A verification arriving after the close changes nothing.
    server.status = 'verified';
    await tester.pumpAndSettle();
    expect(ledger.requests, isEmpty);
    expect(controller.verifiedIntent, isNull);
    expect(find.byKey(const ValueKey('quiz_unlock')), findsNothing);
    expect(watch, findsOneWidget);
  });

  testWidgets(
    'a lost answer is re-checked with the same request and opens at most once',
    (tester) async {
      ledger.loseNextAnswer = true;
      final (server, sdk, events) = await mount(tester);
      await startAd(tester, events);
      server.status = 'verified';
      sdk.ad.reward();
      sdk.ad.dismiss();
      await tester.pumpAndSettle();
      // The unlock committed and its answer was lost. It stays pending and
      // nothing sends it again by itself.
      expect(ledger.unlocks, 1);
      expect(ledger.requests, hasLength(1));
      expect(controller.hasPending, isTrue);
      expect(find.byKey(const ValueKey('quiz_unlock')), findsNothing);
      await tester.pumpAndSettle();
      expect(ledger.requests, hasLength(1));
      final recheck = find.byKey(const ValueKey('quiz_retry_request'));
      await tester.ensureVisible(recheck);
      await tester.tap(recheck);
      await tester.pumpAndSettle();
      // The same request returns the kept question; nothing else opens.
      expect(ledger.requests, hasLength(2));
      expect(ledger.requests.map((r) => r.$1).toSet(), hasLength(1));
      expect(ledger.intents, ['intent-1', 'intent-1']);
      expect(ledger.unlocks, 1);
      expect(controller.hasPending, isFalse);
      expect(find.byKey(const ValueKey('quiz_2_card')), findsOneWidget);
    },
  );

  testWidgets('a double tap and repeated ad events run one ad and one unlock', (
    tester,
  ) async {
    final (server, sdk, events) = await mount(tester);
    await tester.ensureVisible(watch);
    await tester.tap(watch);
    await tester.tap(watch, warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AdsSheet), findsOneWidget);
    expect(events.where((e) => e == 'create'), hasLength(1));
    // Hold the unlock's answer to look at the screen while it is in flight.
    final answer = ledger.hold = Completer<void>();
    // An SDK that reports each event twice.
    server.status = 'verified';
    sdk.ad.reward();
    sdk.ad.reward();
    sdk.ad.dismiss();
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(events.where((e) => e == 'get'), hasLength(1));
    expect(ledger.requests, hasLength(1));
    // No second way to unlock while the first one is in flight.
    expect(find.byKey(const ValueKey('quiz_unlock')), findsNothing);
    expect(tester.widget<ButtonStyleButton>(watch).onPressed, isNull);
    answer.complete();
    await tester.pumpAndSettle();
    expect(ledger.requests, hasLength(1));
    expect(ledger.unlocks, 1);
    expect(find.byKey(const ValueKey('quiz_2_card')), findsOneWidget);
  });
}
