import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/duo_rail.dart';
import '../first_meeting/domain/dog_catalog.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/onboarding_widgets.dart' show wrapByWords;
import '../records/product_page.dart';
import '../records/status_widgets.dart';
import 'dog_sprite.dart';
import 'outfit_shelf.dart';
import 'wardrobe_models.dart';

/// The shelf whose action produced the current message.
enum _Shelf { theme, outfit }

/// Background themes and the approved outfit. Selecting a theme tile only
/// previews; purchase, equip and outfit changes are separate,
/// server-confirmed actions. An outfit is drawn only when the server says it
/// is worn and the app ships a layer on this dog's own sprite canvas.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    required this.dog,
    required this.loadWardrobe,
    required this.purchaseTheme,
    required this.equipTheme,
    required this.changeOutfit,
    required this.onBack,
    required this.onHome,
    super.key,
  });

  /// The selected companion; its approved sprite is never altered.
  final DogBreed dog;
  final LoadWardrobe loadWardrobe;
  final WardrobeThemeAction purchaseTheme;
  final WardrobeThemeAction equipTheme;
  final WardrobeOutfitAction changeOutfit;
  final VoidCallback onBack;

  /// Also used by the insufficient-points path to reach today's reward.
  final VoidCallback onHome;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  WardrobeSnapshot? snapshot;
  String? loadError;
  String? selectedId;
  bool busy = false;
  _Shelf shelf = _Shelf.theme;
  String? actionError;
  bool insufficient = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      snapshot = null;
      loadError = null;
    });
    try {
      final value = await widget.loadWardrobe();
      if (!mounted) return;
      setState(() {
        snapshot = value;
        selectedId ??= value.equippedThemeId;
      });
    } on Exception {
      if (mounted) setState(() => loadError = '꾸미기 정보를 불러오지 못했어요.');
    }
  }

  WardrobeTheme? get selected {
    for (final t in snapshot?.themes ?? const <WardrobeTheme>[]) {
      if (t.id == selectedId) return t;
    }
    return null;
  }

  WardrobeTheme? get equipped {
    for (final t in snapshot?.themes ?? const <WardrobeTheme>[]) {
      if (t.id == snapshot!.equippedThemeId) return t;
    }
    return null;
  }

  Future<void> run(
    _Shelf from,
    Future<WardrobeSnapshot> Function() action,
  ) async {
    setState(() {
      busy = true;
      shelf = from;
      actionError = null;
      insufficient = false;
    });
    try {
      final value = await action();
      if (!mounted) return;
      setState(() {
        snapshot = value;
        busy = false;
      });
    } on WardrobeActionException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        insufficient = e.reason == WardrobeFailureReason.insufficientPoints;
        actionError = switch (e.reason) {
          WardrobeFailureReason.insufficientPoints => '포인트가 부족해요.',
          WardrobeFailureReason.incompatible => '이 강아지는 아직 입을 수 없어요',
          WardrobeFailureReason.unavailable => switch (from) {
            _Shelf.theme => '지금은 이 배경을 사용할 수 없어요.',
            _Shelf.outfit => '지금은 이 의상을 사용할 수 없어요.',
          },
          WardrobeFailureReason.other => '처리하지 못했어요. 다시 시도해 주세요.',
        };
      });
    } on Exception {
      // A lost response does not mean nothing changed: the server may have
      // committed. Show its state so a retry is never sent blindly.
      try {
        final value = await widget.loadWardrobe();
        if (!mounted) return;
        setState(() {
          snapshot = value;
          busy = false;
          actionError = '응답을 받지 못해 서버의 현재 상태를 다시 불러왔어요.';
        });
      } on Exception {
        if (!mounted) return;
        setState(() {
          snapshot = null;
          busy = false;
          loadError = '처리 결과를 확인하지 못했어요. 다시 불러와 주세요.';
        });
      }
    }
  }

  /// Asks before points are spent (Pen 'V2 · WARD-02', XmVOx): the product's
  /// own picture, the balance before and after when both are known and one
  /// button naming the price. Only that button returns true; cancel and a
  /// tap outside send nothing.
  Future<bool> confirmSpend({
    required String title,
    required String note,
    required int price,
    required Widget thumbnail,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => _SpendDialog(
          title: title,
          note: note,
          price: price,
          // The latest server balance as the dialog opens.
          balance: snapshot?.balance,
          thumbnail: thumbnail,
        ),
      ) ==
      true;

  Future<void> confirmPurchase(WardrobeTheme theme) async {
    final ok = await confirmSpend(
      title: '${theme.name} 배경을 살까요?',
      note: '산 배경은 꾸미기에서 언제든 바꿀 수 있어요.\n구매 후 착용은 따로 선택해요.',
      price: theme.price!,
      thumbnail: _ThemeSurface(theme, keyPrefix: 'wardrobe_purchase'),
    );
    if (ok && mounted) {
      await run(_Shelf.theme, () => widget.purchaseTheme(theme));
    }
  }

  Future<void> changeOutfit(WardrobeOutfit outfit, OutfitChange change) async {
    final ok = switch (change) {
      OutfitChange.purchase => await confirmSpend(
        title: '${outfit.name} 의상을 살까요?',
        note: '산 의상은 꾸미기에서 언제든 입히고 벗길 수 있어요.\n구매 후 착용은 따로 선택해요.',
        price: outfit.price,
        // This breed's own layer on its own sprite; the shelf's hanger icon
        // is not the product.
        thumbnail: ColoredBox(
          color: MeetingColors.stage,
          child: Padding(
            padding: const EdgeInsets.all(Space.s2),
            child: DogSprite(
              asset: widget.dog.spritePath,
              layer: outfit.layerFor(widget.dog.id),
              spriteKey: const ValueKey('wardrobe_purchase_dog'),
              layerKey: const ValueKey('wardrobe_purchase_outfit'),
            ),
          ),
        ),
      ),
      OutfitChange.wear || OutfitChange.remove => true,
    };
    if (ok && mounted) {
      await run(_Shelf.outfit, () => widget.changeOutfit(outfit, change));
    }
  }

  void select(WardrobeTheme theme) => setState(() {
    selectedId = theme.id;
    actionError = null;
    insufficient = false;
  });

  @override
  Widget build(BuildContext context) {
    final spec = DuoRailSpec(
      tools: duoBackHome(onBack: widget.onBack, onHome: widget.onHome),
    );
    final mode = duoRailMode(MediaQuery.of(context), spec);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final w = bounds.maxWidth;
                final gutter = pageGutter(w);
                final content = (w - gutter * 2).clamp(0.0, 1200.0);
                final split = w >= 600;
                // RESPONSIVE.md 3: when a fixed action would leave no product row,
                // release it into the single scroll.
                final pinned =
                    bounds.maxHeight >= 600 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.5;
                final previewWidth = w >= 840
                    ? (content * .38).clamp(280.0, 360.0)
                    : 240.0;
                final s = snapshot;
                final header = Padding(
                  padding: EdgeInsets.fromLTRB(gutter, Space.s2, gutter, 0),
                  child: mode == null
                      ? ProductTopBar(
                          onBack: widget.onBack,
                          onHome: widget.onHome,
                          title: '꾸미기',
                        )
                      // The rail takes back and home; the title keeps the
                      // bar's row, as on the other sub screens.
                      : const SizedBox(
                          height: 48,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ProductTitle('꾸미기'),
                          ),
                        ),
                );
                if (s == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter),
                        child: ProductLoadState(
                          error: loadError,
                          onRetry: load,
                        ),
                      ),
                    ],
                  );
                }
                if (s.equippedThemeId == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Padding(
                        padding: EdgeInsets.all(gutter),
                        child: ProductLoadState(
                          error: '작업은 완료됐지만 현재 적용 상태를 확인하지 못했어요.',
                          onRetry: load,
                        ),
                      ),
                    ],
                  );
                }
                final preview = _Preview(
                  dogAsset: widget.dog.spritePath,
                  outfitLayer: s.outfits?.wornLayer(widget.dog.id),
                  theme: selected,
                  equipped:
                      selected != null && selected!.id == s.equippedThemeId,
                  balance: s.balance,
                  compact: !split && bounds.maxHeight < 600,
                );
                final list = _Catalog(
                  snapshot: s,
                  selectedId: selectedId,
                  onSelect: select,
                  maxColumns: w >= 840 ? 4 : 3,
                );
                final action = _ActionBar(
                  theme: selected,
                  equippedId: s.equippedThemeId,
                  balance: s.balance,
                  busy: busy,
                  error: shelf == _Shelf.theme ? actionError : null,
                  insufficient: shelf == _Shelf.theme && insufficient,
                  onPurchase: confirmPurchase,
                  onEquip: (t) => run(_Shelf.theme, () => widget.equipTheme(t)),
                  onEarnPoints: widget.onHome,
                );
                final outfitShelf = OutfitShelf(
                  outfits: s.outfits,
                  breedId: widget.dog.id,
                  balance: s.balance,
                  busy: busy,
                  error: shelf == _Shelf.outfit ? actionError : null,
                  insufficient: shelf == _Shelf.outfit && insufficient,
                  onChange: changeOutfit,
                  onReload: load,
                  onEarnPoints: widget.onHome,
                );
                final body = split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: previewWidth,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  preview,
                                  const SizedBox(height: Space.s3),
                                  action,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.s6),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  list,
                                  const SizedBox(height: Space.s6),
                                  outfitShelf,
                                  const SizedBox(height: Space.s3),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              gutter,
                              Space.s3,
                              gutter,
                              0,
                            ),
                            child:
                                body ??
                                SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      preview,
                                      const SizedBox(height: Space.s3),
                                      list,
                                      const SizedBox(height: Space.s6),
                                      outfitShelf,
                                      const SizedBox(height: Space.s3),
                                      if (!pinned) ...[
                                        action,
                                        const SizedBox(height: Space.s3),
                                      ],
                                    ],
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),
                    if (!split && pinned)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          Space.s2,
                          gutter,
                          Space.s2,
                        ),
                        child: action,
                      ),
                  ],
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

