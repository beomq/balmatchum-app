import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'meeting_theme.dart';

/// The home's `Home/Status Tile` grid (`F9fHc6`): two columns, or one once
/// the text size no longer fits a status line beside a tile icon.
class MeetingShortcuts extends StatelessWidget {
  const MeetingShortcuts({required this.children, super.key});
  final List<Widget> children;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final label = TextPainter(
        text: TextSpan(
          text: '착용 중 · 조끼',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      // Icon 32, its gap 12 and the tile's 12 padding on both sides.
      final minimum = label.width + 32 + 12 * 3;
      label.dispose();
      if ((bounds.maxWidth - _gap) / 2 < minimum) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _gap,
          children: children,
        );
      }
      return Column(
        spacing: _gap,
        children: [
          for (var i = 0; i < children.length; i += 2)
            // Both tiles of a row share the taller one's height.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[i]),
                  const SizedBox(width: _gap),
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

class MeetingHomeLayout extends StatelessWidget {
  const MeetingHomeLayout({
    required this.header,
    required this.scene,
    required this.status,
    required this.shortcuts,
    this.footer,
    super.key,
  });
  final Widget header;
  final Widget scene;
  final Widget status;

  /// Null while the Duo side rail carries the shortcuts.
  final Widget? shortcuts;

  /// Only the Dev local flow says where it saves; Pen home A has no footer.
  final Widget? footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final twoColumns =
          MediaQuery.sizeOf(context).width >= 840 &&
          (bounds.maxWidth - 24) * .45 >= 300;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status,
          if (shortcuts case final shortcuts?) ...[
            const SizedBox(height: 16),
            shortcuts,
          ],
        ],
      );
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: twoColumns ? 1200 : 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              if (twoColumns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 55, child: scene),
                    const SizedBox(width: 24),
                    Expanded(flex: 45, child: details),
                  ],
                )
              else ...[
                scene,
                const SizedBox(height: 16),
                details,
              ],
              if (footer case final footer?) ...[
                const SizedBox(height: 16),
                footer,
              ],
            ],
          ),
        ),
      );
    },
  );
}

class MeetingPage extends StatelessWidget {
  const MeetingPage({
    required this.children,
    this.onBack,
    this.wide = false,
    this.showHeader = true,
    this.rail,
    this.onRefresh,
    this.header,
    this.footer,
    super.key,
  });
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool wide;
  final bool showHeader;

  /// Replaces the back slot, as the goal step's step bar does (guide 4.4-1).
  final Widget? header;

  /// Sits at the bottom of a short page and follows the children on a long
  /// one, as the goal step's start button does (guide 4.4-6).
  final Widget? footer;

  /// Duo side-column rail, painted outside the SafeArea.
  final Widget? rail;

  /// Pull-to-refresh, given only by the home; onboarding keeps a plain
  /// scroll (guide 3.1).
  final RefreshCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = constraints.maxWidth < 360
                  ? 12.0
                  : constraints.maxWidth < 600
                  ? 16.0
                  : constraints.maxWidth < 840
                  ? 24.0
                  : 32.0;
              const top = 16.0;
              const bottom = 24.0;
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The slot stays while the rail or a busy step
                  // hides back, so the focused name field never moves.
                  if (showHeader) ...[
                    header ??
                        SizedBox(
                          height: 48,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: onBack == null
                                ? const SizedBox.shrink()
                                : IconButton(
                                    key: const ValueKey('meeting_back'),
                                    tooltip: '이전 단계',
                                    onPressed: onBack,
                                    icon: Image.asset(
                                      'assets/first_meeting/icons/back.png',
                                      width: 32,
                                      height: 32,
                                      filterQuality: FilterQuality.none,
                                    ),
                                  ),
                          ),
                        ),
                    SizedBox(height: header == null ? 18 : 16),
                  ],
                  ...children,
                ],
              );
              final footer = this.footer;
              final scroll = SingleChildScrollView(
                // Busy callbacks must not replace the focused name field subtree.
                key: PageStorageKey(key ?? 'meeting_root_scroll'),
                padding: EdgeInsets.fromLTRB(padding, top, padding, bottom),
                // A short home must still be pullable.
                physics: onRefresh == null
                    ? null
                    : const AlwaysScrollableScrollPhysics(),
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(size: constraints.biggest),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: wide ? 960 : 480,
                        // The page fills the viewport so a footer can rest at
                        // its bottom; no intrinsic pass is needed.
                        minHeight: footer == null
                            ? 0
                            : math.max(
                                0.0,
                                constraints.maxHeight - top - bottom,
                              ),
                      ),
                      child: footer == null
                          ? content
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                content,
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: footer,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
              return switch (onRefresh) {
                final refresh? => RefreshIndicator(
                  onRefresh: refresh,
                  child: scroll,
                ),
                null => scroll,
              };
            },
          ),
        ),
        ?rail,
      ],
    ),
  );
}

class MeetingHeading extends StatelessWidget {
  const MeetingHeading(this.title, this.description, {super.key});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(description),
      ],
    ),
  );
}

class MeetingNotice extends StatelessWidget {
  const MeetingNotice(this.title, this.body, {this.warning = false, super.key});
  final String title;
  final String body;

  /// ONB-07 Warning: warning-soft fill with a line stroke.
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: warning ? MeetingColors.warningSoft : MeetingColors.pressed,
      border: warning ? Border.all(color: MeetingColors.line) : null,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );
}

class MeetingChoice extends StatelessWidget {
  const MeetingChoice({
    required this.title,
    required this.description,
    required this.onTap,
    this.icon,
    this.color = MeetingColors.soft,
    super.key,
  });
  final String title;
  final String description;
  final String? icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                if (icon != null) ...[
                  Image.asset(
                    icon!,
                    width: 48,
                    height: 48,
                    filterQuality: FilterQuality.none,
                  ),
                  const SizedBox(width: 24),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(description),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
