import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_review_sheet.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'authenticated_quiz_test.dart';

const dog = 'assets/first_meeting/dogs/pug.png';

/// The longest content the quiz should hold: a long question, long choices
/// and a long explanation.
QuizQuestion long({bool answered = false}) =>
    question(1, answered: answered).copyWith(
      question: '산책 중 반려견이 계속 앞으로 끌어 줄이 팽팽해졌어요. 이때 보호자가 가장 먼저 할 일은 무엇일까요?',
      choices: [
        '같은 힘으로 줄을 당겨 뒤로 끈다',
        '멈춰서 조용히 기다리고, 주의가 돌아오면 칭찬한 뒤 다시 천천히 걷는다',
        '속도를 높여 반려견을 따라 뛴다',
      ],
      explanation: answered
          ? '끌 때 멈추고, 보호자에게 주의를 돌리는 순간 보상하면 느슨한 줄 걷기를 배우기 쉬워요. 처음에는 짧게 자주 연습해요.'
          : null,
    );

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

  Future<void> mount(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AuthenticatedQuizScreen(
          controller: controller,
          onBack: () {},
          onHome: () {},
          dogAsset: dog,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void useSize(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Rect rect(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  for (final size in const [Size(320, 568), Size(390, 844)]) {
    testWidgets('1.15x text keeps choices and the home button apart $size', (
      tester,
    ) async {
      useSize(tester, size);
      repository.current = repository.current.copyWith(
        free: long(answered: true),
        extraStatus: 'adRequired',
        extraRevision: 1,
      );
      // The app clamps system text to 1.15x (lib/app/app.dart).
      await mount(tester, textScale: 1.15);
      expect(tester.takeException(), isNull);
      for (var i = 1; i < 3; i++) {
        expect(
          rect(tester, 'quiz_1_choice_${i - 1}').bottom,
          lessThanOrEqualTo(rect(tester, 'quiz_1_choice_$i').top),
        );
      }
      final home = find.byKey(const ValueKey('quiz_home'));
      await tester.ensureVisible(home);
      await tester.pumpAndSettle();
      expect(home.hitTestable(), findsOneWidget);
      expect(
        rect(tester, 'quiz_1_choice_2').bottom,
        lessThanOrEqualTo(rect(tester, 'quiz_1_result').top),
      );
      expect(
        rect(tester, 'quiz_1_result').bottom,
        lessThanOrEqualTo(rect(tester, 'quiz_home').top),
      );
      expect(
        find.byKey(const ValueKey('quiz_watch_ad')).hitTestable(),
        findsOneWidget,
      );
    });
  }

  testWidgets('the hint docks to the bottom edge, and scrolls when short', (
    tester,
  ) async {
    useSize(tester, const Size(390, 844));
    await mount(tester);
    final hint = rect(tester, 'quiz_hint_dog');
    // Pen: the hint row ends 20 pt above the bottom edge.
    expect(844 - hint.bottom, moreOrLessEquals(20));
    useSize(tester, const Size(320, 480));
    await mount(tester, textScale: 1.15);
    expect(tester.takeException(), isNull);
    expect(
      rect(tester, 'quiz_rules').bottom,
      lessThanOrEqualTo(rect(tester, 'quiz_hint_dog').top),
    );
    final last = find.byKey(const ValueKey('quiz_hint'));
    await tester.ensureVisible(last);
    expect(last.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'the empty state keeps its dog and button apart on a small screen',
    (tester) async {
      useSize(tester, const Size(320, 480));
      repository.current = QuizToday(
        premiumStatus: 'notChecked',
        date: '2026-10-19',
        status: 'contentUnavailable',
        extraStatus: 'freeRequired',
      );
      await mount(tester, textScale: 1.15);
      expect(tester.takeException(), isNull);
      expect(
        rect(tester, 'quiz_empty_dog').bottom,
        lessThanOrEqualTo(rect(tester, 'quiz_status_contentUnavailable').top),
      );
      final review = find.byKey(const ValueKey('quiz_empty_review'));
      await tester.ensureVisible(review);
      expect(review.hitTestable(), findsOneWidget);
    },
  );

  for (final viewport in duoViewports.keys) {
    testWidgets('the quiz and its review fit Duo $viewport', (tester) async {
      useDuoViewport(tester, viewport);
      repository.current = repository.current.copyWith(
        free: long(answered: true),
        extraStatus: 'adRequired',
        extraRevision: 1,
      );
      await mount(tester);
      expect(tester.takeException(), isNull);
      final home = find.byKey(const ValueKey('quiz_home'));
      await tester.ensureVisible(home);
      await tester.pumpAndSettle();
      expect(home.hitTestable(), findsOneWidget);
      if (viewport == 'outer portrait') {
        // Back and home move to the side rail; the panel stays beside it.
        expect(find.byType(DuoRail), findsOneWidget);
        expect(find.byType(ProductTopBar), findsNothing);
        expect(rect(tester, 'quiz_home').right, lessThanOrEqualTo(382));
      }
      final link = find.byKey(const ValueKey('quiz_history'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(QuizReviewSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      final close = find.byKey(const ValueKey('quiz_review_close'));
      expect(close.hitTestable(), findsOneWidget);
      if (viewport == 'outer portrait') {
        expect(tester.getRect(close).right, lessThanOrEqualTo(382));
      }
    });
  }
}
