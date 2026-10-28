import 'dart:async';

import 'package:flutter/material.dart';
import 'package:world_holidays/world_holidays.dart';

import '../first_meeting/meeting_theme.dart';
import '../daily_activity/product_controller.dart';
import '../daily_activity/reward_panel.dart';
import '../wardrobe/dog_sprite.dart';
import 'product_page.dart';
import 'records_models.dart';

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

/// Records month calendar. [initialMonth] is a KST month; the parent passes
/// the current KST date so tests stay deterministic.
class RecordsCalendarScreen extends StatefulWidget {
  const RecordsCalendarScreen({
    required this.initialMonth,
    required this.loadMonth,
    required this.onOpenDay,
    required this.onBack,
    required this.onHome,
    this.holidayName = koreanHolidayName,
    super.key,
  });

  final DateTime initialMonth;
  final LoadRecordMonth loadMonth;
  final FutureOr<void> Function(DateTime) onOpenDay;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final HolidayNameOf holidayName;

  @override
  State<RecordsCalendarScreen> createState() => _RecordsCalendarScreenState();
}

class _RecordsCalendarScreenState extends State<RecordsCalendarScreen> {
  late DateTime month = DateTime(
    widget.initialMonth.year,
    widget.initialMonth.month,
  );
  RecordMonth? data;
  String? error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
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

