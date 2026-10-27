import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../daily_activity/reward_panel_test.dart' show TestAdsServer, ReadySdk;

QuizQuestion question(int id, {bool answered = false}) => QuizQuestion(
  assignmentId: id,
  date: '2026-10-19',
  slot: id == 1 ? 'free' : 'extra',
  questionId: 'test-question-$id',
  version: 1,
  question: '테스트 문제 $id',
  choices: ['테스트 선택 A', '테스트 선택 B'],
  conditions: '자동 테스트 전용 조건',
  reviewedAt: '2026-10-01',
  reviewedBy: 'testFixture',
  answerIndex: answered ? 1 : null,
  correctIndex: answered ? 0 : null,
  explanation: answered ? '테스트 해설' : null,
  source: answered ? 'https://example.invalid/test' : null,
  answeredAt: answered ? DateTime.utc(2026, 10, 19) : null,
  awardedPoints: answered ? 2 : 0,
  policyVersion: 'quiz-test-fixture-not-production',
  fixtureLabel: 'quiz-test-fixture-not-production',
);

class Quizzes extends QuizRepository {
  Quizzes() : super(Client('http://localhost/'), 'A');
  QuizToday current = QuizToday(
    premiumStatus: 'notChecked',
    date: '2026-10-19',
    status: 'ready',
    free: question(1),
    extraStatus: 'freeRequired',
  );
  Object? failure;
  Completer<QuizToday>? pendingToday;
  Completer<QuizQuestion>? pendingAnswerResult;
  final requests = <(String, int?, String?)>[];
  final cursors = <int?>[];
  final reviews = <int>[];
  @override
  Future<QuizToday> getToday() async =>
      pendingToday == null ? current : pendingToday!.future;
  @override
  Future<QuizQuestion> answer(QuizQuestion q, int index, String id) async {
    requests.add((id, index, null));
    if (failure != null) throw failure!;
    if (pendingAnswerResult != null) return pendingAnswerResult!.future;
    final result = question(q.assignmentId, answered: true);
    current = current.copyWith(
      free: result,
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    return result;
  }

  @override
  Future<QuizQuestion> unlockExtra(
    String date,
    int revision,
    String intent,
    String id,
  ) async {
    requests.add((id, null, intent));
    if (failure != null) throw failure!;
    current = current.copyWith(
      extra: question(2),
      extraStatus: 'issued',
      extraRevision: null,
    );
    return question(2);
  }

  @override
  Future<List<QuizQuestion>> history(int? before) async {
    cursors.add(before);
    if (failure != null) throw failure!;
    return before == null
        ? List.generate(30, (i) => question(40 - i, answered: true))
        : [question(10, answered: true)];
  }

  @override
  Future<QuizQuestion> review(int id) async {
    reviews.add(id);
    if (failure != null) throw failure!;
    return question(id, answered: true);
  }
}

void main() {
  late Quizzes repository;
  late QuizController controller;
  setUp(() {
    repository = Quizzes();
    controller = QuizController(repository, isCurrentAccount: () => true);
  });
  tearDown(() {
    controller.dispose();
    repository.client.close();
  });

  test('answer loss locks payload and preserves request id', () async {
    await controller.load();
    repository.failure = const SocketException('lost');
    await controller.answer(question(1), 1);
    expect(controller.hasPending, isTrue);
    expect(controller.pendingAnswer, 1);
    await controller.answer(question(1), 0);
    expect(repository.requests.length, 1);
    repository.failure = null;
    await controller.retry();
    expect(repository.requests[0], repository.requests[1]);
    expect(controller.today!.free!.awardedPoints, 2);
    expect(controller.hasPending, isFalse);
    expect(controller.today!.extraStatus, 'adRequired');
  });

  test(
    'verified extra requires explicit action and retry preserves intent and id',
    () async {
      await controller.load();
      await controller.answer(question(1), 1);
      final ad = await TestAdsServer().create('extraQuiz', '2026-10-19', 1);
      controller.captureVerified(
        ad.copyWith(purpose: 'dailyReward'),
        '2026-10-19',
        1,
      );
      expect(controller.verifiedIntent, isNull);
      controller.captureVerified(ad, '2026-10-19', 1);
      expect(repository.requests.length, 1);
      repository.failure = const SocketException('lost');
      await controller.unlockExtra();
      repository.failure = null;
      await controller.retry();
      expect(repository.requests[1], repository.requests[2]);
      expect(controller.today!.extra!.assignmentId, 2);
      expect(controller.verifiedIntent, isNull);
    },
  );

  for (final operation in ['load', 'answer', 'history', 'review']) {
    test('late $operation cannot cross account boundary', () async {
      var active = true;
      controller.dispose();
      controller = QuizController(repository, isCurrentAccount: () => active);
      await controller.load();
      if (operation == 'load') {
        repository.pendingToday = Completer<QuizToday>();
        final run = controller.load();
        active = false;
        repository.pendingToday!.complete(
          repository.current.copyWith(status: 'exhausted'),
        );
        await run;
        expect(controller.today!.status, 'ready');
      } else if (operation == 'answer') {
        repository.pendingAnswerResult = Completer<QuizQuestion>();
        final run = controller.answer(question(1), 1);
        active = false;
        repository.pendingAnswerResult!.complete(question(1, answered: true));
        await run;
        expect(controller.today!.free!.answerIndex, isNull);
      } else {
        final run = operation == 'history'
            ? controller.history(null)
            : controller.review(1);
        final rejected = expectLater(run, throwsStateError);
        active = false;
        await rejected;
      }
    });
  }

  test(
    'definitive stale rejection allows refresh, not blind mutation',
    () async {
      await controller.load();
      repository.failure = ProductException(code: 'quizClosed');
      await controller.answer(question(1), 0);
      expect(controller.hasPending, isFalse);
      expect(controller.needsRefresh, isTrue);
      await controller.answer(question(1), 0);
      expect(repository.requests.length, 1);
    },
  );

  Future<void> mount(WidgetTester tester, {AdsController? ads}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: AuthenticatedQuizScreen(
          controller: controller,
          onBack: () {},
          onHome: () {},
          createAds: ads == null ? null : () async => ads,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'verified sheet close preserves explicit unlock, wrong answer earns historical two',
    (tester) async {
      final ads = AdsController(server: TestAdsServer(), sdk: ReadySdk());
      await mount(tester, ads: ads);
      await tester.tap(find.byKey(const ValueKey('quiz_1_choice_1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('quiz_1_submit')));
      await tester.tap(find.byKey(const ValueKey('quiz_1_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quiz_1_past_points')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('quiz_watch_ad')));
      await tester.tap(find.byKey(const ValueKey('quiz_watch_ad')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ads_start')));
      await tester.pumpAndSettle();
      expect(ads.status, AdsStatus.verified);
      expect(repository.requests.length, 1);
      await tester.tap(find.byKey(const ValueKey('ads_close')));
      await tester.pumpAndSettle();
      expect(repository.requests.length, 1);
      await tester.ensureVisible(find.byKey(const ValueKey('quiz_unlock')));
      await tester.tap(find.byKey(const ValueKey('quiz_unlock')));
      await tester.pumpAndSettle();
      expect(repository.requests.length, 2);
      expect(controller.today!.extra!.assignmentId, 2);
    },
  );

  testWidgets('cancelled sheet cannot unlock', (tester) async {
    repository.current = repository.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    await mount(
      tester,
      ads: AdsController(server: TestAdsServer(), sdk: ReadySdk()),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('quiz_watch_ad')));
    await tester.tap(find.byKey(const ValueKey('quiz_watch_ad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz_unlock')), findsNothing);
    expect(repository.requests, isEmpty);
  });

  testWidgets('history paginates assignment cursor and review never mutates', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('quiz_history')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('quiz_history_more')));
    await tester.tap(find.byKey(const ValueKey('quiz_history_more')));
    await tester.pumpAndSettle();
    expect(repository.cursors, [null, 11]);
    await tester.ensureVisible(find.byKey(const ValueKey('quiz_history_10')));
    await tester.tap(find.byKey(const ValueKey('quiz_history_10')));
    await tester.pumpAndSettle();
    expect(repository.reviews, [10]);
    expect(find.byKey(const ValueKey('quiz_10_past_points')), findsOneWidget);
    expect(repository.requests, isEmpty);
  });

  for (final status in ['contentUnavailable', 'exhausted']) {
    testWidgets('$status has no answer or ad mutation', (tester) async {
      repository.current = QuizToday(
        premiumStatus: 'notChecked',
        date: '2026-10-19',
        status: status,
        extraStatus: status,
      );
      await mount(tester);
      expect(find.byKey(ValueKey('quiz_status_$status')), findsOneWidget);
      expect(find.byKey(const ValueKey('quiz_watch_ad')), findsNothing);
      expect(find.byKey(const ValueKey('quiz_1_submit')), findsNothing);
    });
  }

  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('quiz state render $width dark $dark', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await (FontLoader('Pretendard')..addFont(
                rootBundle.load('assets/fonts/PretendardVariable.ttf'),
              ))
              .load();
        });
        for (final state in [
          'contentUnavailable',
          'exhausted',
          'freeRequired',
          'adRequired',
          'issued',
        ]) {
          repository.current = QuizToday(
            premiumStatus: 'notChecked',
            date: '2026-10-19',
            status: state == 'contentUnavailable' || state == 'exhausted'
                ? state
                : 'ready',
            free: state == 'freeRequired'
                ? question(1)
                : state == 'adRequired' || state == 'issued'
                ? question(1, answered: true)
                : null,
            extra: state == 'issued' ? question(2) : null,
            extraStatus: state,
            extraRevision: state == 'adRequired' ? 1 : null,
          );
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: dark
                    ? ThemeData(
                        brightness: Brightness.dark,
                        fontFamily: 'Pretendard',
                      )
                    : meetingTheme(),
                home: AuthenticatedQuizScreen(
                  key: ValueKey(state),
                  controller: controller,
                  onBack: () {},
                  onHome: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('QUIZ_RENDER')) {
            Future<void> shot(String suffix) async {
              await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${Platform.environment['RUN_TMP']}/quiz-render-$state-$width-$dark-$suffix.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            await shot('top');
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -1600),
            );
            await tester.pumpAndSettle();
            await shot('end');
          }
        }
      });
    }
  }
}
