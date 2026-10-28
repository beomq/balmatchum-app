import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;

import '../../app/duo_rail.dart';
import '../first_meeting/meeting_theme.dart';

/// Pen semantic variables (2026-09-28 olive palette) the meeting palette
/// lacks; DESIGN.md still lists the superseded green values.
abstract final class ProductColors {
  static const record = Color(0xFF637348);
  static const recordSoft = MeetingColors.green;
  static const error = Color(0xFFA74638);
  static const warningSoft = Color(0xFFFFF1CC);
  static const attention = Color(0xFFA97600);
  static const raised = Colors.white;

  /// Pen literals without a variable: the wrong result chip and the review
  /// rows' divider (`dmEHl`), the correct quiz option's label and the quiz
  /// result panel's shadow (`aZln1`).
  static const errorSoft = Color(0xFFF8E3DF);
  static const divider = Color(0xFFF3EADC);
  static const recordInk = Color(0xFF2F3A1E);
  static const panelShadow = Color(0x2450301E);
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

/// A pixel icon of `assets/first_meeting/icons/`: the design library's
/// display/32 PNG drawn with nearest sampling, like the app's other icons.
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.name, {this.size = 32, super.key});

  /// The library file name without `.png`, such as `home` or `close-x`.
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/first_meeting/icons/$name.png',
    width: size,
    height: size,
    filterQuality: FilterQuality.none,
  );
}

/// TopBar back-and-home variant with 44px targets. A [title] sits centered
/// between them, as Pen `TopBar/Standard` does with its title on.
class ProductTopBar extends StatelessWidget {
  const ProductTopBar({
    required this.onBack,
    required this.onHome,
    this.title,
    super.key,
  });
  final VoidCallback onBack;
  final VoidCallback onHome;
  final String? title;

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
        if (title case final title?)
          // Between equal buttons, so centered on the page and never under
          // either button.
          Expanded(child: ProductTitle(title, textAlign: TextAlign.center))
        else
          const Spacer(),
        IconButton(
          key: const ValueKey('product_home'),
          tooltip: '홈',
          onPressed: onHome,
          icon: const PixelIcon('home'),
        ),
      ],
    ),
  );
}

/// `TopBar/Standard` title: 18/700 ink on one line, announced as a header.
class ProductTitle extends StatelessWidget {
  const ProductTitle(this.title, {this.textAlign = TextAlign.start, super.key});
  final String title;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      key: const ValueKey('product_title'),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: meetingType(18, 24, FontWeight.w700),
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
    this.title,
    this.footer,
    this.centerFooter = false,
    super.key,
  });
  final VoidCallback onBack;
  final VoidCallback onHome;
  final List<Widget> children;
  final double maxWidth;

  /// In the top bar between back and home. With the Duo rail, which takes
  /// back and home, it keeps the bar's row on its own at the start (Pen
  /// `n6oQN3`).
  final String? title;

  /// The rest of a page that fills the screen: below [children], at the
  /// bottom edge, or in the middle of the space left when [centerFooter].
  /// It scrolls with [children] when the screen is too short. It gets the
  /// page gutter, spans the safe width without it and pads the bottom inset
  /// itself, so a panel can reach the bottom edge.
  final Widget Function(double gutter)? footer;
  final bool centerFooter;

  @override
  Widget build(BuildContext context) {
    final spec = DuoRailSpec(
      tools: duoBackHome(onBack: onBack, onHome: onHome),
    );
    final mode = duoRailMode(MediaQuery.of(context), spec);
    final footer = this.footer;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            bottom: footer == null,
            child: LayoutBuilder(
              builder: (context, bounds) {
                final gutter = pageGutter(bounds.maxWidth);
                final content = Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mode == null) ...[
                          ProductTopBar(
                            onBack: onBack,
                            onHome: onHome,
                            title: title,
                          ),
                          const SizedBox(height: Space.s3),
                        ] else if (title case final title?) ...[
                          SizedBox(
                            height: 48,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: ProductTitle(title),
                            ),
                          ),
                          const SizedBox(height: Space.s3),
                        ],
                        ...children,
                      ],
                    ),
                  ),
                );
                if (footer == null) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      Space.s2,
                      gutter,
                      Space.s6,
                    ),
                    child: content,
                  );
                }
                // The leftover height is spread between the children, so
                // no intrinsic layout pass is needed.
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: bounds.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          // Keeps a gap when the footer follows directly.
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            Space.s2,
                            gutter,
                            Space.s4,
                          ),
                          child: content,
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxWidth + gutter * 2,
                            ),
                            child: footer(gutter),
                          ),
                        ),
                        if (centerFooter) const SizedBox.shrink(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (mode != null) DuoRail(spec: spec, mode: mode),
        ],
      ),
    );
  }
}

/// Loading or failure body with an explicit retry.
class ProductLoadState extends StatelessWidget {
  const ProductLoadState({
    required this.error,
    required this.onRetry,
    this.retryKey = const ValueKey('product_retry'),
    super.key,
  });

  /// Null while loading.
  final String? error;
  final VoidCallback onRetry;
  final Key retryKey;

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
                  key: retryKey,
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

/// Development fixture markers belong to the dev flavor only. Production
/// builds hide the marker and keep the fixture data itself (guide 3.1).
bool get fixtureLabelsVisible =>
    debugFixtureLabelsVisible ?? appFlavor == 'dev';

/// Test override for [fixtureLabelsVisible]; null follows the build flavor.
@visibleForTesting
bool? debugFixtureLabelsVisible;

/// Marks server content or amounts that are development fixtures, so they
/// are never mistaken for operating values. Callers draw it only while
/// [fixtureLabelsVisible].
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
