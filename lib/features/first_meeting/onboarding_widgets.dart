import 'package:flutter/material.dart';

import '../records/product_page.dart'
    show PixelIcon, ProductColors, Space, formatCount;
import '../wardrobe/dog_sprite.dart';
import 'meeting_theme.dart';

/// Pen values of ONB-09 (`Ao2Ri`) that the spacing scale does not hold.
abstract final class OnboardingMetrics {
  /// Gap between the step bar's parts, the preset cards and the footer.
  static const gap = 10.0;
  static const stepNav = 44.0;
  static const stepBack = 24.0;
  static const segment = 6.0;
  static const segmentGap = 6.0;
  static const stepperHeight = 112.0;
  static const stepperRadius = 22.0;
  static const stepperInset = 18.0;
  static const stepButton = 48.0;
  static const cardInset = 14.0;
  static const dog = 120.0;
  static const dogGap = 6.0;
}

/// `Onboarding/Step Nav` (`OKEkN`): back, one segment per step and
/// `step/total`. A null [onBack] keeps the 44 pt slot empty, as the meeting
/// header does while the Duo rail carries back or a save is running.
class OnboardingStepNav extends StatelessWidget {
  const OnboardingStepNav({
    required this.step,
    required this.total,
    required this.onBack,
    super.key,
  });

  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: OnboardingMetrics.stepNav),
    child: Row(
      spacing: OnboardingMetrics.gap,
      children: [
        SizedBox.square(
          dimension: OnboardingMetrics.stepNav,
          child: onBack == null
              ? null
              : IconButton(
                  key: const ValueKey('meeting_back'),
                  tooltip: '이전 단계',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  icon: const PixelIcon(
                    'back',
                    size: OnboardingMetrics.stepBack,
                  ),
                ),
        ),
        Expanded(
          child: Semantics(
            label: '$total단계 중 $step단계',
            child: ExcludeSemantics(
              child: Row(
                spacing: OnboardingMetrics.gap,
                children: [
                  Expanded(
                    child: Row(
                      spacing: OnboardingMetrics.segmentGap,
                      children: [
                        for (var i = 1; i <= total; i++)
                          Expanded(
                            child: Container(
                              height: OnboardingMetrics.segment,
                              decoration: BoxDecoration(
                                color: i <= step
                                    ? MeetingColors.primary
                                    : MeetingColors.soft,
                                borderRadius: BorderRadius.circular(
                                  OnboardingMetrics.segment / 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '$step/$total',
                    style: meetingType(
                      13,
                      18,
                      FontWeight.w800,
                      MeetingColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The goal stepper of ONB-09: −, the goal over 걸음, and +. A null [value]
/// is a draft that is no number at all; it shows a dash.
class GoalStepper extends StatelessWidget {
  const GoalStepper({
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    super.key,
  });

  final int? value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(
      minHeight: OnboardingMetrics.stepperHeight,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: OnboardingMetrics.stepperInset,
      vertical: Space.s3,
    ),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: MeetingColors.raised,
      borderRadius: BorderRadius.circular(OnboardingMetrics.stepperRadius),
      border: Border.all(color: MeetingColors.line),
    ),
    child: Row(
      spacing: Space.s2,
      children: [
        _StepButton(
          buttonKey: const ValueKey('meeting_goal_minus'),
          glyph: '−',
          tooltip: '목표 줄이기',
          onPressed: onDecrease,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A long number shrinks instead of pushing the buttons out.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value == null ? '—' : formatCount(value!),
                    key: const ValueKey('meeting_goal_value'),
                    style: meetingType(
                      44,
                      52,
                      FontWeight.w800,
                    ).copyWith(letterSpacing: -1),
                  ),
                ),
                Text(
                  '걸음',
                  style: meetingType(
                    14,
                    20,
                    FontWeight.w700,
                    MeetingColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        _StepButton(
          buttonKey: const ValueKey('meeting_goal_plus'),
          glyph: '+',
          tooltip: '목표 늘리기',
          onPressed: onIncrease,
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.buttonKey,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
  });

  final Key buttonKey;
  final String glyph;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: MeetingColors.soft,
      disabledBackgroundColor: MeetingColors.pressed,
      fixedSize: const Size.square(OnboardingMetrics.stepButton),
      padding: EdgeInsets.zero,
    ),
    icon: Text(
      glyph,
      style: meetingType(
        26,
        28,
        FontWeight.w700,
        onPressed == null ? MeetingColors.line : MeetingColors.ink,
      ),
    ),
  );
}

/// The four presets of ONB-09 (Pen `Goal Presets`) in two columns, or in
/// one once the widest value no longer fits half the width.
class GoalPresetGrid extends StatelessWidget {
  const GoalPresetGrid({required this.children, super.key});

  final List<GoalPresetCard> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      var widest = 0.0;
      for (final card in children) {
        final value = TextPainter(
          text: TextSpan(
            text: formatCount(card.value),
            style: GoalPresetCard.valueStyle,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (value.width > widest) widest = value.width;
        value.dispose();
      }
      const gap = OnboardingMetrics.gap;
      final half = (bounds.maxWidth - gap) / 2;
      if (half < widest + OnboardingMetrics.cardInset * 2) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: children,
        );
      }
      return Column(
        spacing: gap,
        children: [
          for (var i = 0; i < children.length; i += 2)
            // Both cards of a row share the taller one's height.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: gap,
                children: [
                  Expanded(child: children[i]),
                  Expanded(
                    child: i + 1 < children.length
                        ? children[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// `Goal/Preset Card` (`rtAXZ`): a value and its title, the 추천 badge and
/// the selected stroke. Selection and the recommendation are separate: the
/// badge stays on its value whichever card is chosen.
class GoalPresetCard extends StatelessWidget {
  const GoalPresetCard({
    required this.value,
    required this.label,
    required this.recommended,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int value;
  final String label;
  final bool recommended;
  final bool selected;
  final VoidCallback? onTap;

  static final valueStyle = meetingType(19, 24, FontWeight.w800);

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? MeetingColors.well : MeetingColors.raised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? const BorderSide(color: MeetingColors.primaryStrong, width: 2)
            : const BorderSide(color: MeetingColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OnboardingMetrics.cardInset,
            vertical: Space.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s1,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.s1,
                runSpacing: Space.s1,
                children: [
                  Text(formatCount(value), style: valueStyle),
                  if (recommended) const _RecommendedBadge(),
                ],
              ),
              Text(
                label,
                style: meetingType(
                  12.5,
                  18,
                  FontWeight.w700,
                  MeetingColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Pen `Preset Badge`: 추천 on the record olive.
class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('meeting_goal_recommended'),
    decoration: BoxDecoration(
      color: ProductColors.record,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      child: Text(
        '추천',
        style: meetingType(11, 14, FontWeight.w800, MeetingColors.raised),
      ),
    ),
  );
}

/// The chosen companion beside its line (Pen `Shared/Home Speech`,
/// `40f12cf158cd`), for the onboarding steps that react to an entry.
class DogSpeechPreview extends StatelessWidget {
  const DogSpeechPreview({
    required this.sprite,
    required this.line,
    this.lineKey,
    super.key,
  });

  final String sprite;
  final String line;
  final Key? lineKey;

  @override
  Widget build(BuildContext context) => Row(
    spacing: OnboardingMetrics.dogGap,
    children: [
      SizedBox.square(
        dimension: OnboardingMetrics.dog,
        child: DogSprite(asset: sprite),
      ),
      Flexible(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MeetingColors.raised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OnboardingMetrics.cardInset,
              vertical: OnboardingMetrics.gap,
            ),
            child: Text(
              line,
              key: lineKey,
              style: meetingType(
                14,
                20,
                FontWeight.w400,
              ).copyWith(fontFamily: 'Galmuri11'),
            ),
          ),
        ),
      ),
    ],
  );
}