class _Preview extends StatelessWidget {
  const _Preview({
    required this.dogAsset,
    required this.outfitLayer,
    required this.theme,
    required this.equipped,
    required this.balance,
    required this.compact,
  });
  final String dogAsset;

  /// Server-confirmed worn layer on the [dogAsset] canvas; never a try-on.
  final String? outfitLayer;
  final WardrobeTheme? theme;

  /// The previewed theme is the one the server has applied.
  final bool equipped;

  /// Null while the server balance is unknown; never shown as 0.
  final int? balance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    // The tag tells a try-out from what the server applied (guide 7.6 3).
    final (String state, String caption) = t == null
        ? ('none', '배경 없음')
        : equipped
        ? ('equipped', '착용 중 · ${t.name}')
        : ('trial', '미리보기 · ${t.name}');
    final points = balance;
    final amount = points == null ? '확인 전' : '${formatCount(points)}P';
    return ClipRRect(
      key: const ValueKey('wardrobe_preview'),
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: compact ? 140 : 206,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (t == null)
              const ColoredBox(
                key: ValueKey('wardrobe_preview_color_null'),
                color: MeetingColors.soft,
              )
            else
              _ThemeSurface(t, keyPrefix: 'wardrobe_preview'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s8,
                Space.s8 + Space.s2,
                Space.s8,
                Space.s2,
              ),
              child: DogSprite(
                asset: dogAsset,
                layer: outfitLayer,
                spriteKey: const ValueKey('wardrobe_preview_dog'),
                layerKey: const ValueKey('wardrobe_preview_outfit'),
              ),
            ),
            Positioned(
              left: Space.s3,
              top: Space.s3,
              right: Space.s3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Container(
                      key: ValueKey('wardrobe_preview_$state'),
                      // Pen 'Wardrobe Preview Tag' (QoNLP), as the photo
                      // example tag.
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: const BoxDecoration(
                        color: ProductColors.photoTag,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        caption,
                        key: const ValueKey('wardrobe_preview_caption'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meetingType(12.5, 16, FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Semantics(
                    label: '보유 포인트 $amount',
                    excludeSemantics: true,
                    child: StatusChip(
                      amount,
                      icon: 'points',
                      key: const ValueKey('wardrobe_balance_chip'),
                      textKey: const ValueKey('wardrobe_balance'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A theme's surface wherever the shop draws it: its approved bundled
/// picture, else the server colour. Until more pictures are approved (guide
/// 9.1 ⑨) only sunny has one. The tile, the preview and the purchase dialog
/// share it, so a theme never looks different between them.
class _ThemeSurface extends StatelessWidget {
  const _ThemeSurface(this.theme, {required this.keyPrefix});
  final WardrobeTheme theme;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => switch (theme.backgroundAsset) {
    final asset? => Image.asset(
      asset,
      key: ValueKey('${keyPrefix}_bg_${theme.id}'),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.none,
    ),
    null => ColoredBox(
      key: ValueKey('${keyPrefix}_color_${theme.id}'),
      color: Color(theme.colorValue),
    ),
  };
}

class _Catalog extends StatelessWidget {
  const _Catalog({
    required this.snapshot,
    required this.selectedId,
    required this.onSelect,
    required this.maxColumns,
  });
  final WardrobeSnapshot snapshot;
  final String? selectedId;
  final ValueChanged<WardrobeTheme> onSelect;

  /// Three on a phone (guide 7.6 2); a wide pane may fit more.
  final int maxColumns;

  /// Narrowest readable tile; Pen 'Wardrobe/Shop Tile' (ERSyr) is 112.
  static const minTileWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final themes = snapshot.themes;
    final owned = themes.where((t) => t.owned).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text('배경', style: Theme.of(context).textTheme.titleLarge),
            ),
            Text(
              '${themes.length}종 · 보유 $owned종',
              key: const ValueKey('wardrobe_theme_counts'),
              style: meetingType(13, 18, FontWeight.w700, MeetingColors.muted),
            ),
          ],
        ),
        if (fixtureLabelsVisible && snapshot.fixtureLabel != null) ...[
          const SizedBox(height: Space.s2),
          FixtureBadge(snapshot.fixtureLabel!),
        ],
        const SizedBox(height: Space.s3),
        if (themes.isEmpty)
          const ProductPanel(
            color: MeetingColors.pressed,
            child: Text('지금 고를 수 있는 배경이 없어요.'),
          )
        else
          LayoutBuilder(
            builder: (context, bounds) {
              const gap = Space.s2;
              final columns = ((bounds.maxWidth + gap) / (minTileWidth + gap))
                  .floor()
                  .clamp(1, maxColumns);
              return Column(
                spacing: gap,
                children: [
                  for (var row = 0; row < themes.length; row += columns)
                    // Tiles of a row share the tallest one's height.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: gap,
                        children: [
                          for (var i = row; i < row + columns; i++)
                            Expanded(
                              child: i < themes.length
                                  ? _ThemeTile(
                                      theme: themes[i],
                                      selected: themes[i].id == selectedId,
                                      equipped:
                                          themes[i].id ==
                                          snapshot.equippedThemeId,
                                      onTap: () => onSelect(themes[i]),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Pen 'Wardrobe/Shop Tile' (ERSyr): the theme's own surface, its name and
/// its price or ownership. Selection draws the strong outline; the worn
/// badge marks what the server applied. They are separate states.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.selected,
    required this.equipped,
    required this.onTap,
  });
  final WardrobeTheme theme;
  final bool selected;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = meetingType(12.5, 16, FontWeight.w700, MeetingColors.muted);
    final statusKey = ValueKey('wardrobe_theme_status_${theme.id}');
    final price = theme.price;
    final Widget status = theme.owned
        ? Text('보유', key: statusKey, style: meta)
        : price == null
        ? Text('가격 확인 전', key: statusKey, style: meta)
        : Row(
            spacing: Space.s1,
            children: [
              const PixelIcon('points', size: 14),
              Flexible(
                child: Text(
                  '${formatCount(price)}P',
                  key: statusKey,
                  style: meta,
                ),
              ),
            ],
          );
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          key: ValueKey('wardrobe_tile_${theme.id}'),
          color: selected ? MeetingColors.well : ProductColors.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: selected
                ? const BorderSide(color: MeetingColors.primaryStrong, width: 2)
                : const BorderSide(color: MeetingColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('wardrobe_theme_${theme.id}'),
            onTap: onTap,
            child: Padding(
              // Pen ERSyr literals: 6 around the picture, 10 below the text.
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 1.2,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ThemeSurface(theme, keyPrefix: 'wardrobe_tile'),
                          if (equipped)
                            Positioned(
                              left: 6,
                              top: 6,
                              child: Container(
                                key: ValueKey(
                                  'wardrobe_theme_equipped_${theme.id}',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: const BoxDecoration(
                                  color: ProductColors.record,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(999),
                                  ),
                                ),
                                child: Text(
                                  '착용 중',
                                  style: meetingType(
                                    10.5,
                                    14,
                                    FontWeight.w800,
                                    ProductColors.raised,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          theme.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: meetingType(13.5, 18, FontWeight.w700),
                        ),
                        status,
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
}

/// Pen 'V2 · WARD-02' (XmVOx) in the app's shared dialog theme (style 40).
class _SpendDialog extends StatelessWidget {
  const _SpendDialog({
    required this.title,
    required this.note,
    required this.price,
    required this.balance,
    required this.thumbnail,
  });
  final String title;
  final String note;
  final int price;

  /// Null when the server balance is unknown: no estimate is drawn and none
  /// is made up from 0. The server's answer is the balance that counts.
  final int? balance;
  final Widget thumbnail;

  static const _unknown = '보유 포인트를 아직 확인하지 못했어요. 부족하면 사지 않고 알려 드려요.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).dialogTheme;
    final points = balance;
    final amount = meetingType(15, 20, FontWeight.w700, MeetingColors.muted);
    Text centered(String text, Key key, TextStyle? style) => Text(
      wrapByWords(text),
      key: key,
      semanticsLabel: text,
      textAlign: TextAlign.center,
      style: style,
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Space.s8,
        vertical: Space.s6,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s3,
            children: [
              Center(
                // Pen 'Purchase Thumb': 132 x 96, the line drawn over the
                // picture's edge.
                child: Container(
                  key: const ValueKey('wardrobe_purchase_thumb'),
                  width: 132,
                  height: 96,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    border: Border.all(color: MeetingColors.line),
                  ),
                  child: thumbnail,
                ),
              ),
              centered(
                title,
                const ValueKey('wardrobe_purchase_title'),
                theme.titleTextStyle,
              ),
              if (points == null)
                centered(
                  _unknown,
                  const ValueKey('wardrobe_purchase_balance_unknown'),
                  theme.contentTextStyle,
                )
              else
                Center(
                  child: Semantics(
                    container: true,
                    label:
                        '구매 전 ${formatCount(points)}P, '
                        '구매 후 예상 ${formatCount(points - price)}P',
                    excludeSemantics: true,
                    child: Container(
                      key: const ValueKey('wardrobe_purchase_balance'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s4,
                        vertical: Space.s2,
                      ),
                      decoration: const BoxDecoration(
                        color: MeetingColors.soft,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.s2,
                        children: [
                          const PixelIcon('points', size: 20),
                          Text(
                            '${formatCount(points)}P',
                            key: const ValueKey('wardrobe_purchase_before'),
                            style: amount,
                          ),
                          Text('→', style: amount),
                          Text(
                            '${formatCount(points - price)}P',
                            key: const ValueKey('wardrobe_purchase_after'),
                            style: meetingType(15, 20, FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              centered(
                note,
                const ValueKey('wardrobe_purchase_note'),
                theme.contentTextStyle,
              ),
              Padding(
                padding: const EdgeInsets.only(top: Space.s1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s2,
                  children: [
                    FilledButton(
                      key: const ValueKey('wardrobe_purchase_confirm'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('${formatCount(price)}P로 사기'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('wardrobe_purchase_cancel'),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.theme,
    required this.equippedId,
    required this.balance,
    required this.busy,
    required this.error,
    required this.insufficient,
    required this.onPurchase,
    required this.onEquip,
    required this.onEarnPoints,
  });
  final WardrobeTheme? theme;
  final String? equippedId;
  final int? balance;
  final bool busy;
  final String? error;
  final bool insufficient;
  final ValueChanged<WardrobeTheme> onPurchase;
  final ValueChanged<WardrobeTheme> onEquip;
  final VoidCallback onEarnPoints;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final text = Theme.of(context).textTheme;
    if (t == null) {
      return const ProductPanel(child: Text('배경을 골라 미리 볼 수 있어요.'));
    }
    final isEquipped = t.id == equippedId;
    final short =
        !t.owned && t.price != null && balance != null && t.price! > balance!;
    final (String caption, String label, VoidCallback? onPressed) = isEquipped
        ? ('적용 완료 · 홈에 반영돼요', '착용 중', null)
        : t.owned
        ? ('구매 완료 · 아직 적용 전', '착용하기', () => onEquip(t))
        : t.price == null
        ? ('가격이 아직 확정되지 않았어요', '구매하기', null)
        : short || insufficient
        ? ('포인트가 부족해요', '구매하기', null)
        : ('미리보기만 선택됨', '구매하기', () => onPurchase(t));
    final button = FilledButton(
      key: const ValueKey('wardrobe_action'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(132, 48),
        backgroundColor: isEquipped ? ProductColors.record : null,
        disabledBackgroundColor: isEquipped ? ProductColors.record : null,
        disabledForegroundColor: isEquipped ? ProductColors.raised : null,
      ),
      onPressed: busy ? null : onPressed,
      child: Text(busy ? '처리 중…' : label),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.name, style: text.titleMedium),
        Text(caption, key: const ValueKey('wardrobe_action_caption')),
      ],
    );
    return ProductPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, bounds) =>
                bounds.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.5
                ? Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: Space.s3),
                      button,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      info,
                      const SizedBox(height: Space.s2),
                      button,
                    ],
                  ),
          ),
          if (error != null) ...[
            const SizedBox(height: Space.s2),
            Text(
              error!,
              key: const ValueKey('wardrobe_error'),
              style: const TextStyle(color: ProductColors.error),
            ),
          ],
          if ((short || insufficient) && !t.owned)
            TextButton(
              key: const ValueKey('wardrobe_earn_points'),
              onPressed: onEarnPoints,
              child: const Text('홈에서 걸음 포인트 받기'),
            ),
        ],
      ),
    );
  }
}
