import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_review_sheet.dart';
import 'package:balmatchum_app/features/records/status_widgets.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'authenticated_quiz_test.dart';

/// Past answers as the server lists them: newest first, both indexes known.
class ReviewQuizzes extends Quizzes {
  ReviewQuizzes(this.past);
  final List<QuizQuestion> past;
  Object? pageFailure;
  Object? reviewFailure;

  /// Holds a page in flight until completed.
  Completer<void>? hold;
  @override
  Future<List<QuizQuestion>> history(int? before) async {
    cursors.add(before);
    if (hold case final gate?) await gate.future;
    if (pageFailure != null) throw pageFailure!;
    return past
        .where((q) => before == null || q.assignmentId < before)
        .take(30)
        .toList();
  }

  @override
  Future<QuizQuestion> review(int id) async {
    reviews.add(id);
    if (reviewFailure != null) throw reviewFailure!;
    return past.firstWhere((q) => q.assignmentId == id);
  }
}

QuizQuestion answered(int id, {required int answer, int? correct = 0}) =>
    question(
      id,
      answered: true,
    ).copyWith(answerIndex: answer, correctIndex: correct);

void main() {
  late ReviewQuizzes repository;
  late QuizController controller;

  void use(List<QuizQuestion> past) {
    repository = ReviewQuizzes(past);
    controller = QuizController(repository, isCurrentAccount: () => true);
    addTearDown(() {
      controller.dispose();
      repository.client.close();
    });
  }

  Future<void> openSheet(WidgetTester tester) async {
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz_history')));
    await tester.pumpAndSettle();
    expect(find.byType(QuizReviewSheet), findsOneWidget);
  }

  TextChip? result(WidgetTester tester, int id) {
    final chip = find.byKey(ValueKey('quiz_history_${id}_result'));
    return chip.evaluate().isEmpty ? null : tester.widget<TextChip>(chip);
  }

  testWidgets('results come from both indexes and the summary counts them', (
    tester,
  ) async {
    use([
      answered(9, answer: 0),
      // Points were granted, yet the answer was wrong.
      answered(8, answer: 1),
      answered(7, answer: 2, correct: 2),
      // No correct index from the server: nothing is judged.
      answered(6, answer: 1, correct: null),
    ]);
    await openSheet(tester);
    expect(result(tester, 9)!.tone, TextChipTone.record);
    expect(result(tester, 8)!.tone, TextChipTone.error);
    expect(result(tester, 7)!.tone, TextChipTone.record);
    expect(result(tester, 6), isNull);
    final summary = tester
        .widget<Text>(find.byKey(const ValueKey('quiz_review_summary')))
        .data!;
    // The judged questions read so far, and the right ones among them.
    expect(RegExp(r'\d+').allMatches(summary).map((m) => int.parse(m[0]!)), [
      3,
      2,
    ]);
    expect(repository.requests, isEmpty);
  });

  testWidgets('no answered questions yet reads as an empty list', (
    tester,
  ) async {
    use(const []);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('quiz_history_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_review_summary')), findsNothing);
    expect(find.byKey(const ValueKey('quiz_history_more')), findsNothing);
  });

  testWidgets('pages load once each and a failed page keeps the list', (
    tester,
  ) async {
    use([for (var id = 45; id >= 1; id--) answered(id, answer: 0)]);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('quiz_history_16')), findsOneWidget);
    final more = find.byKey(const ValueKey('quiz_history_more'));
    repository.pageFailure = const SocketException('offline');
    final page = repository.hold = Completer<void>();
    await tester.ensureVisible(more);
    // A double tap while the page is in flight asks for it once.
    await tester.tap(more);
    await tester.tap(more, warnIfMissed: false);
    await tester.pump();
    expect(repository.cursors, [null, 16]);
    repository.hold = null;
    page.complete();
    await tester.pumpAndSettle();
    // The failure keeps every listed question and offers its own retry.
    expect(find.byKey(const ValueKey('quiz_history_16')), findsOneWidget);
    final retry = find.byKey(const ValueKey('quiz_history_retry'));
    expect(retry, findsOneWidget);
    repository.pageFailure = null;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    // The same page is asked again, then the list grows without repeats.
    expect(repository.cursors, [null, 16, 16]);
    expect(find.byKey(const ValueKey('quiz_history_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_history_16')), findsOneWidget);
    expect(more, findsNothing);
  });

  testWidgets('a review keeps the list, and a failed one retries only itself', (
    tester,
  ) async {
    use([answered(9, answer: 0), answered(8, answer: 1)]);
    await openSheet(tester);
    repository.reviewFailure = const SocketException('offline');
    await tester.tap(find.byKey(const ValueKey('quiz_history_8')));
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('quiz_history_retry'));
    expect(retry, findsOneWidget);
    repository.reviewFailure = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repository.reviews, [8, 8]);
    expect(find.byKey(const ValueKey('quiz_result_wrong')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_8_past_points')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_8_award_new')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quiz_review_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz_history_9')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_history_8')), findsOneWidget);
    expect(repository.cursors, [null]);
    expect(repository.requests, isEmpty);
  });

  testWidgets('closing the sheet leaves the answered quiz as it was', (
    tester,
  ) async {
    use([answered(9, answer: 0)]);
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz_1_choice_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsOneWidget);
    final today = controller.today;
    for (final close in ['button', 'drag']) {
      await tester.tap(find.byKey(const ValueKey('quiz_history')));
      await tester.pumpAndSettle();
      expect(find.byType(QuizReviewSheet), findsOneWidget);
      if (close == 'button') {
        await tester.tap(find.byKey(const ValueKey('quiz_review_close')));
      } else {
        await tester.fling(
          find.byKey(const ValueKey('quiz_review_close')),
          const Offset(0, 600),
          1500,
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(QuizReviewSheet), findsNothing, reason: close);
    }
    expect(identical(controller.today, today), isTrue);
    expect(find.byKey(const ValueKey('quiz_1_award_new')), findsOneWidget);
    expect(repository.requests, hasLength(1));
  });
}
