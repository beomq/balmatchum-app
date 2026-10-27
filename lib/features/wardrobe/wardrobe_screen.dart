import 'dart:async';

import 'package:flutter/material.dart';

import '../first_meeting/meeting_theme.dart';
import '../records/product_page.dart';
import 'wardrobe_models.dart';

enum WardrobeScope { owned, store }

/// Background theme wardrobe. Selecting a tile only previews; purchase and
/// equip are separate, server-confirmed actions. Only themes are offered:
/// no fitted accessory composites are produced for the supplied dog.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    required this.dogAsset,
    required this.loadWardrobe,
    required this.purchaseTheme,
    required this.equipTheme,
    required this.onBack,
    required this.onHome,
    super.key,
  });

  /// The selected companion's approved sprite path.
  final String dogAsset;
  final LoadWardrobe loadWardrobe;
  final WardrobeThemeAction purchaseTheme;
  final WardrobeThemeAction equipTheme;
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
  WardrobeScope scope = WardrobeScope.owned;
  bool busy = false;
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

  Future<void> run(WardrobeThemeAction action, WardrobeTheme theme) async {
    setState(() {
      busy = true;
      actionError = null;
      insufficient = false;
    });
    try {
      final value = await action(theme);
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
          WardrobeFailureReason.unavailable => '지금은 이 배경을 사용할 수 없어요.',
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

  Future<void> confirmPurchase(WardrobeTheme theme) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${theme.name} 배경을 구매할까요?'),
        content: Text(
          '${formatCount(theme.price!)}포인트가 사용돼요. 구매 후 착용은 따로 선택해요.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('wardrobe_purchase_cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const ValueKey('wardrobe_purchase_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('구매 확인'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await run(widget.purchaseTheme, theme);
  }

  void select(WardrobeTheme theme) => setState(() {
    selectedId = theme.id;
    actionError = null;
    insufficient = false;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
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
            child: ProductTopBar(onBack: widget.onBack, onHome: widget.onHome),
          );
          if (s == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: ProductLoadState(error: loadError, onRetry: load),
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
            dogAsset: widget.dogAsset,
            theme: selected,
            equipped: selected != null && selected!.id == s.equippedThemeId,
            compact: !split && bounds.maxHeight < 600,
          );
          final list = _Catalog(
            snapshot: s,
            scope: scope,
            selectedId: selectedId,
            onScope: (v) => setState(() => scope = v),
            onSelect: select,
            narrow: !split,
            wide: w >= 840,
          );
          final action = _ActionBar(
            theme: selected,
            equippedId: s.equippedThemeId,
            balance: s.balance,
            busy: busy,
            error: actionError,
            insufficient: insufficient,
            onPurchase: confirmPurchase,
            onEquip: (t) => run(widget.equipTheme, t),
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
                    Expanded(child: SingleChildScrollView(child: list)),
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
                      padding: EdgeInsets.fromLTRB(gutter, Space.s3, gutter, 0),
                      child:
                          body ??
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                preview,
                                const SizedBox(height: Space.s3),
                                list,
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
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.dogAsset,
    required this.theme,
    required this.equipped,
    required this.compact,
  });
  final String dogAsset;
  final WardrobeTheme? theme;
  final bool equipped;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final caption = t == null
        ? '배경 없음'
        : equipped
        ? '실제 적용 상태'
        : t.owned
        ? '보유함 · 실제 적용 전'
        : '미리보기 · 실제 적용 전';
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: compact ? 140 : 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (t?.backgroundAsset != null)
              Image.asset(
                t!.backgroundAsset!,
                key: ValueKey('wardrobe_preview_bg_${t.id}'),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
              )
            else
              ColoredBox(
                key: ValueKey('wardrobe_preview_color_${t?.id}'),
                color: t == null ? MeetingColors.soft : Color(t.colorValue),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s8,
                Space.s8 + Space.s2,
                Space.s8,
                Space.s2,
              ),
              child: Image.asset(
                dogAsset,
                key: const ValueKey('wardrobe_preview_dog'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              ),
            ),
            Positioned(
              left: Space.s3,
              top: Space.s3,
              right: Space.s3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s3,
                    vertical: Space.s1,
                  ),
                  decoration: BoxDecoration(
                    color: ProductColors.raised,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    caption,
                    key: const ValueKey('wardrobe_preview_caption'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: MeetingColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  const _Catalog({
    required this.snapshot,
    required this.scope,
    required this.selectedId,
    required this.onScope,
    required this.onSelect,
    required this.narrow,
    required this.wide,
  });
  final WardrobeSnapshot snapshot;
  final WardrobeScope scope;
  final String? selectedId;
  final ValueChanged<WardrobeScope> onScope;
  final ValueChanged<WardrobeTheme> onSelect;
  final bool narrow;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final t in snapshot.themes)
        if ((scope == WardrobeScope.owned) == t.owned) t,
    ];
    final balance = snapshot.balance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s3,
          children: [
            Text('배경', style: Theme.of(context).textTheme.titleLarge),
            Text(
              balance == null ? '포인트 확인 전' : '보유 ${formatCount(balance)}포인트',
              key: const ValueKey('wardrobe_balance'),
            ),
          ],
        ),
        if (snapshot.fixtureLabel != null) ...[
          const SizedBox(height: Space.s2),
          FixtureBadge(snapshot.fixtureLabel!),
        ],
        const SizedBox(height: Space.s2),
        SegmentedButton<WardrobeScope>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: WardrobeScope.owned,
              label: Text('보유함', key: ValueKey('wardrobe_scope_owned')),
            ),
            ButtonSegment(
              value: WardrobeScope.store,
              label: Text('상점', key: ValueKey('wardrobe_scope_store')),
            ),
          ],
          selected: {scope},
          onSelectionChanged: (v) => onScope(v.single),
          style: SegmentedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            selectedBackgroundColor: MeetingColors.soft,
            foregroundColor: MeetingColors.ink,
          ),
        ),
        const SizedBox(height: Space.s3),
        if (items.isEmpty)
          ProductPanel(
            color: MeetingColors.pressed,
            child: Text(
              scope == WardrobeScope.owned
                  ? '아직 보유한 배경이 없어요. 상점에서 둘러보세요.'
                  : '지금 상점에 새 배경이 없어요.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, bounds) {
              final gap = narrow ? Space.s2 : Space.s3;
              final min = narrow
                  ? 136.0
                  : wide
                  ? 240.0
                  : 144.0;
              final cols = ((bounds.maxWidth + gap) / (min + gap))
                  .floor()
                  .clamp(1, wide ? 3 : 2);
              final width = (bounds.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in items)
                    SizedBox(
                      width: width,
                      child: _ThemeTile(
                        theme: t,
                        selected: t.id == selectedId,
                        equipped: t.id == snapshot.equippedThemeId,
                        onTap: () => onSelect(t),
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
    final status = [
      theme.owned
          ? (equipped ? '보유 · 착용 중' : '보유')
          : theme.price == null
          ? '미보유 · 가격 확인 전'
          : '미보유 · ${formatCount(theme.price!)}포인트',
      if (selected) '선택됨',
    ].join(' · ');
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? MeetingColors.soft : ProductColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? MeetingColors.primary : MeetingColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('wardrobe_theme_${theme.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: theme.backgroundAsset == null
                        ? ColoredBox(color: Color(theme.colorValue))
                        : Image.asset(
                            theme.backgroundAsset!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.none,
                          ),
                  ),
                ),
                const SizedBox(height: Space.s2),
                Text(
                  theme.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Space.s1),
                Text(status, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
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
