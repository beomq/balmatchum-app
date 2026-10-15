import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';

/// Semantic colors from app-v2 DESIGN.md that the meeting palette lacks.
abstract final class ProductColors {
  static const record = Color(0xFF47815E);
  static const recordSoft = Color(0xFFE8F3EA);
  static const error = Color(0xFFA74638);
  static const warningSoft = Color(0xFFFFF1CC);
  static const attention = Color(0xFFA97600);
  static const raised = Colors.white;
}

/// DESIGN.md spacing scale (space/1..8).
abstract final class Space {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
}

/// RESPONSIVE.md page gutter chosen from the SafeArea width.
double pageGutter(double width) => width < 360
    ? 12
    : width < 600
    ? 16
    : width < 840
    ? 24
    : 32;

/// TopBar back-and-home variant: 44px targets, no centered duplicate title.
class ProductTopBar extends StatelessWidget {
  const ProductTopBar({required this.onBack, required this.onHome, super.key});
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('product_back'),
          tooltip: '뒤로',
          onPressed: onBack,
          icon: Image.asset(
            'assets/first_meeting/icons/back.png',
            width: 32,
            height: 32,
            filterQuality: FilterQuality.none,
          ),
        ),
        const Spacer(),
        IconButton(
          key: const ValueKey('product_home'),
          tooltip: '홈',
          onPressed: onHome,
          icon: const Icon(Icons.home_outlined, color: MeetingColors.ink),
        ),
      ],
    ),
  );
}

/// Scrolling single-column page with the shared gutter and max width.
class ProductPage extends StatelessWidget {
  const ProductPage({
    required this.onBack,
    required this.onHome,
    required this.children,
    this.maxWidth = 640,
    super.key,
  });
  final VoidCallback onBack;
  final VoidCallback onHome;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final gutter = pageGutter(bounds.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(gutter, Space.s2, gutter, Space.s6),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProductTopBar(onBack: onBack, onHome: onHome),
                    const SizedBox(height: Space.s3),
                    ...children,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Loading or failure body with an explicit retry.
class ProductLoadState extends StatelessWidget {
  const ProductLoadState({
    required this.error,
    required this.onRetry,
    super.key,
  });

  /// Null while loading.
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s8),
    child: error == null
        ? const Center(
            child: CircularProgressIndicator(
              key: ValueKey('product_loading'),
              color: MeetingColors.primary,
            ),
          )
        : ProductPanel(
            color: ProductColors.warningSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(error!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: Space.s3),
                FilledButton(
                  key: const ValueKey('product_retry'),
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
  );
}

class ProductPanel extends StatelessWidget {
  const ProductPanel({
    required this.child,
    this.color = ProductColors.raised,
    super.key,
  });
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MeetingColors.line),
    ),
    child: child,
  );
}

/// Marks server content or amounts that are development fixtures, so they
/// are never mistaken for operating values.
class FixtureBadge extends StatelessWidget {
  const FixtureBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      key: const ValueKey('product_fixture_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.s1,
      ),
      decoration: BoxDecoration(
        color: ProductColors.warningSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ProductColors.attention),
      ),
      child: Text(
        '개발 검증용 · $label',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: MeetingColors.ink),
      ),
    ),
  );
}

String formatCount(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
