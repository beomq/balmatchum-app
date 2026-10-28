import 'package:flutter/material.dart';

import 'domain/first_meeting.dart';
import 'meeting_theme.dart';

/// One breed per card in the approved catalog order, starting at G1. Group
/// tabs jump to a group's first breed; tapping the card selects that breed.
class BreedPager extends StatefulWidget {
  const BreedPager({
    required this.onSelect,
    this.initialBreedId,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<DogBreed> onSelect;
  final String? initialBreedId;
  final bool enabled;

  @override
  State<BreedPager> createState() => _BreedPagerState();
}

class _BreedPagerState extends State<BreedPager> {
  static const _breeds = FirstMeetingCatalog.breeds;
  static const _groups = FirstMeetingCatalog.groups;
  static const _tabWidth = 52.0;
  static const _tabGap = 8.0;
  static const _step = Duration(milliseconds: 250);

  late int index = _breeds
      .indexWhere((b) => b.id == widget.initialBreedId)
      .clamp(0, _breeds.length - 1);
  // The candidate decides the first card, not a page remembered elsewhere.
  late final pages = PageController(initialPage: index, keepPage: false);
  final tabs = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealTab(false));
  }

  @override
  void dispose() {
    pages.dispose();
    tabs.dispose();
    super.dispose();
  }

  void _show(int target, {bool animate = true}) {
    if (target == index || target < 0 || target >= _breeds.length) return;
    if (animate) {
      pages.animateToPage(target, duration: _step, curve: Curves.easeOutCubic);
    } else {
      pages.jumpToPage(target);
    }
  }

  void _changed(int value) {
    setState(() => index = value);
    _revealTab(true);
  }

  /// Keeps the current group's tab in view without scrolling the page.
  void _revealTab(bool animate) {
    if (!mounted || !tabs.hasClients) return;
    final group = _groups.indexWhere((g) => g.id == _breeds[index].groupId);
    final position = tabs.position;
    final offset =
        (group * (_tabWidth + _tabGap) -
                (position.viewportDimension - _tabWidth) / 2)
            .clamp(0.0, position.maxScrollExtent);
    if (animate) {
      tabs.animateTo(offset, duration: _step, curve: Curves.easeOut);
    } else {
      tabs.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _breeds[index];
    final scale = MediaQuery.textScalerOf(context);
    // MeetingPage reports the SafeArea viewport; 300 is the heading, tabs,
    // controls and page padding above and below the card.
    final cardHeight =
        (MediaQuery.sizeOf(context).height - 300).clamp(260.0, 480.0) +
        scale.scale(30) -
        30 +
        scale.scale(17) -
        17;
    final tabHeight = scale.scale(14) + 30 < 44 ? 44.0 : scale.scale(14) + 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: tabHeight,
          child: ListView.separated(
            key: const ValueKey('breed_group_tabs'),
            controller: tabs,
            scrollDirection: Axis.horizontal,
            itemCount: _groups.length,
            separatorBuilder: (context, i) => const SizedBox(width: _tabGap),
            itemBuilder: (context, i) => _GroupTab(
              group: _groups[i],
              width: _tabWidth,
              selected: _groups[i].id == current.groupId,
              onTap: () => _show(
                _breeds.indexWhere((b) => b.groupId == _groups[i].id),
                animate: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardHeight,
          child: PageView.builder(
            key: const ValueKey('breed_pager'),
            controller: pages,
            itemCount: _breeds.length,
            onPageChanged: _changed,
            itemBuilder: (context, i) => _BreedCard(
              breed: _breeds[i],
              onTap: widget.enabled ? () => widget.onSelect(_breeds[i]) : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StepButton(
              key: const ValueKey('breed_pager_previous'),
              tooltip: '이전 품종',
              mirrored: false,
              onPressed: index == 0 ? null : () => _show(index - 1),
            ),
            Expanded(
              child: Text(
                '${index + 1} / ${_breeds.length}',
                key: const ValueKey('breed_pager_position'),
                textAlign: TextAlign.center,
                style: meetingType(
                  15,
                  20,
                  FontWeight.w700,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            _StepButton(
              key: const ValueKey('breed_pager_next'),
              tooltip: '다음 품종',
              mirrored: true,
              onPressed: index == _breeds.length - 1
                  ? null
                  : () => _show(index + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({
    required this.group,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final DogGroup group;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  // Wardrobe/Category Filter: primary-soft selected, raised otherwise.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: group.name,
    child: Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? MeetingColors.soft : MeetingColors.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('breed_group_${group.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: width,
            child: Center(
              child: Text(
                group.id,
                style: meetingType(
                  14,
                  20,
                  selected ? FontWeight.w700 : FontWeight.w600,
                  selected ? MeetingColors.primaryStrong : MeetingColors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BreedCard extends StatelessWidget {
  const _BreedCard({required this.breed, required this.onTap});

  final DogBreed breed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final group = FirstMeetingCatalog.groups.firstWhere(
      (g) => g.id == breed.groupId,
    );
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: MeetingColors.raised,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: MeetingColors.line),
        ),
        child: InkWell(
          key: ValueKey('breed_${breed.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${group.id} · ${group.name}',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MeetingColors.stage,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        breed.spritePath,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  breed.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.tooltip,
    required this.mirrored,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final bool mirrored;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size(48, 48),
      backgroundColor: MeetingColors.raised,
      disabledBackgroundColor: MeetingColors.raised,
      side: const BorderSide(color: MeetingColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Opacity(
      opacity: onPressed == null ? .3 : 1,
      child: Transform.flip(
        flipX: mirrored,
        child: Image.asset(
          'assets/first_meeting/icons/back.png',
          width: 24,
          height: 24,
          filterQuality: FilterQuality.none,
        ),
      ),
    ),
  );
}
