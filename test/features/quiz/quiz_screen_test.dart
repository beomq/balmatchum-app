import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/quiz_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const quiz = QuizView(
  date: '2027-01-04',
  questionId: 'q1',
  question: '산책 중 강아지에게 준비할 것은?',
  choices: ['깨끗한 물', '초콜릿'],
  fixtureLabel: 'dev-fixture-v1',
);

QuizView answered(int answer) => QuizView(
  date: quiz.date,
  questionId: quiz.questionId,
  question: quiz.question,
  choices: quiz.choices,
  answerIndex: answer,
  correctIndex: 0,
  explanation: '깨끗한 물을 준비해요.',
  awardedPoints: answer == 0 ? 2 : 0,
  fixtureLabel: quiz.fixtureLabel,
);

Widget host(Widget child) => MaterialApp(theme: meetingTheme(), home: child);

void main() {
  testWidgets('load failure retries, submit failure keeps selection', (
    tester,
  ) async {
    var loads = 0;
    final submits = <int>[];
    final done = <QuizView>[];
    final pending = Completer<QuizView>();
    var failSubmit = true;
    await tester.pumpWidget(
      host(
        DailyQuizScreen(
          loadQuiz: () async {
            if (++loads == 1) throw Exception('offline');
            return quiz;
          },
          submitAnswer: (q, i) {
            submits.add(i);
            if (failSubmit) return Future.error(Exception('500'));
            return pending.future;
          },
          onAnswered: done.add,
          onBack: () {},
          onHome: () {},
          loadHistory: () async => [answered(0)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오늘의 퀴즈를 불러오지 못했어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('product_retry')));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsOneWidget);

    final submit = find.byKey(const ValueKey('quiz_submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('quiz_choice_1')));
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz_submit_error')), findsOneWidget);
    expect(find.text('선택됨'), findsOneWidget);
    expect(done, isEmpty);

    failSubmit = false;
    await tester.tap(submit);
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.byKey(const ValueKey('quiz_result')), findsNothing);
    pending.complete(answered(1));
    await tester.pumpAndSettle();
    expect(submits, [1, 1]);
    expect(done.length, 1);
    expect(find.text('아쉽지만 오답이에요'), findsOneWidget);
    expect(find.text('정답'), findsOneWidget);
    expect(find.text('내 답'), findsOneWidget);
    expect(find.textContaining('포인트를 받았어요'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quiz_choice_0')));
    await tester.pump();
    expect(find.text('내 답'), findsOneWidget);
  });

  testWidgets('already answered quiz opens in review without submit', (
    tester,
  ) async {
    var submits = 0;
    await tester.pumpWidget(
      host(
        DailyQuizScreen(
          loadQuiz: () async => answered(0),
          submitAnswer: (_, _) async {
            submits++;
            throw StateError('unreachable');
          },
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('정답이에요'), findsOneWidget);
    expect(find.text('2포인트를 받았어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_submit')), findsNothing);
    expect(submits, 0);
  });

  testWidgets('history reads past answers without submitting again', (
    tester,
  ) async {
    var submits = 0;
    await tester.pumpWidget(
      host(
        DailyQuizScreen(
          loadQuiz: () async => answered(0),
          loadHistory: () async => [answered(0)],
          submitAnswer: (_, _) async {
            submits++;
            return answered(0);
          },
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('지난 퀴즈 복습'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(submits, 0);
  });
}
