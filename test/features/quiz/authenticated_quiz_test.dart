import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_app/features/quiz/quiz_review_sheet.dart';
import 'package:balmatchum_app/features/quiz/quiz_widgets.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/wardrobe/dog_sprite.dart';
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
  Quizzes({super.billing}) : super(Client('http://localhost/'), 'A');
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
    // A held answer lands like any other once the test releases it.
    final result =
        await (pendingAnswerResult?.future ??
            Future.value(
              question(
                q.assignmentId,
                answered: true,
              ).copyWith(answerIndex: index),
            ));
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
    // Assignments 40..11, then 10, then nothing older.
    return before == null
        ? List.generate(30, (i) => question(40 - i, answered: true))
        : before == 11
        ? [question(10, answered: true)]
        : [];
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

  Future<void> mount(
    WidgetTester tester, {
    AdsController? ads,
    VoidCallback? onHome,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: AuthenticatedQuizScreen(
          controller: controller,
          onBack: () {},
          onHome: onHome ?? () {},
          createAds: ads == null ? null : () async => ads,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  QuizOption option(WidgetTester tester, int id, int index) => tester
      .widget<QuizOption>(find.byKey(ValueKey('quiz_${id}_choice_$index')));

  testWidgets('the question and its choices lead; no retry shows by default', (
    tester,
  ) async {
    await mount(tester);
    final card = tester.getRect(find.byKey(const ValueKey('quiz_1_card')));
    final choice = tester.getRect(
      find.byKey(const ValueKey('quiz_1_choice_1')),
    );
    final rules = tester.getRect(find.byKey(const ValueKey('quiz_rules')));
    expect(
      tester.getRect(find.byKey(const ValueKey('quiz_chip'))).bottom,
      lessThanOrEqualTo(card.top),
    );
    expect(card.bottom, lessThanOrEqualTo(choice.top));
    expect(choice.bottom, lessThanOrEqualTo(rules.top));
    for (final key in [
      'quiz_reload',
      'quiz_retry_request',
      'quiz_check_premium',
      'quiz_premium_status',
      'quiz_notice',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
  });

  testWidgets('one tap sends one answer and the result waits for the server', (
    tester,
  ) async {
    final answer = repository.pendingAnswerResult = Completer<QuizQuestion>();
    await mount(tester);
    // A double tap in one frame, then taps while the request is in flight.
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_1')));
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_1')));
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_0')));
    await tester.pump();
    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.$2, 1);
    expect(option(tester, 1, 1).state, QuizOptionState.sending);
    expect(option(tester, 1, 0).state, QuizOptionState.idle);
    expect(option(tester, 1, 0).onTap, isNull);
    // Nothing is judged or granted before the server answers.
    expect(find.byKey(const ValueKey('quiz_result_wrong')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_result_correct')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsNothing);
    answer.complete(question(1, answered: true));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    // Wrong: the real answer and the user's own each have a mark and word.
    expect(find.byKey(const ValueKey('quiz_result_wrong')), findsOneWidget);
    expect(option(tester, 1, 0).state, QuizOptionState.correct);
    expect(option(tester, 1, 0).tag, isNotNull);
    expect(option(tester, 1, 1).state, QuizOptionState.wrong);
    expect(option(tester, 1, 1).tag, isNotNull);
    expect(option(tester, 1, 1).selected, isTrue);
    expect(option(tester, 1, 1).onTap, isNull);
    // The first submission's grant, from the server's answer.
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsOneWidget);
  });

  testWidgets('a right answer marks its choice and the rest stay readable', (
    tester,
  ) async {
    var home = 0;
    await mount(tester, onHome: () => home++);
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz_result_correct')), findsOneWidget);
    expect(option(tester, 1, 0).state, QuizOptionState.correct);
    expect(option(tester, 1, 0).tag, isNull);
    expect(option(tester, 1, 1).state, QuizOptionState.rest);
    final rest = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('quiz_1_choice_1')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(rest.style?.color, MeetingColors.muted);
    await tester.ensureVisible(find.byKey(const ValueKey('quiz_home')));
    await tester.tap(find.byKey(const ValueKey('quiz_home')));
    expect(home, 1);
  });

  testWidgets('a lost answer keeps its choice and retries the same request', (
    tester,
  ) async {
    await mount(tester);
    repository.failure = const SocketException('lost');
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_1')));
    await tester.pumpAndSettle();
    // No result or grant is made up after the loss.
    expect(find.byKey(const ValueKey('quiz_result_wrong')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsNothing);
    expect(option(tester, 1, 1).state, QuizOptionState.chosen);
    expect(option(tester, 1, 0).onTap, isNull);
    final retry = find.byKey(const ValueKey('quiz_retry_request'));
    expect(retry, findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_reload')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_0')));
    await tester.pump();
    expect(repository.requests, hasLength(1));
    repository.failure = null;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(repository.requests[1], repository.requests[0]);
    expect(find.byKey(const ValueKey('quiz_result_wrong')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsOneWidget);
    expect(retry, findsNothing);
  });

  testWidgets('reopening an answered question shows its record, not a grant', (
    tester,
  ) async {
    repository.current = repository.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    await mount(tester);
    expect(find.byKey(const ValueKey('quiz_1_past_points')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_hint')), findsNothing);
    // Conditions stay on the card; source and review open from the result.
    expect(find.byKey(const ValueKey('quiz_conditions_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_1_details')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quiz_1_info')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quiz_1_details')),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
    expect(repository.requests, isEmpty);
  });

  testWidgets('a verified ad still waits for the explicit unlock', (
    tester,
  ) async {
    repository.current = repository.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    final ads = AdsController(server: TestAdsServer(), sdk: ReadySdk());
    await mount(tester, ads: ads);
    await tester.ensureVisible(find.byKey(const ValueKey('quiz_watch_ad')));
    await tester.tap(find.byKey(const ValueKey('quiz_watch_ad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ads_start')));
    await tester.pumpAndSettle();
    expect(ads.status, AdsStatus.verified);
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    expect(repository.requests, isEmpty);
    final unlock = find.byKey(const ValueKey('quiz_unlock'));
    await tester.ensureVisible(unlock);
    await tester.tap(unlock);
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    expect(find.byKey(const ValueKey('quiz_2_card')), findsOneWidget);
  });

  testWidgets('cancelled sheet cannot unlock', (tester) async {
    repository.current = repository.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    // The view is not verified when the sheet opens; the stub ad then fails.
    await mount(
      tester,
      ads: AdsController(
        server: TestAdsServer()..status = 'pending',
        sdk: ReadySdk(),
      ),
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

  testWidgets('the reload retry shows only once a load needs repeating', (
    tester,
  ) async {
    await mount(tester);
    final reload = find.byKey(const ValueKey('quiz_reload'));
    expect(reload, findsNothing);
    // A definitive rejection leaves the latest state to be read again.
    repository.failure = ProductException(code: 'quizClosed');
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_1')));
    await tester.pumpAndSettle();
    expect(controller.needsRefresh, isTrue);
    expect(reload, findsOneWidget);
    repository.failure = null;
    await tester.ensureVisible(reload);
    await tester.tap(reload);
    await tester.pumpAndSettle();
    expect(controller.needsRefresh, isFalse);
    expect(reload, findsNothing);
  });

  testWidgets('a failed first load offers the retry', (tester) async {
    repository.pendingToday = Completer<QuizToday>();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: AuthenticatedQuizScreen(
          controller: controller,
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    final reload = find.byKey(const ValueKey('quiz_reload'));
    expect(reload, findsNothing, reason: 'still loading');
    repository.pendingToday!.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();
    expect(reload, findsOneWidget);
    repository.pendingToday = null;
    await tester.tap(reload);
    await tester.pumpAndSettle();
    expect(controller.today, isNotNull);
    expect(reload, findsNothing);
  });

  testWidgets('production hides test markers and the unobserved benefit', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_premium_status')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_check_premium')), findsNothing);
    debugFixtureLabelsVisible = true;
    addTearDown(() => debugFixtureLabelsVisible = null);
    await mount(tester);
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsOneWidget);
  });

  testWidgets('the own companion joins a result and the empty state', (
    tester,
  ) async {
    const dog = 'assets/first_meeting/dogs/pug.png';
    Future<void> show(String key) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: AuthenticatedQuizScreen(
            key: ValueKey(key),
            controller: controller,
            onBack: () {},
            onHome: () {},
            dogAsset: dog,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String shown(String key) => tester
        .widget<DogSprite>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(DogSprite),
          ),
        )
        .asset;

    await show('open');
    expect(find.byKey(const ValueKey('quiz_1_dog')), findsNothing);
    repository.current = repository.current.copyWith(
      free: question(1, answered: true),
      extraStatus: 'adRequired',
      extraRevision: 1,
    );
    await show('answered');
    expect(shown('quiz_1_dog'), dog);
    repository.current = QuizToday(
      premiumStatus: 'notChecked',
      date: '2026-10-19',
      status: 'contentUnavailable',
      extraStatus: 'contentUnavailable',
    );
    await show('empty');
    expect(shown('quiz_empty_dog'), dog);
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

  testWidgets('loading, a failed load, no content and all used differ', (
    tester,
  ) async {
    const states = [
      'product_loading',
      'quiz_reload',
      'quiz_status_contentUnavailable',
      'quiz_status_exhausted',
    ];
    void only(String shown) {
      for (final key in states) {
        expect(
          find.byKey(ValueKey(key)),
          key == shown ? findsOneWidget : findsNothing,
          reason: key,
        );
      }
    }

    repository.pendingToday = Completer<QuizToday>();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: AuthenticatedQuizScreen(
          controller: controller,
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    only('product_loading');
    expect(find.byKey(const ValueKey('quiz_chip')), findsNothing);
    repository.pendingToday!.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();
    // A failure is not "preparing": no chip, only its retry.
    only('quiz_reload');
    expect(find.byKey(const ValueKey('quiz_chip')), findsNothing);
    repository.pendingToday = null;
    for (final status in ['contentUnavailable', 'exhausted']) {
      repository.current = QuizToday(
        premiumStatus: 'notChecked',
        date: '2026-10-19',
        status: status,
        // The server answers freeRequired while no free question exists.
        extraStatus: 'freeRequired',
      );
      await controller.load();
      await tester.pumpAndSettle();
      only('quiz_status_$status');
      expect(find.byKey(const ValueKey('quiz_chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('quiz_watch_ad')), findsNothing);
      expect(find.byType(QuizOption), findsNothing);
    }
    expect(repository.requests, isEmpty);
  });

  testWidgets('the empty state and the link open the same review sheet', (
    tester,
  ) async {
    repository.current = QuizToday(
      premiumStatus: 'notChecked',
      date: '2026-10-19',
      status: 'contentUnavailable',
      extraStatus: 'freeRequired',
    );
    var home = 0;
    await mount(tester, onHome: () => home++);
    for (final entry in ['quiz_empty_review', 'quiz_history']) {
      await tester.tap(find.byKey(ValueKey(entry)));
      await tester.pumpAndSettle();
      expect(find.byType(QuizReviewSheet), findsOneWidget, reason: entry);
      await tester.tap(find.byKey(const ValueKey('quiz_review_close')));
      await tester.pumpAndSettle();
      expect(find.byType(QuizReviewSheet), findsNothing);
    }
    expect(repository.cursors, [null, null]);
    await tester.tap(find.byKey(const ValueKey('product_home')));
    expect(home, 1);
    expect(repository.requests, isEmpty);
  });

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
