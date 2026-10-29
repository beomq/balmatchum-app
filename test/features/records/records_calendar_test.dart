import 'dart:async';

import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:balmatchum_app/features/records/status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'records_screen_test.dart' show host;

/// Today in these tests: Friday 2027-01-15.
final today = DateTime(2027, 1, 15);

RecordDay at(
  int d, {
  int? steps,
  StepAvailability availability = StepAvailability.confirmed,
  DayRewardStatus reward = DayRewardStatus.paid,
  int granted = 0,
}) => RecordDay(
  date: DateTime(2027, 1, d),
  revision: 1,
  steps: availability == StepAvailability.confirmed ? steps : null,
  availability: availability,
  rewardStatus: reward,
  claimablePoints: reward == DayRewardStatus.claimable ? 6 : 0,
  grantedPoints: granted,
);

/// Every kind once: walked 4, zero 5, unknown 6, no snapshot 7, deleted 8,
/// today 15 at 9,000 and a past 9,000 on 12; 9 is missing from the answer.
RecordMonth january([int todaySteps = 9000]) => RecordMonth(
  month: DateTime(2027, 1),
  days: [
    at(4, steps: 4200, granted: 42),
    at(5, steps: 0),
    at(6, availability: StepAvailability.unavailable),
    at(7, availability: StepAvailability.none),
    at(8, availability: StepAvailability.deleted),
    at(12, steps: 9000, granted: 90),
    at(15, steps: todaySteps, reward: DayRewardStatus.claimable),
    at(20, availability: StepAvailability.none),
  ],
);

const summary = RecordsSummary(
  thisWeek: 3,
  streak: 6,
  streakAtLeast: false,
  monthAverage: 7220,
);

RecordsCalendarScreen calendar({
  LoadRecordMonth? loadMonth,
  LoadRecordsSummary? loadSummary,
  LoadDayQuiz? loadQuiz,
  FutureOr<void> Function(DateTime)? onOpenDay,
  int? todayGoal = 8000,
}) => RecordsCalendarScreen(
  initialMonth: today,
  loadMonth: loadMonth ?? (month) async => january(),
  loadSummary: loadSummary,
  loadQuiz: loadQuiz,
  todayGoal: todayGoal,
  onOpenDay: onOpenDay ?? (_) {},
  onBack: () {},
  onHome: () {},
);

RecordDayCell cell(WidgetTester tester, int d) => tester.widget<RecordDayCell>(
  find.ancestor(
    of: find.byKey(ValueKey('records_day_$d')),
    matching: find.byType(RecordDayCell),
  ),
);

String text(WidgetTester tester, String key) {
  final widget = tester.widget(find.byKey(ValueKey(key)));
  return widget is Text
      ? widget.data!
      : (widget as RichText).text.toPlainText();
}

String richText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).textSpan!.toPlainText();

