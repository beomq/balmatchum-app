import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../billing/billing_http_harness.dart' show presentBilling;
import 'authenticated_quiz_test.dart';

class PaidQuizzes extends Quizzes {
  PaidQuizzes({super.billing});
  Object? observationFailure;
  Completer<QuizToday>? observation;
  bool active = true;
  final paidRequests = <(String, int, String)>[];
  int observations = 0;
  @override
  Future<QuizToday> getTodayWithPremium() async {
    observations++;
    if (observationFailure != null) throw observationFailure!;
    if (observation != null) return observation!.future;
    return current.copyWith(
      paidEntitlement: active,
      premiumStatus: active ? 'active' : 'inactive',
      extraStatus: active && current.extraStatus == 'adRequired'
          ? 'premiumAvailable'
          : current.extraStatus,
    );
  }

  @override
  Future<QuizQuestion> unlockExtraWithPremium(
    String date,
    int revision,
    String id,
  ) async {
    paidRequests.add((date, revision, id));
    if (failure != null) throw failure!;
    current = current.copyWith(
      extra: question(2),
      extraStatus: 'issued',
      extraRevision: null,
    );
    return question(2);
  }
}

void main() {
  late PaidQuizzes repo;
  late QuizController c;
  setUp(() {
    repo = PaidQuizzes();
    c = QuizController(repo, isCurrentAccount: () => true);
  });
  tearDown(() {
    c.dispose();
    repo.client.close();
  });

  test('notChecked is distinct from inactive and fresh failures do not grant access', () async {
    await c.load();
    expect(c.today!.premiumStatus, 'notChecked');
    await c.checkPremium();
    expect(c.today!.extraStatus, 'freeRequired');
    await c.unlockExtraWithPremium();
    expect(repo.paidRequests, isEmpty);
    repo.active = false;
    await c.checkPremium();
    expect(c.today!.premiumStatus, 'inactive');
    repo.observationFailure = BillingException(code: 'temporarilyUnavailable');
    await c.checkPremium();
    expect(c.premiumError, 'temporarilyUnavailable');
    expect(c.premiumReady, isFalse);
  });

  test(
    'premium unlock response loss replays exact request and reconciles',
    () async {
      await c.load();
      await c.answer(question(1), 1);
      await c.checkPremium();
      expect(c.today!.extraStatus, 'premiumAvailable');
      expect(repo.paidRequests, isEmpty);
      repo.failure = const SocketException('lost');
      await c.unlockExtraWithPremium();
      expect(c.hasPending, isTrue);
      await c.answer(question(1), 0);
      await c.checkPremium();
      expect(c.beginAd(), isFalse);
      repo.failure = BillingException(code: 'staleObservation');
      await c.retry();
      expect(c.hasPending, isTrue);
      repo.failure = null;
      await c.retry();
      expect(repo.paidRequests, everyElement(repo.paidRequests.first));
      expect(c.today!.extraStatus, 'issued');
      expect(c.today!.premiumStatus, 'notChecked');
      expect(c.hasPending, isFalse);
    },
  );

  test('ad gate blocks all premium, answer and refresh requests', () async {
    await c.load();
    expect(c.beginAd(), isTrue);
    await c.checkPremium();
    await c.answer(question(1), 0);
    expect(repo.requests, isEmpty);
    expect(c.today!.premiumStatus, 'notChecked');
    c.endAd();
  });

  test('late premium observation cannot update switched account', () async {
    var current = true;
    c.dispose();
    c = QuizController(repo, isCurrentAccount: () => current);
    await c.load();
    repo.observation = Completer<QuizToday>();
    final check = c.checkPremium();
    current = false;
    repo.observation!.complete(
      repo.current.copyWith(premiumStatus: 'active', paidEntitlement: true),
    );
    await check;
    expect(c.today!.premiumStatus, 'notChecked');
  });

  /// A controller whose repository has a billing connection, as for a real
  /// account (guide 3.1 observes only then).
  (PaidQuizzes, QuizController) billed() {
    final billing = presentBilling();
    final paid = PaidQuizzes(billing: billing);
    final quiz = QuizController(paid, isCurrentAccount: () => true);
    addTearDown(() {
      quiz.dispose();
      paid.client.close();
      billing.client.close();
    });
    return (paid, quiz);
  }

  test('a billing connection observes once the extra asks for an ad', () async {
    final (paid, quiz) = billed();
    await quiz.load();
    expect(paid.observations, 0, reason: 'free question still open');
    await quiz.answer(question(1), 1);
    expect(paid.observations, 1);
    expect(quiz.today!.extraStatus, 'premiumAvailable');
    expect(paid.paidRequests, isEmpty);
  });

  test('without a billing connection nothing is observed', () async {
    repo.current = repo.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    await c.load();
    expect(repo.observations, 0);
    expect(c.today!.premiumStatus, 'notChecked');
  });

  Future<void> mountQuiz(WidgetTester tester, QuizController quiz) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthenticatedQuizScreen(
          controller: quiz,
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'entry observes the benefit; the paid unlock stays an explicit tap',
    (tester) async {
      final (paid, quiz) = billed();
      paid.current = paid.current.copyWith(
        free: question(1, answered: true),
        extraStatus: 'adRequired',
        extraRevision: 1,
      );
      await mountQuiz(tester, quiz);
      expect(paid.observations, 1);
      expect(paid.paidRequests, isEmpty);
      expect(find.byKey(const ValueKey('quiz_check_premium')), findsNothing);
      final unlock = find.byKey(const ValueKey('quiz_premium_unlock'));
      await tester.ensureVisible(unlock);
      await tester.tap(unlock);
      await tester.pumpAndSettle();
      expect(paid.paidRequests, hasLength(1));
      expect(quiz.today!.extra!.assignmentId, 2);
      expect(paid.observations, 1);
    },
  );

  testWidgets('only a failed observation offers its retry', (tester) async {
    final (paid, quiz) = billed();
    paid.current = paid.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    paid.observationFailure = BillingException(code: 'temporarilyUnavailable');
    await mountQuiz(tester, quiz);
    final retry = find.byKey(const ValueKey('quiz_check_premium'));
    expect(retry, findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_premium_status')), findsOneWidget);
    paid.observationFailure = null;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsNothing);
    expect(find.byKey(const ValueKey('quiz_premium_unlock')), findsOneWidget);
    expect(paid.paidRequests, isEmpty);
  });
}
