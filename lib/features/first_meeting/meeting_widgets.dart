import 'package:flutter/material.dart';

import 'meeting_theme.dart';

class MeetingShortcuts extends StatelessWidget {
  const MeetingShortcuts({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final label = TextPainter(
        text: TextSpan(
          text: '꾸미기',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final minimum = (label.width + 48).clamp(72.0, double.infinity);
      label.dispose();
      final columns = (bounds.maxWidth - 36) / 4 >= minimum
          ? 4
          : (bounds.maxWidth - 12) / 2 >= minimum
          ? 2
          : 1;
      final width = (bounds.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
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
    required this.footer,
    super.key,
  });
  final Widget header;
  final Widget scene;
  final Widget status;
  final Widget shortcuts;
  final Widget footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final twoColumns =
          bounds.maxWidth >= 776 && (bounds.maxWidth - 24) * .45 >= 300;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [status, const SizedBox(height: 16), shortcuts],
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
              const SizedBox(height: 16),
              footer,
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
    super.key,
  });
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool wide;
  final bool showHeader;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 360
              ? 12.0
              : constraints.maxWidth < 600
              ? 16.0
              : constraints.maxWidth < 840
              ? 24.0
              : 32.0;
          return SingleChildScrollView(
            key: PageStorageKey(
              onBack == null ? 'meeting_root_scroll' : 'meeting_scroll',
            ),
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 960 : 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showHeader)
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
                    if (showHeader) const SizedBox(height: 18),
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
  const MeetingNotice(this.title, this.body, {super.key});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: MeetingColors.pressed,
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
