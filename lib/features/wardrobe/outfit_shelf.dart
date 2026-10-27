import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';
import 'wardrobe_models.dart';

/// The outfit shelf on the wardrobe screen: one card per server outfit with
/// its purchase, wear or removal action. Whether the drawn sprite can wear an
/// outfit comes from [WardrobeOutfit.layerFor], never from the card alone.
class OutfitShelf extends StatelessWidget {
  const OutfitShelf({
    required this.outfits,
    required this.breedId,
    required this.balance,
    required this.busy,
    required this.error,
    required this.insufficient,
    required this.onChange,
    required this.onReload,
    required this.onEarnPoints,
    super.key,
  });

  /// Null when the server outfit state could not be confirmed.
  final WardrobeOutfits? outfits;

  /// The drawn sprite's breed; only its own layer may be worn.
  final String breedId;
  final int? balance;
  final bool busy;
  final String? error;
  final bool insufficient;
  final void Function(WardrobeOutfit outfit, OutfitChange change) onChange;
  final VoidCallback onReload;
  final VoidCallback onEarnPoints;

  @override
  Widget build(BuildContext context) {
    final o = outfits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('의상', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.s2),
        if (o == null)
          ProductPanel(
            color: ProductColors.warningSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '의상 정보를 확인하지 못했어요.',
                  key: ValueKey('wardrobe_outfits_unknown'),
                ),
                const SizedBox(height: Space.s2),
                OutlinedButton(
                  key: const ValueKey('wardrobe_outfits_reload'),
                  onPressed: onReload,
                  child: const Text('다시 불러오기'),
                ),
              ],
            ),
          )
        else if (o.items.isEmpty)
          const ProductPanel(
            color: MeetingColors.pressed,
            child: Text('지금 입을 수 있는 의상이 없어요.'),
          )
        else
          for (final (i, item) in o.items.indexed) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            card(context, item, worn: item.id == o.equippedId),
          ],
      ],
    );
  }

  Widget card(BuildContext context, WardrobeOutfit item, {required bool worn}) {
    final text = Theme.of(context).textTheme;
    final wearable = item.layerFor(breedId) != null;
    final short = !item.owned && balance != null && item.price > balance!;
    final status = item.owned
        ? (worn ? '보유 · 착용 중' : '보유')
        : '미보유 · ${formatCount(item.price)}포인트';
    final (String label, VoidCallback? onPressed) = !wearable
        ? (item.owned ? '입히기' : '구매하기', null)
        : worn
        ? ('벗기기', () => onChange(item, OutfitChange.remove))
        : item.owned
        ? ('입히기', () => onChange(item, OutfitChange.wear))
        : short || insufficient
        ? ('구매하기', null)
        : ('구매하기', () => onChange(item, OutfitChange.purchase));
    final key = ValueKey('wardrobe_outfit_action_${item.id}');
    final child = Text(busy ? '처리 중…' : label);
    const size = Size(132, 48);
    final button = worn && wearable
        ? OutlinedButton(
            key: key,
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: busy ? null : onPressed,
            child: child,
          )
        : FilledButton(
            key: key,
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: busy ? null : onPressed,
            child: child,
          );
    final info = Row(
      children: [
        Image.asset(
          'assets/first_meeting/icons/wardrobe.png',
          width: 32,
          height: 32,
          filterQuality: FilterQuality.none,
        ),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: text.titleMedium),
              Text(
                status,
                key: ValueKey('wardrobe_outfit_status_${item.id}'),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
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
          if (!wearable) ...[
            const SizedBox(height: Space.s2),
            Text(
              '이 강아지는 아직 입을 수 없어요',
              key: const ValueKey('wardrobe_outfit_unsupported'),
              style: text.bodyMedium?.copyWith(color: MeetingColors.ink),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: Space.s2),
            Text(
              error!,
              key: const ValueKey('wardrobe_outfit_error'),
              style: const TextStyle(color: ProductColors.error),
            ),
          ],
          if (wearable && !item.owned && (short || insufficient))
            TextButton(
              key: const ValueKey('wardrobe_outfit_earn_points'),
              onPressed: onEarnPoints,
              child: const Text('홈에서 걸음 포인트 받기'),
            ),
        ],
      ),
    );
  }
}