void main() {
  testWidgets('each day kind keeps its own cell; only today can be reached', (
    tester,
  ) async {
    await tester.pumpWidget(host(calendar()));
    await tester.pumpAndSettle();
    expect(cell(tester, 15).kind, RecordDayKind.achieved);
    expect(cell(tester, 4).kind, RecordDayKind.walked);
    expect(cell(tester, 5).kind, RecordDayKind.zero);
    expect(cell(tester, 6).kind, RecordDayKind.unknown);
    expect(cell(tester, 7).kind, RecordDayKind.none);
    expect(cell(tester, 8).kind, RecordDayKind.deleted);
    // A missing answer is no record, never unknown or zero.
    expect(cell(tester, 9).kind, RecordDayKind.none);
    expect(cell(tester, 20).kind, RecordDayKind.future);
    // The current goal is never applied to a past day (guide 7.1-5).
    expect(cell(tester, 12).kind, RecordDayKind.walked);
    // Today's border and the selection are separate flags.
    expect(cell(tester, 15).today, isTrue);
    expect(cell(tester, 15).selected, isTrue);
    expect(cell(tester, 4).today, isFalse);
    expect(cell(tester, 4).selected, isFalse);
    // No '?' box or 'k' figure in any cell.
    expect(find.text('?'), findsNothing);
    expect(find.textContaining(RegExp(r'\dk$')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('below the goal or without one, today is walked', (tester) async {
    await tester.pumpWidget(
      host(calendar(loadMonth: (month) async => january(6840))),
    );
    await tester.pumpAndSettle();
    expect(cell(tester, 15).kind, RecordDayKind.walked);
    expect(text(tester, 'records_card_percent'), '86%');
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('records_card_progress')),
    );
    expect(bar.value, closeTo(.855, .001));
    await tester.pumpWidget(
      host(
        KeyedSubtree(
          key: const ValueKey('no goal'),
          child: calendar(todayGoal: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cell(tester, 15).kind, RecordDayKind.walked);
    expect(find.byKey(const ValueKey('records_card_percent')), findsNothing);
    expect(find.byKey(const ValueKey('records_card_progress')), findsNothing);
  });

  testWidgets('a tap moves the selection and the card, nothing opens', (
    tester,
  ) async {
    final opened = <DateTime>[];
    await tester.pumpWidget(host(calendar(onOpenDay: opened.add)));
    await tester.pumpAndSettle();
    expect(richText(tester, 'records_card_steps'), contains('9,000'));
    await tester.tap(find.byKey(const ValueKey('records_day_4')));
    await tester.pumpAndSettle();
    expect(cell(tester, 4).selected, isTrue);
    expect(cell(tester, 15).selected, isFalse);
    expect(cell(tester, 15).today, isTrue);
    expect(richText(tester, 'records_card_steps'), contains('4,200'));
    // A past day has no goal: no ratio and no bar.
    expect(find.byKey(const ValueKey('records_card_percent')), findsNothing);
    expect(text(tester, 'records_card_reward'), contains('42P'));
    // States without a count say so instead of a number.
    for (final d in [6, 7, 8, 20]) {
      await tester.tap(find.byKey(ValueKey('records_day_$d')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('records_card_steps')), findsNothing);
      expect(
        find.byKey(const ValueKey('records_card_message')),
        findsOneWidget,
      );
    }
    expect(opened, isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('records_open_day')));
    await tester.tap(find.byKey(const ValueKey('records_open_day')));
    await tester.pump();
    expect(opened, [DateTime(2027, 1, 20)]);
  });

  testWidgets('another month clears the selection until a date is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(host(calendar()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records_next_month')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records_day_card')), findsNothing);
    expect(find.byKey(const ValueKey('records_select_hint')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('records_prev_month')));
    await tester.pumpAndSettle();
    expect(cell(tester, 15).selected, isTrue);
    expect(find.byKey(const ValueKey('records_day_card')), findsOneWidget);
  });

  testWidgets('the last selection wins over a slower earlier quiz answer', (
    tester,
  ) async {
    final pending = <DateTime, Completer<DayQuiz>>{};
    await tester.pumpWidget(
      host(
        calendar(
          loadQuiz: (date) => (pending[date] = Completer<DayQuiz>()).future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records_day_4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('records_day_12')));
    await tester.pump();
    pending[DateTime(2027, 1, 12)]!.complete(
      const DayQuiz(answered: 1, correct: 1, points: 2),
    );
    await tester.pump();
    pending[DateTime(2027, 1, 4)]!.complete(
      const DayQuiz(answered: 1, correct: 0, points: 0),
    );
    pending[today]!.complete(const DayQuiz(answered: 0, correct: 0, points: 0));
    await tester.pumpAndSettle();
    expect(richText(tester, 'records_card_steps'), contains('9,000'));
    final chip = tester.widget<TextChip>(
      find.ancestor(
        of: find.byKey(const ValueKey('records_card_quiz')),
        matching: find.byType(TextChip),
      ),
    );
    expect(chip.tone, TextChipTone.record);
    expect(chip.label, contains('+2P'));
  });

  testWidgets('month answers in reverse order keep the last month', (
    tester,
  ) async {
    final pending = <int, Completer<RecordMonth>>{};
    await tester.pumpWidget(
      host(
        calendar(
          loadMonth: (month) {
            if (month.month == 1) return Future.value(january());
            return (pending[month.month] = Completer<RecordMonth>()).future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records_next_month')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('records_next_month')));
    await tester.pump();
    pending[3]!.complete(RecordMonth(month: DateTime(2027, 3), days: []));
    await tester.pump();
    pending[2]!.complete(RecordMonth(month: DateTime(2027, 2), days: []));
    await tester.pumpAndSettle();
    expect(cell(tester, 31).date, DateTime(2027, 3, 31));
  });

  testWidgets('tiles show the aggregate, or no number and one retry', (
    tester,
  ) async {
    var fail = true;
    var reads = 0;
    await tester.pumpWidget(
      host(
        calendar(
          loadSummary: () async {
            reads++;
            if (fail) throw Exception('offline');
            return summary;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in ['records_week', 'records_streak', 'records_average']) {
      expect(text(tester, key), isNot(contains(RegExp(r'\d'))));
    }
    fail = false;
    await tester.tap(find.byKey(const ValueKey('records_summary_retry')));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byKey(const ValueKey('records_summary_retry')), findsNothing);
    expect(text(tester, 'records_week'), contains('3'));
    expect(text(tester, 'records_streak'), contains('6'));
    expect(text(tester, 'records_average'), contains('7,220'));
  });

  testWidgets('a lower-bound streak and a month without a count', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        calendar(
          loadSummary: () async => const RecordsSummary(
            thisWeek: 0,
            streak: 31,
            streakAtLeast: true,
            monthAverage: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      text(tester, 'records_streak'),
      allOf(contains('31'), contains('이상')),
    );
    expect(text(tester, 'records_average'), isNot(contains(RegExp(r'\d'))));
  });

  testWidgets('no aggregate source means no tiles at all', (tester) async {
    await tester.pumpWidget(host(calendar()));
    await tester.pumpAndSettle();
    expect(find.byType(StatTile), findsNothing);
  });

  testWidgets('coming back from a detail rereads the month and the tiles', (
    tester,
  ) async {
    var months = 0;
    var summaries = 0;
    var deleted = false;
    final back = Completer<void>();
    await tester.pumpWidget(
      host(
        calendar(
          loadMonth: (month) async {
            months++;
            if (!deleted) return january();
            return RecordMonth(
              month: month,
              days: [at(15, availability: StepAvailability.deleted)],
            );
          },
          loadSummary: () async {
            summaries++;
            return summary;
          },
          onOpenDay: (_) => back.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('records_open_day')));
    await tester.tap(find.byKey(const ValueKey('records_open_day')));
    await tester.pumpAndSettle();
    expect((months, summaries), (1, 1));
    // The detail deleted today, then closed.
    deleted = true;
    back.complete();
    await tester.pumpAndSettle();
    expect((months, summaries), (2, 2));
    expect(cell(tester, 15).kind, RecordDayKind.deleted);
    expect(cell(tester, 15).selected, isTrue);
    expect(find.byKey(const ValueKey('records_card_message')), findsOneWidget);
  });
}
