import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import 'product_page.dart';

/// `Home/Status Chip` (`Dkbzs`): a 32 pt pill with one short status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {this.textKey, super.key});
  final String label;

  /// Finds the label itself, whose text tests read.
  final Key? textKey;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 6),
    decoration: const BoxDecoration(
      color: MeetingColors.soft,
      borderRadius: BorderRadius.all(Radius.circular(999)),
    ),
    child: Text(
      label,
      key: textKey,
      style: meetingType(15, 20, FontWeight.w700),
    ),
  );
}

/// Fills of [TextChip]: a plain status, a good result, a wrong one.
enum TextChipTone { neutral, record, error }

/// `Chip/Text` (`ki4q7`): a 30 pt pill with a short status or result.
/// Its 13 pt labels keep 4.5:1 contrast, so the olive tone writes in the
/// darker olive the correct quiz option uses (Pen's record on record-soft
/// is 4.4:1).
class TextChip extends StatelessWidget {
  const TextChip(
    this.label, {
    this.tone = TextChipTone.neutral,
    this.textKey,
    super.key,
  });
  final String label;
  final TextChipTone tone;

  /// Finds the label itself, whose text tests read.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (tone) {
      TextChipTone.neutral => (MeetingColors.soft, MeetingColors.ink),
      TextChipTone.record => (
        ProductColors.recordSoft,
        ProductColors.recordInk,
      ),
      TextChipTone.error => (ProductColors.errorSoft, ProductColors.error),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        label,
        key: textKey,
        style: meetingType(13, 18, FontWeight.w700, ink),
      ),
    );
  }
}

/// `Home/Goal Ring` (`T63MNT`): the share of the day's goal. A null
/// [progress] draws the track alone, for steps that are not known.
class GoalRing extends StatelessWidget {
  const GoalRing({
    required this.progress,
    required this.color,
    required this.child,
    this.size = 112,
    super.key,
  });

  /// 0 to 1; values outside are clamped.
  final double? progress;
  final Color color;
  final Widget child;
  final double size;

  static const stroke = 12.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RingPainter(progress?.clamp(0.0, 1.0).toDouble(), color),
      child: Padding(
        padding: const EdgeInsets.all(stroke + Space.s1),
        child: Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double? progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(GoalRing.stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = GoalRing.stroke;
    canvas.drawArc(
      bounds,
      0,
      math.pi * 2,
      false,
      paint..color = MeetingColors.soft,
    );
    final value = progress;
    if (value != null && value > 0) {
      canvas.drawArc(
        bounds,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// `Home/Status Tile` (`F9fHc6`): a destination with its current state.
class StatusTile extends StatelessWidget {
  const StatusTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.status,
    this.statusKey,
    super.key,
  });

  /// A pixel icon under `assets/first_meeting/icons/`.
  final String icon;
  final String title;

  /// Null while the state is not known; nothing is shown in its place.
  final String? status;
  final Key? statusKey;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: MeetingColors.raised,
    shape: _shape.copyWith(side: const BorderSide(color: MeetingColors.line)),
    child: InkWell(
      onTap: onTap,
      customBorder: _shape,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: Space.s2,
          ),
          child: Row(
            children: [
              Image.asset(
                icon,
                width: 32,
                height: 32,
                filterQuality: FilterQuality.none,
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: meetingType(15, 20, FontWeight.w700)),
                    if (status case final status?)
                      Text(
                        status,
                        key: statusKey,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
