import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../first_meeting/meeting_widgets.dart';
import '../records/product_page.dart';

/// Pen `V2 · SET · 설정` (`o39c7Y`) measurements without a variable.
abstract final class SettingsMetrics {
  /// The settings body's gap between the card, labels and groups.
  static const gap = 10.0;

  /// `SettingsRow/*`: the row height, its icon well and the well's radius.
  static const row = 64.0;
  static const well = 36.0;
  static const wellRadius = 10.0;

  /// A group panel's vertical padding around its rows.
  static const groupPadding = 5.0;
}

/// `SettingsRow/*`: an optional icon well with a 20 pt pixel icon, a 15/700
/// title over a 13/500 state line, and a caret when the row opens something.
/// Larger text grows the 64 pt row instead of clipping it.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.icon,
    this.value,
    this.valueKey,
    this.onTap,
    super.key,
  });

  /// A [PixelIcon] name; null draws the row without its well (SET-09).
  final String? icon;
  final String title;

  /// Null while the state is not known; nothing is shown in its place.
  final String? value;
  final Key? valueKey;

  /// A row without an action only shows its value and draws no caret.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final value = this.value;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SettingsMetrics.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          child: Row(
            spacing: Space.s3,
            children: [
              if (icon != null)
                Container(
                  width: SettingsMetrics.well,
                  height: SettingsMetrics.well,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: MeetingColors.soft,
                    borderRadius: BorderRadius.all(
                      Radius.circular(SettingsMetrics.wellRadius),
                    ),
                  ),
                  child: PixelIcon(icon, size: 20),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(title, style: meetingType(15, 20, FontWeight.w700)),
                    if (value != null)
                      Text(
                        value,
                        key: valueKey,
                        style: meetingType(
                          13,
                          18,
                          FontWeight.w500,
                          MeetingColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null) const PixelIcon('caret-right', size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Settings Group …`: a 13/700 muted label over a raised panel with the
/// line stroke and the panel radius that holds [SettingsRow]s.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, this.label, super.key});
  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SettingsMetrics.gap,
    children: [
      if (label case final label?)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, 0),
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: meetingType(13, 18, FontWeight.w700, MeetingColors.muted),
            ),
          ),
        ),
      Material(
        color: MeetingColors.raised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: MeetingColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: SettingsMetrics.groupPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

/// The title and copy of a settings notice inside a [ProductPanel]
/// (`Shared/Rule`, `Shared/Purpose`).
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.title, this.body, {super.key});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.s2,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      Text(body),
    ],
  );
}

/// SET-07 and SET-15: a heading, notices, one confirm button and a quiet
/// cancel. While [busy] the page is locked, so back, home, cancel and a
/// second confirm do nothing until the request answers.
class SettingsConfirmPage extends StatelessWidget {
  const SettingsConfirmPage({
    required this.title,
    required this.description,
    required this.notices,
    required this.confirm,
    required this.busy,
    required this.onBack,
    required this.onHome,
    required this.lockKey,
    required this.cancelKey,
    required this.progressKey,
    super.key,
  });
  final String title;
  final String description;
  final List<Widget> notices;

  /// The page's one filled button, disabled by its owner while [busy].
  final Widget confirm;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final Key lockKey;
  final Key cancelKey;
  final Key progressKey;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AbsorbPointer(
      key: lockKey,
      absorbing: busy,
      child: ProductPage(
        onBack: onBack,
        onHome: onHome,
        children: [
          MeetingHeading(title, description),
          for (final notice in notices) ...[
            notice,
            const SizedBox(height: Space.s4),
          ],
          if (busy) ...[
            LinearProgressIndicator(
              key: progressKey,
              color: MeetingColors.primary,
            ),
            const SizedBox(height: Space.s3),
          ],
          confirm,
          const SizedBox(height: Space.s3),
          OutlinedButton(
            key: cancelKey,
            onPressed: busy ? null : onBack,
            child: const Text('취소'),
          ),
        ],
      ),
    ),
  );
}
