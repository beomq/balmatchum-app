import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../records/product_page.dart' show PixelIcon, ProductColors, Space;
import 'domain/first_meeting.dart';
import 'meeting_theme.dart';

/// Pen values of ONB-06 (`uGbPl`) that the spacing scale does not hold.
abstract final class BreedPagerMetrics {
  /// The centered card's share of the pager width; the rest shows the
  /// neighbours (Pen `Breed Card Main` is 254 of 358).
  static const cardShare = .68;

  /// Neighbours are drawn smaller and faded (Pen `Breed Peek`).
  static const peekScale = .9;
  static const peekOpacity = .55;
  static const cardRadius = 22.0;
  static const cardInset = 14.0;
  static const artRadius = 16.0;
  static const copyGap = 10.0;
  static const copyLineGap = 2.0;
  static const tabHeight = 36.0;
  static const dot = 6.0;
  static const currentDot = 18.0;
  static const dotGap = 5.0;
  static const positionGap = 10.0;

  /// Room under the cards for the centered card's shadow (Pen y 8, blur 22).
  static const shadowRoom = 24.0;

  /// Everything else on the catalog step at 1x around the card: page
  /// padding, step bar, heading, tabs, position and the bottom buttons.
  static const chrome = 422.0;
}

/// One breed per card in the approved catalog order, the neighbours peeking
/// at the sides and no wrap at the ends. The caller owns the centered [index]
/// so its bottom button names the breed the card shows (guide 4.2-5); swipes,
/// tabs, arrows and a tap on a neighbour report a new one through
/// [onChanged]. Only a tap on the centered card selects.
class BreedPager extends StatefulWidget {
  const BreedPager({
    required this.index,
    required this.onChanged,
    required this.onSelect,
    this.enabled = true,
    super.key,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final ValueChanged<DogBreed> onSelect;
  final bool enabled;

  /// The card a visit opens on: the previous candidate, or G1's first.
  static int indexOf(String? breedId) => FirstMeetingCatalog.breeds
      .indexWhere((b) => b.id == breedId)
      .clamp(0, FirstMeetingCatalog.breeds.length - 1);

  @override
  State<BreedPager> createState() => _BreedPagerState();
}

class _BreedPagerState extends State<BreedPager> {
  static const _breeds = FirstMeetingCatalog.breeds;
  static const _groups = FirstMeetingCatalog.groups;
  static const _step = Duration(milliseconds: 250);

  // The caller's index decides the first card, not a page remembered elsewhere.
  late final pages = PageController(
    initialPage: widget.index,
    keepPage: false,
    viewportFraction: BreedPagerMetrics.cardShare,
  );
  final tabs = ScrollController();
  final tabKeys = [for (final _ in _groups) GlobalKey()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealTab(widget.index, animate: false),
    );
  }

  @override
  void dispose() {
    pages.dispose();
    tabs.dispose();
    super.dispose();
  }

  void _show(int target, {bool animate = true}) {
    if (target == widget.index || target < 0 || target >= _breeds.length) {
      return;
    }
    if (animate) {
      pages.animateToPage(target, duration: _step, curve: Curves.easeOutCubic);
    } else {
      pages.jumpToPage(target);
    }
  }

  void _changed(int value) {
    widget.onChanged(value);
    _revealTab(value, animate: true);
  }

  /// Centers the shown breed's group tab in the strip. Tab widths follow
  /// their names, so the strip asks the laid-out tab for its offset; the page
  /// itself does not scroll.
  void _revealTab(int index, {required bool animate}) {
    if (!mounted || !tabs.hasClients) return;
    final group = _groups.indexWhere((g) => g.id == _breeds[index].groupId);
    final tab = tabKeys[group].currentContext?.findRenderObject();
    if (tab == null) return;
    final position = tabs.position;
    final offset = RenderAbstractViewport.of(tab)
        .getOffsetToReveal(tab, .5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (animate) {
      tabs.animateTo(offset, duration: _step, curve: Curves.easeOut);
    } else {
      tabs.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _breeds[widget.index];
    final scale = MediaQuery.textScalerOf(context);
    // MeetingPage reports the SafeArea viewport. The card also grows with its
    // own two text lines so a larger text size keeps the art.
    final cardHeight =
        (MediaQuery.sizeOf(context).height - BreedPagerMetrics.chrome).clamp(
          240.0,
          460.0,
        ) +
        scale.scale(16) -
        16 +
        scale.scale(30) -
        30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          key: const ValueKey('breed_group_tabs'),
          controller: tabs,
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: Space.s2,
            children: [
              for (final (i, group) in _groups.indexed)
                BreedGroupTab(
                  key: tabKeys[i],
                  group: group,
                  selected: group.id == current.groupId,
                  onTap: () => _show(
                    _breeds.indexWhere((b) => b.groupId == group.id),
                    animate: false,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        SizedBox(
          height: cardHeight + BreedPagerMetrics.shadowRoom,
          child: PageView.builder(
            key: const ValueKey('breed_pager'),
            controller: pages,
            itemCount: _breeds.length,
            onPageChanged: _changed,
            itemBuilder: (context, i) => Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: cardHeight,
                child: AnimatedBuilder(
                  animation: pages,
                  builder: (context, card) {
                    final page =
                        pages.hasClients && pages.position.haveDimensions
                        ? pages.page!
                        : widget.index.toDouble();
                    final away = (page - i).abs().clamp(0.0, 1.0);
                    return Opacity(
                      opacity: 1 - (1 - BreedPagerMetrics.peekOpacity) * away,
                      child: Transform.scale(
                        scale: 1 - (1 - BreedPagerMetrics.peekScale) * away,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              BreedPagerMetrics.cardRadius,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: MeetingColors.cardShadow.withValues(
                                  alpha:
                                      MeetingColors.cardShadow.a * (1 - away),
                                ),
                                offset: const Offset(0, 8),
                                blurRadius: 22,
                              ),
                            ],
                          ),
                          child: card,
                        ),
                      ),
                    );
                  },
                  // A neighbour only steps aside; it never selects, so the
                  // card and the bottom button always name the same breed.
                  child: ExcludeSemantics(
                    excluding: i != widget.index,
                    child: _BreedCard(
                      breed: _breeds[i],
                      onTap: !widget.enabled
                          ? null
                          : i == widget.index
                          ? () => widget.onSelect(_breeds[i])
                          : () => _show(i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            _StepButton(
              key: const ValueKey('breed_pager_previous'),
              tooltip: '이전 품종',
              mirrored: false,
              onPressed: widget.index == 0
                  ? null
                  : () => _show(widget.index - 1),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: BreedPagerMetrics.positionGap,
                children: [
                  ExcludeSemantics(
                    child: _Dots(index: widget.index, count: _breeds.length),
                  ),
                  Flexible(
                    child: Text(
                      '${widget.index + 1} / ${_breeds.length}',
                      key: const ValueKey('breed_pager_position'),
                      style:
                          meetingType(
                            13,
                            18,
                            FontWeight.w800,
                            MeetingColors.muted,
                          ).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                ],
              ),
            ),
            _StepButton(
              key: const ValueKey('breed_pager_next'),
              tooltip: '다음 품종',
              mirrored: true,
              onPressed: widget.index == _breeds.length - 1
                  ? null
                  : () => _show(widget.index + 1),
            ),
          ],
        ),
      ],
    );
  }
}

/// A group tab of ONB-06 (Pen `Chip/Text` in `Breed Group Tabs`): the
/// group's user-facing name from the catalog, primary-strong once selected.
/// The pill is 36 pt; the tap target keeps the 48 pt minimum.
class BreedGroupTab extends StatelessWidget {
  const BreedGroupTab({
    required this.group,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final DogGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton(
      key: ValueKey('breed_group_${group.id}'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? MeetingColors.primaryStrong
            : MeetingColors.raised,
        foregroundColor: selected ? MeetingColors.raised : MeetingColors.muted,
        // The same stroke width either way, so selecting never resizes a tab.
        side: BorderSide(
          color: selected ? MeetingColors.primaryStrong : MeetingColors.line,
        ),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, BreedPagerMetrics.tabHeight),
        padding: const EdgeInsets.symmetric(horizontal: Space.s3),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: meetingType(13, 18, FontWeight.w700),
      ),
      child: Text(group.name),
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
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: MeetingColors.raised,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BreedPagerMetrics.cardRadius),
          side: const BorderSide(color: MeetingColors.line),
        ),
        child: InkWell(
          key: ValueKey('breed_${breed.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(BreedPagerMetrics.cardInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ProductColors.recordSoft,
                      borderRadius: BorderRadius.circular(
                        BreedPagerMetrics.artRadius,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(Space.s2),
                      child: Image.asset(
                        breed.spritePath,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: BreedPagerMetrics.copyGap),
                // ⑦ is open: the group name only, no trait chips (guide 9.1).
                Text(
                  group.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meetingType(
                    12,
                    16,
                    FontWeight.w700,
                    MeetingColors.muted,
                  ),
                ),
                const SizedBox(height: BreedPagerMetrics.copyLineGap),
                // One line on every card, so all 30 arts keep one size.
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(30),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      breed.name,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pen `Breed Dots`: five dots around the shown card, the current one long.
/// The `n / 30` beside it carries the position for assistive technology.
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final first = (index - _shown ~/ 2).clamp(0, count - _shown);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: BreedPagerMetrics.dotGap,
      children: [
        for (var i = first; i < first + _shown; i++)
          Container(
            width: i == index
                ? BreedPagerMetrics.currentDot
                : BreedPagerMetrics.dot,
            height: BreedPagerMetrics.dot,
            decoration: BoxDecoration(
              color: i == index ? MeetingColors.primary : MeetingColors.line,
              borderRadius: BorderRadius.circular(BreedPagerMetrics.dot / 2),
            ),
          ),
      ],
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
    style: IconButton.styleFrom(fixedSize: const Size.square(48)),
    icon: Opacity(
      opacity: onPressed == null ? .3 : 1,
      child: Transform.flip(
        flipX: mirrored,
        child: const PixelIcon('back', size: 24),
      ),
    ),
  );
}
