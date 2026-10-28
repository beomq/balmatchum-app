import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../daily_activity/daily_steps_controller.dart';
import '../daily_activity/product_controller.dart';
import '../daily_activity/record_mapping.dart';
import '../records/product_page.dart';
import '../records/records_models.dart';
import '../records/status_widgets.dart';
import '../watch_sync/watch_bridge.dart';
import 'meeting_theme.dart';

/// Where today's device steps stand. The ring is a device observation only;
/// rewards come from the server record (guide 5.1).
enum StepsState {
  /// Reading, or not read yet.
  checking,

  /// A count for today's KST date, zero included.
  counted,

  /// A count for another date, such as a read from before midnight.
  notToday,

  /// The device has no step data for today.
  empty,
  unsupported,
  permissionDenied,
  updateRequired,
  failed,
}

/// Today's steps against the goal, as the home card draws them.
class HomeGoal {
  const HomeGoal._(this.state, this.goal, this.count);

  factory HomeGoal.of(DailyStepsController? steps, int goal, String today) {
    final result = steps?.result;
    if (steps == null || steps.isLoading || result == null) {
      return HomeGoal._(StepsState.checking, goal, null);
    }
    final state = switch (result.status) {
      DailyStepsStatus.available =>
        steps.count == null
            ? StepsState.failed
            : steps.date == today
            ? StepsState.counted
            : StepsState.notToday,
      DailyStepsStatus.empty => StepsState.empty,
      DailyStepsStatus.capabilityUnavailable => StepsState.unsupported,
      DailyStepsStatus.permissionDenied => StepsState.permissionDenied,
      DailyStepsStatus.providerUpdateRequired => StepsState.updateRequired,
      DailyStepsStatus.unavailable ||
      DailyStepsStatus.error => StepsState.failed,
    };
    return HomeGoal._(
      state,
      goal,
      state == StepsState.counted ? steps.count : null,
    );
  }

  final StepsState state;
  final int goal;

  /// Today's count; null whenever it is not known. Never 0 in its place.
  final int? count;

  bool get achieved => count != null && count! >= goal;

  /// `steps / goal` clamped to 0..1; the count itself is not clamped.
  double? get progress =>
      count == null ? null : (goal <= 0 ? 1.0 : math.min(count! / goal, 1.0));
  int get remaining => math.max(goal - (count ?? 0), 0);
  int get excess => math.max((count ?? 0) - goal, 0);

  /// Whole percent, rounded; an unfinished goal stops at 99 so it never
  /// reads 100%.
  int get percent {
    if (count == null || goal <= 0) return 0;
    final value = (count! * 100 / goal).round();
    return achieved ? value : math.min(value, 99);
  }

  /// Failed reads a retry can fix. Unsupported devices and empty days are
  /// answers, not failures.
  bool get retryable => switch (state) {
    StepsState.notToday ||
    StepsState.permissionDenied ||
    StepsState.updateRequired ||
    StepsState.failed => true,
    _ => false,
  };
}

/// The home card's point action. The goal and the reward are separate:
/// a reached goal is not a claim, and a claim does not reach the goal.
enum HomeReward {
  /// Opens today's reward sheet, which explains what can be received.
  open,

  /// Today's record is loading or the server still confirms the steps.
  checking,

  /// The server settled today with points granted.
  claimed,
}

HomeReward homeReward(ProductController? product, String today) {
  if (product == null) return HomeReward.open;
  final value = product.today;
  if (value == null || value.date != today) {
    return product.busy ? HomeReward.checking : HomeReward.open;
  }
  final RecordDay day;
  try {
    day = recordDay(value);
  } on FormatException {
    return HomeReward.open;
  }
  if (day.rewardStatus == DayRewardStatus.pending) return HomeReward.checking;
  // A settled day without a grant is not "received" (guide 5.1).
  if (day.rewardStatus == DayRewardStatus.paid && day.grantedPoints > 0) {
    return HomeReward.claimed;
  }
  return HomeReward.open;
}

/// HOME-A goal card: the ring, its description and one full-width action.
class HomeGoalCard extends StatelessWidget {
  const HomeGoalCard({
    required this.goal,
    required this.reward,
    required this.onReward,
    required this.onRetry,
    this.notices = const [],
    super.key,
  });

  final HomeGoal goal;
  final HomeReward reward;
  final VoidCallback onReward;

  /// The home's refresh after a failed read.
  final VoidCallback onRetry;

