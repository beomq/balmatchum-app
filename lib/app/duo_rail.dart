import 'package:flutter/material.dart';

import '../features/first_meeting/meeting_theme.dart';
import '../features/records/product_page.dart' show ProductColors;

enum DuoRailSide { left, right }

/// A null mode means the screen keeps its current layout without the rail.
enum DuoRailMode { full, compact }

/// Measured on the Xcode 27.1 iOS 27.1 iPhone Duo simulator, 2026-10-28.
abstract final class DuoRailMetrics {
  static const minSideInset = 60.0;
  static const axisFromEdge = 48.0;
  static const bottomGap = 2.0;
  static const statusBottomMax = 235.0;
  static const icon = 44.0;
  static const labeled = 64.0;
  static const labeledGap = 8.0;
  static const iconGap = 12.0;
  static const dividerBlock = 28.0; // 12 + 1 + 15
}

class DuoRailItem {
  const DuoRailItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.badgeLabel,
  });
  final Key key;
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final String? badgeLabel;
}

/// tools: icon only (settings, back, home). destinations: icon and label
/// (home shortcuts).
class DuoRailSpec {
  const DuoRailSpec({this.tools = const [], this.destinations = const []});
  final List<DuoRailItem> tools;
  final List<DuoRailItem> destinations;

  double height(DuoRailMode mode) {
    double stack(int n, double size, double gap) =>
        n == 0 ? 0 : n * size + (n - 1) * gap;
    final full = mode == DuoRailMode.full;
    return stack(tools.length, DuoRailMetrics.icon, DuoRailMetrics.iconGap) +
        (tools.isNotEmpty && destinations.isNotEmpty
            ? DuoRailMetrics.dividerBlock
            : 0) +
        stack(
          destinations.length,
          full ? DuoRailMetrics.labeled : DuoRailMetrics.icon,
          full ? DuoRailMetrics.labeledGap : DuoRailMetrics.iconGap,
        );
  }
}

/// Pass only padding read above the SafeArea; inside it the insets are 0.
DuoRailSide? duoRailSide(EdgeInsets padding) {
  if (padding.right >= DuoRailMetrics.minSideInset && padding.left == 0) {
    return DuoRailSide.right;
  }
  if (padding.left >= DuoRailMetrics.minSideInset && padding.right == 0) {
    return DuoRailSide.left;
  }
  return null;
}

DuoRailMode? duoRailMode(MediaQueryData media, DuoRailSpec spec) {
  if (duoRailSide(media.padding) == null) return null;
  if (media.viewInsets.bottom > 0) return null;
  final available =
      media.size.height -
      media.padding.bottom -
      DuoRailMetrics.bottomGap -
      DuoRailMetrics.statusBottomMax;
  final largeText = media.textScaler.scale(12) > 16;
  if (!largeText && spec.height(DuoRailMode.full) <= available) {
    return DuoRailMode.full;
  }
  if (spec.height(DuoRailMode.compact) <= available) return DuoRailMode.compact;
  return null;
}

/// Back button shared by the onboarding steps and the sub screens.
DuoRailItem duoBack(VoidCallback? onBack) => DuoRailItem(
  key: const ValueKey('duo_rail_back'),
  label: '뒤로',
  icon: Image.asset(
    'assets/first_meeting/icons/back.png',
    filterQuality: FilterQuality.none,
  ),
  onPressed: onBack,
);

/// Back and home group shared by the sub screens.
List<DuoRailItem> duoBackHome({
  required VoidCallback? onBack,
  required VoidCallback? onHome,
}) => [
  duoBack(onBack),
  DuoRailItem(
    key: const ValueKey('duo_rail_home'),
    label: '홈',
    icon: const Icon(Icons.home_outlined, color: MeetingColors.ink),
    onPressed: onHome,
  ),
];

/// Last child of a `Stack(fit: StackFit.expand)` above the screen SafeArea.
class DuoRail extends StatelessWidget {
  const DuoRail({required this.spec, required this.mode, super.key});
  final DuoRailSpec spec;
  final DuoRailMode mode;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final right = duoRailSide(media.padding) == DuoRailSide.right;
    final inset = right ? media.padding.right : media.padding.left;
    const line = BorderSide(color: MeetingColors.line);
    final full = mode == DuoRailMode.full;
    return Stack(
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          width: inset,
          right: right ? 0 : null,
          left: right ? null : 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x0A50301E),
              border: Border(
                left: right ? line : BorderSide.none,
                right: right ? BorderSide.none : line,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: media.padding.bottom + DuoRailMetrics.bottomGap,
          width: DuoRailMetrics.axisFromEdge * 2,
          right: right ? 0 : null,
          left: right ? null : 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, item) in spec.tools.indexed) ...[
                if (i > 0) const SizedBox(height: DuoRailMetrics.iconGap),
                _RailIconButton(item: item),
              ],
              if (spec.tools.isNotEmpty && spec.destinations.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SizedBox(
                  width: 40,
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: MeetingColors.line,
                  ),
                ),
                const SizedBox(height: 15),
              ],
              for (final (i, item) in spec.destinations.indexed) ...[
                if (i > 0)
                  SizedBox(
                    height: full
                        ? DuoRailMetrics.labeledGap
                        : DuoRailMetrics.iconGap,
                  ),
                full
                    ? _RailLabeledButton(item: item)
                    : _RailIconButton(item: item),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({required this.item});
  final DuoRailItem item;

  @override
  Widget build(BuildContext context) => IconButton(
    key: item.key,
    tooltip: item.badgeLabel == null
        ? item.label
        : '${item.label}, ${item.badgeLabel}',
    onPressed: item.onPressed,
    style: IconButton.styleFrom(
      backgroundColor: ProductColors.raised,
      side: const BorderSide(color: MeetingColors.line),
      fixedSize: const Size.square(DuoRailMetrics.icon),
      padding: EdgeInsets.zero,
      // The default 48 tap target would raise the group top by 4pt.
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Badge(
      isLabelVisible: item.badgeLabel != null,
      smallSize: 8,
      child: SizedBox.square(dimension: 24, child: item.icon),
    ),
  );
}

class _RailLabeledButton extends StatelessWidget {
  const _RailLabeledButton({required this.item});
  final DuoRailItem item;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: item.badgeLabel == null
        ? item.label
        : '${item.label}, ${item.badgeLabel}',
    excludeFromSemantics: true,
    child: SizedBox.square(
      dimension: DuoRailMetrics.labeled,
      child: OutlinedButton(
        key: item.key,
        onPressed: item.onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: ProductColors.raised,
          side: const BorderSide(color: MeetingColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          minimumSize: const Size.square(DuoRailMetrics.labeled),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: item.badgeLabel != null,
              smallSize: 8,
              child: SizedBox.square(dimension: 28, child: item.icon),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            if (item.badgeLabel case final badge?)
              Semantics(label: badge, child: const SizedBox.shrink()),
          ],
        ),
      ),
    ),
  );
}
