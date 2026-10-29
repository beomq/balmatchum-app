import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:world_holidays/world_holidays.dart';

import '../daily_activity/product_controller.dart';
import '../daily_activity/reward_panel.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/onboarding_widgets.dart'
    show SpeechBubble, wrapByWords;
import '../wardrobe/dog_sprite.dart';
import 'product_page.dart';
import 'records_models.dart';
import 'status_widgets.dart';

final _holidays = WorldHolidays();

/// Bundled, offline KR holiday name via the package's synchronous lookup.
/// No update method is called, so this never touches the network.
String? koreanHolidayName(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final next = _holidays.getNextHoliday(
    'KR',
    from: day.subtract(const Duration(seconds: 1)),
  );
  if (next == null || !next.isOnDate(day)) return null;
  // world_holidays 2.1.2 bundles some KR records (2027+) with an English
  // `name`; prefer whichever field is actually Korean.
  final hangul = RegExp(r'[가-힣]');
  if (hangul.hasMatch(next.name)) return next.name;
  final ko = next.descriptionKo;
  return ko != null && hangul.hasMatch(ko) ? ko : next.name;
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

DateTime _dateOf(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// `M월 D일 (요일)`, as Pen titles a date.
String _dayTitle(DateTime date) =>
    '${date.month}월 ${date.day}일 (${_weekdays[date.weekday - 1]})';

/// Whole percent of [goal], rounded; an unfinished goal stops at 99 so it
/// never reads 100%, as on the home ring.
int _percent(int steps, int goal) {
  if (goal <= 0) return 100;
  final value = (steps * 100 / goal).round();
  return steps >= goal ? value : math.min(value, 99);
}

/// `steps / goal` clamped to 0..1.
double _progress(int steps, int goal) =>
    goal <= 0 ? 1 : math.min(steps / goal, 1);

bool _counted(RecordDayKind kind) => switch (kind) {
  RecordDayKind.achieved || RecordDayKind.walked || RecordDayKind.zero => true,
  _ => false,
};

/// Records month calendar (Pen `K6Z5x`): summary tiles, the month and the
/// selected date's card. A date tap selects; only the card's `자세히` opens
/// the date.
class RecordsCalendarScreen extends StatefulWidget {
  const RecordsCalendarScreen({
    required this.initialMonth,
    required this.loadMonth,
    required this.onOpenDay,
    required this.onBack,
    required this.onHome,
    this.loadSummary,
    this.loadQuiz,
    this.todayGoal,
    this.holidayName = koreanHolidayName,
    super.key,
  });

  /// The current KST date: its month opens first and its day is today. The
  /// parent passes it so tests stay deterministic.
  final DateTime initialMonth;
  final LoadRecordMonth loadMonth;

  /// Opens the date's detail; the calendar refreshes when it returns.
  final FutureOr<void> Function(DateTime) onOpenDay;
  final VoidCallback onBack;
  final VoidCallback onHome;

  /// The tiles' aggregate. Without it the page has no tiles.
  final LoadRecordsSummary? loadSummary;

  /// A date's answered quizzes for the card. Without it the card leaves
  /// the quiz out.
  final LoadDayQuiz? loadQuiz;

  /// Today's confirmed goal. Past dates have no goal on record (guide
  /// 7.1-5), so only today can show as reached.
  final int? todayGoal;
  final HolidayNameOf holidayName;

  @override
  State<RecordsCalendarScreen> createState() => _RecordsCalendarScreenState();
}

class _RecordsCalendarScreenState extends State<RecordsCalendarScreen> {
  late final DateTime today = _dateOf(widget.initialMonth);
  late DateTime month = DateTime(today.year, today.month);
  RecordMonth? data;
  String? error;
  int _request = 0;

  /// The date on the card: today while today's month shows, else the last
  /// tapped date of the shown month.
  late DateTime? selected = today;
  DayQuiz? quiz;
  bool quizFailed = false;
  int _quizRequest = 0;

  RecordsSummary? summary;
  bool summaryFailed = false;
  int _summaryRequest = 0;

  @override
  void initState() {
    super.initState();
    unawaited(loadSummary());
    unawaited(loadQuiz());
    unawaited(load());
  }

  Future<void> load() async {
    final request = ++_request;
    setState(() {
      data = null;
      error = null;
    });
    try {
      final value = await widget.loadMonth(month);
      if (mounted && request == _request) setState(() => data = value);
    } on Exception {
      if (mounted && request == _request) {
        setState(() => error = '기록을 불러오지 못했어요.');
      }
    }
  }

  Future<void> loadSummary() async {
    final load = widget.loadSummary;
    if (load == null) return;
    final request = ++_summaryRequest;
    setState(() {
      summary = null;
      summaryFailed = false;
    });
    try {
      final value = await load();
      if (mounted && request == _summaryRequest) {
        setState(() => summary = value);
      }
    } catch (_) {
      // Any failure, an account change included, leaves no number.
      if (mounted && request == _summaryRequest) {
        setState(() => summaryFailed = true);
      }
    }
  }

  /// The selected date's quizzes. A later selection wins over a slower
  /// earlier answer, as month requests do.
  Future<void> loadQuiz() async {
    final request = ++_quizRequest;
    final date = selected;
    final load = widget.loadQuiz;
    setState(() {
      quiz = null;
      quizFailed = false;
    });
    if (date == null || load == null || date.isAfter(today)) return;
    try {
      final value = await load(date);
      if (mounted && request == _quizRequest) setState(() => quiz = value);
    } catch (_) {
      if (mounted && request == _quizRequest) {
        setState(() => quizFailed = true);
      }
    }
  }

  void select(DateTime date) {
    if (date == selected) return;
    setState(() => selected = date);
    unawaited(loadQuiz());
  }

  void shift(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
      selected = month.year == today.year && month.month == today.month
          ? today
          : null;
    });
    unawaited(loadQuiz());
    unawaited(load());
  }

  Future<void> open(DateTime date) async {
    await widget.onOpenDay(date);
    if (!mounted) return;
    // A delete or a claim there changes the tiles, the month and the card.
    unawaited(loadSummary());
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final data = this.data;
    final selected = this.selected;
    return ProductPage(
      onBack: widget.onBack,
      onHome: widget.onHome,
      title: '기록',
      children: [
        if (widget.loadSummary != null) ...[
          _SummaryTiles(
            summary: summary,
            failed: summaryFailed,
            onRetry: loadSummary,
          ),
          const SizedBox(height: Space.s3),
        ],
        _CalendarPanel(
          month: month,
          onShift: shift,
          child: data == null
              ? ProductLoadState(error: error, onRetry: load)
              : _MonthGrid(
                  data: data,
                  today: today,
                  selected: selected,
                  todayGoal: widget.todayGoal,
                  holidayName: widget.holidayName,
                  onSelect: select,
                ),
        ),
        if (data != null) ...[
          const SizedBox(height: Space.s3),
          if (selected == null)
            const ProductPanel(
              key: ValueKey('records_select_hint'),
              child: Text(
                '날짜를 누르면 그날 기록을 볼 수 있어요',
                textAlign: TextAlign.center,
              ),
            )
          else
            _DayCard(
              date: selected,
              day: data.day(selected.day),
              today: selected == today,
              future: selected.isAfter(today),
              goal: selected == today ? widget.todayGoal : null,
              holiday: widget.holidayName(selected),
              quiz: quiz,
              quizFailed: quizFailed,
              quizShown: widget.loadQuiz != null,
              onOpen: () => open(selected),
            ),
        ],
      ],
    );
  }
}