  void shift(int delta) {
    month = DateTime(month.year, month.month + delta);
    unawaited(load());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ProductPage(
      onBack: widget.onBack,
      onHome: widget.onHome,
      children: [
        Text('기록', style: text.headlineSmall),
        const SizedBox(height: Space.s1),
        const Text('한국 기준 날짜 · 날짜를 눌러 상세를 확인해요'),
        const SizedBox(height: Space.s4),
        Row(
          children: [
            IconButton(
              key: const ValueKey('records_prev_month'),
              tooltip: '이전 달',
              onPressed: () => shift(-1),
              icon: const Icon(Icons.chevron_left, color: MeetingColors.ink),
            ),
            Expanded(
              child: Text(
                '${month.year}년 ${month.month}월',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
            ),
            IconButton(
              key: const ValueKey('records_next_month'),
              tooltip: '다음 달',
              onPressed: () => shift(1),
              icon: const Icon(Icons.chevron_right, color: MeetingColors.ink),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        if (data == null)
          ProductLoadState(error: error, onRetry: load)
        else
          _MonthGrid(
            data: data!,
            holidayName: widget.holidayName,
            onOpenDay: (date) async {
              await widget.onOpenDay(date);
              if (mounted) await load();
            },
          ),
        const SizedBox(height: Space.s4),
        const _Legend(),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.data,
    required this.holidayName,
    required this.onOpenDay,
  });
  final RecordMonth data;
  final HolidayNameOf holidayName;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final first = data.month;
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final leading = first.weekday - 1;
    final cells = <Widget>[
      for (final w in _weekdays)
        Center(
          child: Text(
            w,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: w == '일' ? ProductColors.error : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _DayCell(
          date: DateTime(first.year, first.month, d),
          summary: data.day(d),
          holiday: holidayName(DateTime(first.year, first.month, d)),
          onTap: onOpenDay,
        ),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final row = cells.sublist(i, (i + 7).clamp(0, cells.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: c < row.length ? row[c] : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.summary,
    required this.holiday,
    required this.onTap,
  });
  final DateTime date;
  final RecordDay? summary;
  final String? holiday;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final red = holiday != null || date.weekday == DateTime.sunday;
    final small = Theme.of(context).textTheme.bodySmall;
    final label = s == null
        ? ''
        : s.isDeleted
        ? '삭제'
        : s.availability == StepAvailability.unavailable || s.steps == null
        ? '?'
        : s.steps! >= 1000
        // Compact so the label never ellipsizes; full value is in semantics.
        ? '${(s.steps! / 1000).toStringAsFixed(s.steps! >= 10000 ? 0 : 1)}k'
        : '${s.steps}';
    final claimable =
        s?.rewardStatus == DayRewardStatus.claimable ||
        s?.rewardStatus == DayRewardStatus.adRequired;
    final semantics = [
      '${date.month}월 ${date.day}일',
      if (holiday != null) holiday,
      if (s != null) _stepsPhrase(s),
      if (claimable) '받을 포인트 있음',
    ].join(', ');
    return Semantics(
      label: semantics,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: s == null ? Colors.transparent : ProductColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: s == null ? Colors.transparent : MeetingColors.line,
          ),
        ),
        child: InkWell(
          key: ValueKey('records_day_${date.day}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(date),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: red ? ProductColors.error : null),
                  ),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small?.copyWith(
                        color: s!.availability == StepAvailability.confirmed
                            ? ProductColors.record
                            : MeetingColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (claimable)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (claimable)
                          const _Dot(color: ProductColors.attention),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _stepsPhrase(RecordDay d) => d.isDeleted
    ? '삭제된 기록'
    : d.availability == StepAvailability.confirmed && d.steps != null
    ? '${formatCount(d.steps!)}걸음'
    : '걸음 확인 불가';

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.all(1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: Space.s4,
    runSpacing: Space.s2,
    children: [
      _LegendItem(_Dot(color: ProductColors.attention), '받을 포인트'),
      _LegendItem(Text('?'), '걸음 확인 불가'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.mark, this.label);
  final Widget mark;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      mark,
      const SizedBox(width: Space.s1),
      Text(label),
    ],
  );
}

/// One KST date with steps and rewards. Deletion removes the entire day.
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
    this.holidayName = koreanHolidayName,
    this.dogAsset,
    super.key,
  });

  final DateTime date;
  final bool isToday;

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

  @override
  void initState() {
    super.initState();
    unawaited(load());
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
      _notice('${formatCount(amount)}포인트를 받았어요.');
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
    final text = Theme.of(context).textTheme;
    final d = widget.date;
    final holiday = widget.holidayName(d);
    final day = data;
    return ProductPage(
      onBack: widget.onBack,
      onHome: widget.onHome,
      children: [
        Text(
          '${d.year}년 ${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})',
          style: text.headlineSmall,
        ),
        if (holiday != null) ...[
          const SizedBox(height: Space.s1),
          Text(holiday, style: const TextStyle(color: ProductColors.error)),
        ],
        if (fixtureLabelsVisible && day?.fixtureLabel != null) ...[
          const SizedBox(height: Space.s2),
          FixtureBadge(day!.fixtureLabel!),
        ],
        const SizedBox(height: Space.s4),
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
        if (day == null)
          ProductLoadState(error: error, onRetry: load)
        else if (day.isDeleted)
          const ProductPanel(
            key: ValueKey('records_deleted'),
            child: Text('삭제된 날짜예요. 걸음 기록이 남아 있지 않아요.'),
          )
        else ...[
          _Section(
            title: '걸음',
            child:
                day.availability == StepAvailability.confirmed &&
                    day.steps != null
                ? Text(
                    '${formatCount(day.steps!)}걸음',
                    style: text.headlineSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : const Text('이 날짜의 걸음을 확인할 수 없어요. 0걸음과는 달라요.'),
          ),
          if (widget.dogAsset case final dog?) ...[
            const SizedBox(height: Space.s3),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                key: const ValueKey('records_day_dog'),
                // Pen record day: the companion sits under the steps card.
                dimension: DogSpriteSize.companion,
                child: DogSprite(asset: dog),
              ),
            ),
          ],
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
                    onChanged: (fresh) {
                      setState(() => data = fresh);
                      widget.onDayChanged?.call(fresh);
                    },
                  )
                : _RewardBody(day: day, busy: busy, onClaim: () => claim(day)),
          ),
          const SizedBox(height: Space.s6),
          OutlinedButton(
            key: const ValueKey('records_delete_day'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ProductColors.error,
              side: const BorderSide(color: ProductColors.error),
            ),
            onPressed: busy ? null : confirmDelete,
            child: Text(busy ? '처리 중…' : '이 날짜 기록 전체 삭제'),
          ),
        ],
      ],
    );
  }
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
            : '${formatCount(day.claimablePoints!)}포인트를 받을 수 있어요.',
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