  /// Server connection notices shown above the action.
  final List<Widget> notices;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final count = goal.count;
    final ring = Semantics(
      key: const ValueKey('home_goal_ring'),
      label: count == null
          ? goal.state == StepsState.checking
                ? '오늘 걸음 확인 중'
                : '오늘 걸음 확인 불가, 목표 ${formatCount(goal.goal)}걸음'
          : '오늘 ${formatCount(count)}걸음, '
                '목표 ${formatCount(goal.goal)}걸음의 ${goal.percent}%',
      child: ExcludeSemantics(
        child: GoalRing(
          progress: goal.progress,
          color: goal.achieved ? ProductColors.record : MeetingColors.primary,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count == null ? '–' : formatCount(count),
                key: const ValueKey('daily_steps_count'),
                style: text.headlineSmall,
              ),
              Text('/ ${formatCount(goal.goal)}걸음', style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
    final (title, body) = _describe(goal);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          key: const ValueKey('home_goal_title'),
          style: text.titleLarge,
        ),
        if (body != null) ...[
          const SizedBox(height: Space.s1),
          Text(body, key: const ValueKey('home_goal_body')),
        ],
      ],
    );
    final point = switch (reward) {
      HomeReward.claimed => FilledButton(
        key: const ValueKey('home_reward'),
        onPressed: null,
        style: FilledButton.styleFrom(
          disabledBackgroundColor: ProductColors.recordSoft,
          disabledForegroundColor: ProductColors.record,
        ),
        child: const Text('오늘 포인트 받음'),
      ),
      HomeReward.checking => const FilledButton(
        key: ValueKey('home_reward'),
        onPressed: null,
        child: Text('포인트 확인 중'),
      ),
      // A failed read leads with its retry; the point action steps down.
      // Pen `Points Button Content`: the 20 pt points icon, 8 pt, the label.
      HomeReward.open when goal.retryable => OutlinedButton.icon(
        key: const ValueKey('home_reward'),
        onPressed: onReward,
        icon: const PixelIcon('points', size: 20),
        label: const Text('오늘 포인트 받기'),
      ),
      HomeReward.open => FilledButton.icon(
        key: const ValueKey('home_reward'),
        onPressed: onReward,
        icon: const PixelIcon('points', size: 20),
        label: const Text('오늘 포인트 받기'),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: MeetingColors.raised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, bounds) =>
                // Large text stacks the ring over its description.
                bounds.maxWidth - 112 - Space.s4 < 160 ||
                    MediaQuery.textScalerOf(context).scale(16) > 16 * 1.3
                ? Column(
                    children: [
                      ring,
                      const SizedBox(height: Space.s3),
                      SizedBox(width: double.infinity, child: summary),
                    ],
                  )
                : Row(
                    children: [
                      ring,
                      const SizedBox(width: Space.s4),
                      Expanded(child: summary),
                    ],
                  ),
          ),
          ...notices,
          const SizedBox(height: Space.s4),
          if (goal.retryable) ...[
            FilledButton(
              key: const ValueKey('daily_steps_retry'),
              onPressed: onRetry,
              child: const Text('다시 불러오기'),
            ),
            const SizedBox(height: Space.s2),
          ],
          point,
        ],
      ),
    );
  }
}

/// The title and the optional line beside the ring. Numbers stay here and
/// never in the speech bubble (guide 5.1).
(String, String?) _describe(HomeGoal goal) {
  final health = defaultTargetPlatform == TargetPlatform.iOS
      ? '건강 앱'
      : 'Health Connect';
  return switch (goal.state) {
    StepsState.counted when goal.achieved => (
      '목표 달성!',
      goal.excess > 0 ? '목표보다 ${formatCount(goal.excess)}걸음 더 걸었어요' : null,
    ),
    StepsState.counted => (
      '${formatCount(goal.remaining)}걸음 남음',
      '오늘 목표의 ${goal.percent}%',
    ),
    StepsState.checking => ('걸음 확인 중', null),
    // Pen breaks these lines at a word; Hangul would wrap mid-word.
    StepsState.notToday => ('걸음을 못 불러왔어요', '화면을 당겨\n새로고침해 주세요'),
    StepsState.empty => ('아직 걸음이 없어요', '걸으면 여기에 쌓여요'),
    StepsState.unsupported => ('걸음을 확인할 수 없어요', '이 기기에서는 걸음 조회를\n지원하지 않아요'),
    StepsState.permissionDenied => (
      '걸음을 못 불러왔어요',
      '$health에서 걸음 읽기\n권한을 허용해 주세요',
    ),
    StepsState.updateRequired => (
      '걸음을 못 불러왔어요',
      'Health Connect를 설치하거나\n업데이트해 주세요',
    ),
    StepsState.failed => ('걸음을 못 불러왔어요', '$health 권한을 확인하거나\n화면을 당겨 새로고침해 주세요'),
  };
}