/// `Stat/Tile` × 3 under the title (guide 7.1-1). The values describe this
/// week and this month whichever month is shown.
class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({
    required this.summary,
    required this.failed,
    required this.onRetry,
  });
  final RecordsSummary? summary;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final missing = failed ? '확인하지 못했어요' : '확인 중';
    final average = s?.monthAverage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: Space.s2,
          children: [
            Expanded(
              child: StatTile(
                label: '이번 주',
                value: s == null ? null : '${s.thisWeek}일 기록',
                missing: missing,
                valueKey: const ValueKey('records_week'),
              ),
            ),
            Expanded(
              child: StatTile(
                label: '연속 기록',
                value: s == null
                    ? null
                    : '${s.streak}일${s.streakAtLeast ? ' 이상' : ''}',
                missing: missing,
                valueKey: const ValueKey('records_streak'),
              ),
            ),
            Expanded(
              child: StatTile(
                label: '이번 달 평균',
                value: s == null
                    ? null
                    : average == null
                    ? '기록 없음'
                    : '${formatCount(average)}걸음',
                missing: missing,
                valueKey: const ValueKey('records_average'),
              ),
            ),
          ],
        ),
        if (failed)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const ValueKey('records_summary_retry'),
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ),
      ],
    );
  }
}

/// Pen `Records Calendar`: the month header, [child] and the legend on one
/// raised panel. A [Material] so the date taps show their ink.
class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.month,
    required this.onShift,
    required this.child,
  });
  final DateTime month;
  final ValueChanged<int> onShift;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: MeetingColors.raised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      side: BorderSide(color: MeetingColors.line),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s1,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('records_prev_month'),
                tooltip: '이전 달',
                onPressed: () => onShift(-1),
                // Pen `K6Z5x`: back for the previous month, caret for the next.
                icon: const PixelIcon('back', size: 20),
              ),
              Expanded(
                child: Text(
                  '${month.year}년 ${month.month}월',
                  textAlign: TextAlign.center,
                  style: meetingType(16, 22, FontWeight.w800),
                ),
              ),
              IconButton(
                key: const ValueKey('records_next_month'),
                tooltip: '다음 달',
                onPressed: () => onShift(1),
                icon: const PixelIcon('caret-right', size: 20),
              ),
            ],
          ),
          child,
          const _Legend(),
        ],
      ),
    ),
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.data,
    required this.today,
    required this.selected,
    required this.todayGoal,
    required this.holidayName,
    required this.onSelect,
  });
  final RecordMonth data;
  final DateTime today;
  final DateTime? selected;
  final int? todayGoal;
  final HolidayNameOf holidayName;
  final ValueChanged<DateTime> onSelect;

  Widget _cell(int d) {
    final first = data.month;
    final date = DateTime(first.year, first.month, d);
    final day = data.day(d);
    final isToday = date == today;
    final goal = isToday ? todayGoal : null;
    final kind = recordDayKind(day, future: date.isAfter(today), goal: goal);
    return RecordDayCell(
      date: date,
      kind: kind,
      today: isToday,
      selected: date == selected,
      semanticsLabel: _cellLabel(
        date,
        day,
        kind,
        today: isToday,
        holiday: holidayName(date),
        goal: goal,
      ),
      onTap: () => onSelect(date),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = data.month;
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final cells = <Widget>[
      for (var i = 0; i < first.weekday - 1; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _cell(d),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s1),
          child: Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: meetingType(
                        11.5,
                        16,
                        FontWeight.w700,
                        MeetingColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < cells.length; i += 7)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s1,
              vertical: 2,
            ),
            child: Row(
              children: [
                for (var c = i; c < i + 7; c++)
                  Expanded(
                    child: c < cells.length
                        ? cells[c]
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Everything a date's circle shows, in words (guide 7.1-6), with the full
/// step count.
String _cellLabel(
  DateTime date,
  RecordDay? day,
  RecordDayKind kind, {
  required bool today,
  required String? holiday,
  required int? goal,
}) {
  final claimable =
      day?.rewardStatus == DayRewardStatus.claimable ||
      day?.rewardStatus == DayRewardStatus.adRequired;
  final steps = day?.steps;
  return [
    '${date.month}월 ${date.day}일',
    if (today) '오늘',
    ?holiday,
    _stepsPhrase(day, kind),
    if (kind == RecordDayKind.achieved)
      '목표 달성'
    else if (_counted(kind) && goal != null && steps != null)
      '목표의 ${_percent(steps, goal)}%',
    if (claimable) '받을 포인트 있음',
  ].join(', ');
}

String _stepsPhrase(RecordDay? day, RecordDayKind kind) => switch (kind) {
  RecordDayKind.achieved ||
  RecordDayKind.walked ||
  RecordDayKind.zero => '${formatCount(day?.steps ?? 0)}걸음',
  RecordDayKind.unknown => '걸음 확인 불가',
  RecordDayKind.none => '기록 없음',
  RecordDayKind.deleted => '삭제된 기록',
  RecordDayKind.future => '아직 오지 않은 날',
};

/// `Records/Day` (`fkNx8`): a date's 36 pt circle. The fill shows [kind];
/// today's border and the selection ring are drawn apart, so each can join
/// any kind. Pen has no selected look (guide 9.2), so it is an outer ring
/// in a lighter brown than today's border.
class RecordDayCell extends StatelessWidget {
  const RecordDayCell({
    required this.date,
    required this.kind,
    required this.today,
    required this.selected,
    required this.semanticsLabel,
    required this.onTap,
    super.key,
  });

  final DateTime date;
  final RecordDayKind kind;
  final bool today;
  final bool selected;
  final String semanticsLabel;
  final VoidCallback onTap;

  static const circle = 36.0;

  /// The tap target, which also holds the selection ring.
  static const target = 44.0;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (kind) {
      RecordDayKind.achieved => (ProductColors.record, MeetingColors.raised),
      RecordDayKind.walked => (MeetingColors.soft, MeetingColors.ink),
      RecordDayKind.zero => (null, MeetingColors.ink),
      RecordDayKind.unknown => (ProductColors.dayUnknown, ProductColors.subtle),
      RecordDayKind.deleted => (null, ProductColors.subtle),
      RecordDayKind.none ||
      RecordDayKind.future => (null, ProductColors.dayEmpty),
    };
    // Today's border sits on the circle (Pen). A measured zero has no fill,
    // so a thin line keeps it apart from a day without a record.
    final border = today
        ? Border.all(color: MeetingColors.primaryStrong, width: 2.5)
        : kind == RecordDayKind.zero
        ? Border.all(color: MeetingColors.line, width: 1.5)
        : null;
    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey('records_day_${date.day}'),
        onTap: onTap,
        radius: target / 2,
        child: SizedBox(
          height: target,
          child: Center(
            // Narrow screens shrink the target with its rings intact.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                width: target,
                height: target,
                alignment: Alignment.center,
                decoration: selected
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: MeetingColors.primary,
                          width: 2,
                        ),
                      )
                    : null,
                child: Container(
                  width: circle,
                  height: circle,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    border: border,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${date.day}',
                      style:
                          meetingType(
                            14,
                            18,
                            kind == RecordDayKind.achieved
                                ? FontWeight.w800
                                : FontWeight.w700,
                            ink,
                          ).copyWith(
                            decoration: kind == RecordDayKind.deleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: ink,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 6, bottom: 2),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: Space.s1,
      children: [
        _LegendItem(ProductColors.record, '목표 달성'),
        _LegendItem(MeetingColors.soft, '걸었어요'),
        _LegendItem(ProductColors.dayUnknown, '확인 불가'),
      ],
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 5,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      Text(
        label,
        style: meetingType(11.5, 16, FontWeight.w700, MeetingColors.muted),
      ),
    ],
  );
}

/// Pen `Selected Day Panel`: the selected date at a glance. Steps and the
/// point state come from the month the calendar already holds; the quiz is
/// read per date.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.day,
    required this.today,
    required this.future,
    required this.goal,
    required this.holiday,
    required this.quiz,
    required this.quizFailed,
    required this.quizShown,
    required this.onOpen,
  });
  final DateTime date;
  final RecordDay? day;
  final bool today;
  final bool future;
  final int? goal;
  final String? holiday;
  final DayQuiz? quiz;
  final bool quizFailed;
  final bool quizShown;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    final kind = recordDayKind(day, future: future, goal: this.goal);
    final steps = day?.steps;
    final counted = _counted(kind) && steps != null;
    final goal = counted ? this.goal : null;
    final quizChip = quizShown && !future ? _quizChip(quiz, quizFailed) : null;
    final reward = day == null || kind == RecordDayKind.none
        ? null
        : _rewardChip(day);
    return Material(
      key: const ValueKey('records_day_card'),
      color: MeetingColors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: MeetingColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s2,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [_dayTitle(date), if (today) '오늘', ?holiday].join(' · '),
                    key: const ValueKey('records_card_title'),
                    style: meetingType(14.5, 20, FontWeight.w800),
                  ),
                ),
                TextButton(
                  key: const ValueKey('records_open_day'),
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    foregroundColor: MeetingColors.muted,
                    padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                    textStyle: meetingType(13, 18, FontWeight.w700),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(
                        '자세히',
                        semanticsLabel: '${date.month}월 ${date.day}일 자세히 보기',
                      ),
                      const PixelIcon('caret-right', size: 16),
                    ],
                  ),
                ),
              ],
            ),
            if (counted)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Pen `Selected Day Value`: the share sits at the far end.
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatCount(steps),
                            style: meetingType(
                              26,
                              32,
                              FontWeight.w800,
                            ).copyWith(letterSpacing: -.5),
                          ),
                          TextSpan(
                            text: goal == null
                                ? ' 걸음'
                                : '  / ${formatCount(goal)}걸음',
                            style: meetingType(
                              13.5,
                              18,
                              FontWeight.w700,
                              MeetingColors.muted,
                            ),
                          ),
                        ],
                      ),
                      key: const ValueKey('records_card_steps'),
                    ),
                  ),
                  if (goal != null)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.s2),
                      child: Text(
                        '${_percent(steps, goal)}%',
                        key: const ValueKey('records_card_percent'),
                        style: meetingType(
                          13.5,
                          18,
                          FontWeight.w800,
                          MeetingColors.primary,
                        ),
                      ),
                    ),
                ],
              )
            else
              Text(
                switch (kind) {
                  RecordDayKind.unknown => '걸음을 확인할 수 없어요',
                  RecordDayKind.deleted => '삭제한 기록이에요',
                  RecordDayKind.future => '아직 오지 않은 날이에요',
                  _ => '걸음 기록이 없어요',
                },
                key: const ValueKey('records_card_message'),
                style: meetingType(
                  15,
                  20,
                  FontWeight.w700,
                  MeetingColors.muted,
                ),
              ),
            if (counted && goal != null)
              LinearProgressIndicator(
                key: const ValueKey('records_card_progress'),
                value: _progress(steps, goal),
                minHeight: 8,
                color: kind == RecordDayKind.achieved
                    ? ProductColors.record
                    : MeetingColors.primary,
                backgroundColor: MeetingColors.soft,
                borderRadius: BorderRadius.circular(4),
              ),
            if (quizChip != null || reward != null)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (quizChip case (final label, final tone))
                    TextChip(
                      label,
                      tone: tone,
                      textKey: const ValueKey('records_card_quiz'),
                    ),
                  if (reward != null)
                    TextChip(
                      reward,
                      textKey: const ValueKey('records_card_reward'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The card's quiz chip; null while the read is out.
(String, TextChipTone)? _quizChip(DayQuiz? quiz, bool failed) {
  if (failed) return ('퀴즈 확인 못 함', TextChipTone.neutral);
  if (quiz == null) return null;
  if (quiz.answered == 0) return ('퀴즈 기록 없음', TextChipTone.neutral);
  if (quiz.correct == 0) {
    return (
      quiz.answered > 1 ? '퀴즈 정답 0/${quiz.answered}' : '퀴즈 오답',
      TextChipTone.neutral,
    );
  }
  final share = quiz.answered > 1 ? ' ${quiz.correct}/${quiz.answered}' : '';
  final points = quiz.points > 0 ? ' +${formatCount(quiz.points)}P' : '';
  return ('퀴즈 정답$share$points', TextChipTone.record);
}

/// Every [DayRewardStatus] as a short card chip (guide 7.1-5); a future
/// date has nothing to say yet.
String? _rewardChip(RecordDay day) => switch (day.rewardStatus) {
  DayRewardStatus.pending => '걸음 확정 전',
  DayRewardStatus.claimable => '포인트 받기 전',
  // A settled day without a grant is not "received" (guide 5.1).
  DayRewardStatus.paid =>
    day.grantedPoints > 0
        ? '${formatCount(day.grantedPoints)}P 받음'
        : '받을 포인트 없음',
  DayRewardStatus.expired => '받을 기간 지남',
  DayRewardStatus.adRequired => '광고 보고 받기 전',
  DayRewardStatus.futureDate => null,
  DayRewardStatus.legacyPolicyExcluded => '보상 대상 아님',
  DayRewardStatus.canceled => '포인트 취소됨',
  DayRewardStatus.unconfigured => '포인트 준비 중',
};

/// One KST date with steps and rewards (Pen `tEUiU`). Deletion removes the
/// entire day.
class RecordDayScreen extends StatefulWidget {
  const RecordDayScreen({
    required this.date,
    required this.loadDay,
    required this.deleteDay,
    required this.claimDay,
    this.rewardController,
    required this.onBack,
    required this.onHome,
    this.onDayChanged,
    this.isToday = false,
    this.goal,
    this.loadQuiz,
    this.holidayName = koreanHolidayName,
    this.dogAsset,
    super.key,
  });

  final DateTime date;
  final bool isToday;

  /// The date's confirmed goal. The router passes today's only; past dates
  /// have none on record (guide 7.1-5).
  final int? goal;

  /// The date's answered quizzes for its tile.
  final LoadDayQuiz? loadQuiz;

  /// The user's own companion sprite, passed by the router (guide 3.6).
  final String? dogAsset;
  final LoadRecordDay loadDay;
  final DeleteRecordDay deleteDay;
  final ClaimRecordDay claimDay;
  final ProductController? rewardController;
  final VoidCallback onBack;
  final VoidCallback onHome;

  /// Fired after a confirmed delete or claim so the parent can refresh the
  /// calendar and home.
  final ValueChanged<RecordDay>? onDayChanged;
  final HolidayNameOf holidayName;

  @override
  State<RecordDayScreen> createState() => _RecordDayScreenState();
}

class _RecordDayScreenState extends State<RecordDayScreen> {
  RecordDay? data;
  String? error;
  bool busy = false;
  String? notice;
  bool noticeIsError = false;
  DayQuiz? quiz;
  bool quizFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
    unawaited(loadQuiz());
  }

  Future<void> load() async {
    setState(() {
      data = null;
      error = null;
    });
    try {
      final value = await widget.loadDay(widget.date);
      if (mounted) setState(() => data = value);
    } on Exception {
      if (mounted) setState(() => error = '이 날짜의 기록을 불러오지 못했어요.');
    }
  }

  Future<void> loadQuiz() async {
    final load = widget.loadQuiz;
    if (load == null) return;
    try {
      final value = await load(widget.date);
      if (mounted) setState(() => quiz = value);
    } catch (_) {
      // Any failure, an account change included, leaves the tile empty.
      if (mounted) setState(() => quizFailed = true);
    }
  }

  void _notice(String text, {bool isError = false}) => setState(() {
    notice = text;
    noticeIsError = isError;
  });

  Future<void> confirmDelete() async {
    final d = widget.date;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${d.month}월 ${d.day}일 기록을 모두 삭제할까요?'),
        content: const Text(
          '이 날짜의 걸음 기록이 삭제돼요.\n'
          '아직 받지 않은 포인트는 취소되고, 이미 받은 포인트는 그대로 유지돼요.\n'
          '삭제 후에는 되돌릴 수 없어요.',
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          OutlinedButton(
            key: const ValueKey('records_delete_cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('records_delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: ProductColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('이 날짜 전체 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final value = await widget.deleteDay(d);
      if (!mounted) return;
      setState(() {
        busy = false;
        data = value;
      });
      _notice('이 날짜 기록을 삭제했어요. 받지 않은 포인트는 취소되고 받은 포인트는 유지돼요.');
      widget.onDayChanged?.call(value);
    } on Exception {
      if (!mounted) return;
      setState(() => busy = false);
      _notice('삭제하지 못했어요. 기록은 그대로예요. 다시 시도해 주세요.', isError: true);
    }
  }

  Future<void> claim(RecordDay day) async {
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final amount = await widget.claimDay(day);
      if (!mounted) return;
      setState(() => busy = false);
      _notice('${formatCount(amount)}P를 받았어요.');
      await load();
      final fresh = data;
      if (fresh != null) widget.onDayChanged?.call(fresh);
    } on Exception {
      if (!mounted) return;
      setState(() => busy = false);
      _notice('포인트를 받지 못했어요. 다시 시도해 주세요.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    final holiday = widget.holidayName(d);
    final day = data;
    final kind = day == null
        ? null
        : recordDayKind(
            day,
            future: day.rewardStatus == DayRewardStatus.futureDate,
            goal: widget.goal,
          );
    // Points the tiles already say need no panel (guide 7.2-5); a claim
    // still waiting for its answer keeps it.
    final rewardShown =
        day != null &&
        (day.rewardStatus != DayRewardStatus.paid ||
            (widget.rewardController?.hasPendingClaim ?? false));
    return ProductPage(
      onBack: widget.onBack,
      onHome: widget.onHome,
      title: _dayTitle(d),
      footer: day == null || day.isDeleted
          ? null
          : (gutter) => _DeleteFooter(
              gutter: gutter,
              busy: busy,
              onDelete: confirmDelete,
            ),
      children: [
        if (holiday != null) ...[
          Text(
            holiday,
            key: const ValueKey('records_day_holiday'),
            style: const TextStyle(color: ProductColors.error),
          ),
          const SizedBox(height: Space.s2),
        ],
        if (fixtureLabelsVisible && day?.fixtureLabel != null) ...[
          FixtureBadge(day!.fixtureLabel!),
          const SizedBox(height: Space.s2),
        ],
        if (notice != null) ...[
          ProductPanel(
            key: const ValueKey('records_notice'),
            color: noticeIsError
                ? ProductColors.warningSoft
                : MeetingColors.pressed,
            child: Text(notice!),
          ),
          const SizedBox(height: Space.s3),
        ],
        if (day == null || kind == null)
          ProductLoadState(error: error, onRetry: load)
        else if (day.isDeleted)
          const ProductPanel(
            key: ValueKey('records_deleted'),
            child: Text('삭제된 날짜예요. 걸음 기록이 남아 있지 않아요.'),
          )
        else ...[
          _DayHero(
            day: day,
            kind: kind,
            goal: widget.goal,
            isToday: widget.isToday,
          ),
          if (widget.dogAsset case final dog?) ...[
            const SizedBox(height: Space.s3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s1),
              child: Row(
                spacing: 6,
                children: [
                  SizedBox.square(
                    key: const ValueKey('records_day_dog'),
                    // Pen `Day Dog`.
                    dimension: 76,
                    child: DogSprite(asset: dog),
                  ),
                  Flexible(
                    child: SpeechBubble(
                      wrapByWords(_dogLine(kind, widget.isToday, widget.goal)),
                      lineKey: const ValueKey('records_day_line'),
                      semanticsLabel: _dogLine(
                        kind,
                        widget.isToday,
                        widget.goal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.s3),
          _DayTiles(
            day: day,
            kind: kind,
            goal: widget.goal,
            quiz: quiz,
            quizMissing: widget.loadQuiz == null
                ? '확인할 수 없어요'
                : quizFailed
                ? '확인하지 못했어요'
                : '확인 중',
          ),
          if (rewardShown) ...[
            const SizedBox(height: Space.s3),
            _Section(
              title: '포인트',
              child: widget.isToday
                  ? TextButton(
                      onPressed: widget.onHome,
                      child: const Text('오늘 포인트는 홈에서 받기'),
                    )
                  : widget.rewardController != null
                  ? RewardPanel(
                      controller: widget.rewardController!,
                      day: day,
                      // The notice outlives the panel, which leaves once
                      // nothing is left to receive.
                      onGranted: (amount) =>
                          _notice('${formatCount(amount)}P를 받았어요.'),
                      onChanged: (fresh) {
                        setState(() => data = fresh);
                        widget.onDayChanged?.call(fresh);
                      },
                    )
                  : _RewardBody(
                      day: day,
                      busy: busy,
                      onClaim: () => claim(day),
                    ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Pen `Day Hero`: the ring, then the state and the gap to the goal. Only a
/// confirmed count against a confirmed goal fills the ring or names a gap;
/// an unknown count never reads as 0% (guide 7.2-3).
class _DayHero extends StatelessWidget {
  const _DayHero({
    required this.day,
    required this.kind,
    required this.goal,
    required this.isToday,
  });
  final RecordDay day;
  final RecordDayKind kind;
  final int? goal;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final steps = day.steps;
    final counted = _counted(kind) && steps != null;
    final goal = counted ? this.goal : null;
    final ring = Semantics(
      label: !counted
          ? null
          : goal == null
          ? '${formatCount(steps)}걸음'
          : '${formatCount(steps)}걸음, 목표 ${formatCount(goal)}걸음의 '
                '${_percent(steps, goal)}%',
      child: ExcludeSemantics(
        child: GoalRing(
          key: const ValueKey('records_hero_ring'),
          progress: goal == null ? null : _progress(steps!, goal),
          color: kind == RecordDayKind.achieved
              ? ProductColors.record
              : MeetingColors.primary,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              Text(
                counted ? formatCount(steps) : '–',
                style: meetingType(22, 28, FontWeight.w800),
              ),
              if (counted)
                Text(
                  goal == null ? '걸음' : '/ ${formatCount(goal)}걸음',
                  style: meetingType(
                    12,
                    16,
                    FontWeight.w400,
                    MeetingColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final (title, body) = _heroCopy(kind, steps, goal, isToday);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(
          title,
          key: const ValueKey('records_hero_title'),
          style: meetingType(
            21,
            26,
            FontWeight.w800,
            kind == RecordDayKind.achieved
                ? ProductColors.record
                : counted
                ? MeetingColors.ink
                : MeetingColors.muted,
          ),
        ),
        Text(
          wrapByWords(body),
          key: const ValueKey('records_hero_body'),
          semanticsLabel: body,
          style: meetingType(14, 20, FontWeight.w600, MeetingColors.muted),
        ),
      ],
    );
    return Container(
      key: const ValueKey('records_day_hero'),
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: MeetingColors.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MeetingColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, bounds) =>
            // Large text or a narrow screen stacks the ring over its copy,
            // as the home card does.
            bounds.maxWidth - 112 - Space.s4 < 150 ||
                MediaQuery.textScalerOf(context).scale(16) > 16 * 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.s3,
                children: [ring, copy],
              )
            : Row(
                spacing: Space.s4,
                children: [
                  ring,
                  Expanded(child: copy),
                ],
              ),
      ),
    );
  }
}

/// The hero's title and line for each kind. Unknown keeps the existing
/// explanation that it is not 0 steps.
(String, String) _heroCopy(
  RecordDayKind kind,
  int? steps,
  int? goal,
  bool isToday,
) => switch (kind) {
  RecordDayKind.achieved when steps != null && goal != null => (
    '목표 달성!',
    steps > goal ? '목표보다 ${formatCount(steps - goal)}걸음 더 걸었어요' : '목표를 딱 채웠어요',
  ),
  RecordDayKind.walked when steps != null && goal != null => (
    isToday
        ? '${formatCount(goal - steps)}걸음 남았어요'
        : '목표까지 ${formatCount(goal - steps)}걸음',
    '${isToday ? '오늘 ' : ''}목표의 ${_percent(steps, goal)}%를 걸었어요',
  ),
  RecordDayKind.zero when goal != null => (
    '0걸음이에요',
    '${isToday ? '오늘 ' : ''}목표는 ${formatCount(goal)}걸음이에요',
  ),
  RecordDayKind.zero => ('0걸음이에요', '이날은 걸음이 없었어요'),
  RecordDayKind.achieved || RecordDayKind.walked => ('걸었어요', '이날 목표는 기록에 없어요'),
  RecordDayKind.unknown => ('걸음 확인 불가', '이 날짜의 걸음을 확인할 수 없어요. 0걸음과는 달라요.'),
  RecordDayKind.none => ('기록 없음', '이날은 걸음 기록이 없어요'),
  RecordDayKind.future => ('아직 오지 않은 날', '그날 걸으면 여기에 기록돼요'),
  RecordDayKind.deleted => ('삭제된 날짜', '걸음 기록이 남아 있지 않아요'),
};

/// The companion's short reaction beside it (Pen `Day Dog Speech`).
String _dogLine(RecordDayKind kind, bool isToday, int? goal) => switch (kind) {
  RecordDayKind.achieved => isToday ? '오늘 정말 잘 걸었어!' : '이날 정말 잘 걸었어!',
  RecordDayKind.walked when isToday =>
    goal == null ? '오늘도 같이 걷자!' : '조금만 더 같이 걷자!',
  RecordDayKind.walked => '이날도 같이 걸었지!',
  RecordDayKind.zero => isToday ? '오늘 같이 걸으러 가자!' : '이날은 같이 쉬었어',
  RecordDayKind.unknown => '이날 걸음은 못 가져왔어',
  RecordDayKind.none => '이날은 기록이 없어',
  RecordDayKind.future => '그날 같이 걷자!',
  RecordDayKind.deleted => '',
};

/// Pen `Day Stats Row 1/2`: steps, goal, received points and quiz. The
/// points are the server's grant for the day, never worked out from steps.
class _DayTiles extends StatelessWidget {
  const _DayTiles({
    required this.day,
    required this.kind,
    required this.goal,
    required this.quiz,
    required this.quizMissing,
  });
  final RecordDay day;
  final RecordDayKind kind;
  final int? goal;
  final DayQuiz? quiz;
  final String quizMissing;

  @override
  Widget build(BuildContext context) {
    final future = kind == RecordDayKind.future;
    final steps = day.steps;
    final goal = this.goal;
    return Column(
      spacing: Space.s2,
      children: [
        Row(
          spacing: Space.s2,
          children: [
            Expanded(
              child: StatTile(
                label: '걸음',
                value: _counted(kind) && steps != null
                    ? '${formatCount(steps)}걸음'
                    : switch (kind) {
                        RecordDayKind.unknown => '확인 불가',
                        RecordDayKind.future => null,
                        _ => '기록 없음',
                      },
                missing: '아직 오지 않은 날',
                valueKey: const ValueKey('records_tile_steps'),
              ),
            ),
            Expanded(
              child: StatTile(
                label: '목표',
                value: future
                    ? null
                    : goal == null
                    ? '기록 없음'
                    : '${formatCount(goal)}걸음',
                missing: '아직 오지 않은 날',
                valueKey: const ValueKey('records_tile_goal'),
              ),
            ),
          ],
        ),
        Row(
          spacing: Space.s2,
          children: [
            Expanded(
              child: StatTile(
                label: '받은 포인트',
                value: '${formatCount(day.grantedPoints)}P',
                valueKey: const ValueKey('records_tile_points'),
              ),
            ),
            Expanded(
              child: StatTile(
                label: '퀴즈',
                value: future ? null : _quizTile(quiz),
                missing: future ? '아직 오지 않은 날' : quizMissing,
                valueKey: const ValueKey('records_tile_quiz'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The quiz tile's value; null while unknown.
String? _quizTile(DayQuiz? quiz) {
  if (quiz == null) return null;
  if (quiz.answered == 0) return '기록 없음';
  final points = quiz.points > 0 ? ' · +${formatCount(quiz.points)}P' : '';
  if (quiz.answered == 1) return quiz.correct == 1 ? '정답$points' : '오답';
  return '정답 ${quiz.correct}/${quiz.answered}$points';
}

/// Pen `Day Delete Link`: one red text button at the bottom of the page. It
/// still goes through the delete confirmation.
class _DeleteFooter extends StatelessWidget {
  const _DeleteFooter({
    required this.gutter,
    required this.busy,
    required this.onDelete,
  });
  final double gutter;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      gutter,
      Space.s2,
      gutter,
      Space.s4 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Center(
      child: TextButton(
        key: const ValueKey('records_delete_day'),
        style: TextButton.styleFrom(
          foregroundColor: ProductColors.error,
          textStyle: meetingType(14, 20, FontWeight.w700),
        ),
        onPressed: busy ? null : onDelete,
        child: Text(busy ? '처리 중…' : '이 날 기록 삭제'),
      ),
    ),
  );
}

class _RewardBody extends StatelessWidget {
  const _RewardBody({
    required this.day,
    required this.busy,
    required this.onClaim,
  });
  final RecordDay day;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final granted = day.grantedPoints > 0
        ? '받은 포인트 ${formatCount(day.grantedPoints)}P'
        : null;
    final status = switch (day.rewardStatus) {
      DayRewardStatus.pending => '걸음이 확정되면 받을 수 있어요.',
      DayRewardStatus.claimable =>
        day.claimablePoints == null
            ? '받을 수 있는 포인트가 있어요.'
            : '${formatCount(day.claimablePoints!)}P를 받을 수 있어요.',
      DayRewardStatus.paid => '이 날짜의 포인트를 모두 받았어요.',
      DayRewardStatus.expired => '받을 수 있는 기간이 지났어요.',
      DayRewardStatus.adRequired => '광고 확인 후 남은 포인트를 받을 수 있어요.',
      DayRewardStatus.futureDate => '미래 날짜의 기록이에요.',
      DayRewardStatus.legacyPolicyExcluded => '이전 테스트 정책 기록으로 운영 보상 대상이 아니에요.',
      DayRewardStatus.canceled => '삭제로 받지 않은 포인트가 취소됐어요.',
      DayRewardStatus.unconfigured => '포인트 정책이 아직 준비되지 않았어요.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(status, key: const ValueKey('records_reward_status')),
        if (granted != null) ...[
          const SizedBox(height: Space.s1),
          Text(granted),
        ],
        if (day.rewardStatus == DayRewardStatus.claimable) ...[
          const SizedBox(height: Space.s3),
          FilledButton(
            key: const ValueKey('records_claim'),
            onPressed: busy ? null : onClaim,
            child: Text(busy ? '처리 중…' : '포인트 받기'),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.s2),
        child,
      ],
    ),
  );
}
