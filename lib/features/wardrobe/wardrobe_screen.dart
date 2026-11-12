import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart' as api;
import 'package:flutter/material.dart';

import '../../app/duo_rail.dart';
import '../first_meeting/domain/dog_catalog.dart';
import '../first_meeting/meeting_theme.dart';
import '../first_meeting/onboarding_widgets.dart' show wrapByWords;
import '../records/product_page.dart';
import '../records/status_widgets.dart';
import 'dog_sprite.dart';
import 'set_effect.dart';
import 'wardrobe_art.dart';
import 'wardrobe_models.dart';

/// Gift months are KST calendar months; show their dates in KST too.
DateTime _kst(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

/// Set band and set-only accents (DESIGN.md set-display mock).
const _setRed = Color(0xFFD9483B);
const _setRedSoft = Color(0xFFFBE4E0);
const _giftGreen = Color(0xFF2E7D55);

enum _Tab { sets, items, backgrounds }

/// The wardrobe: sets, items by colour and backgrounds. Everyone can try
/// anything on locally; only server-confirmed purchases and wear change what
/// the companion wears. The set band and effect show only when the server
/// (or, while trying on, the same rule) says the set is complete.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    required this.dog,
    required this.loadWardrobe,
    required this.runAction,
    required this.onBack,
    required this.onHome,
    this.onSubscribe,
    this.cachedStore,
    super.key,
  });

  final DogBreed dog;
  final LoadWardrobe loadWardrobe;
  final RunWardrobeAction runAction;
  final VoidCallback onBack;

  /// Also used by the insufficient-points path to reach today's reward.
  final VoidCallback onHome;

  /// Opens the subscription page for a season set; null hides the button.
  final VoidCallback? onSubscribe;

  /// The last known wardrobe, shown while [loadWardrobe] runs.
  final api.WardrobeStore? cachedStore;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  api.WardrobeStore? store;
  String? loadError;
  bool busy = false;
  String? actionError;
  bool insufficient = false;
  _Tab tab = _Tab.sets;

  /// Local try-on: slot -> worn, and a background. Null = what is worn.
  Map<String, Worn>? trial;
  String? trialBackground;

  /// Chosen colour per set or item card.
  final colours = <String, String>{};

  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// A try-on is seen in the preview at the top, wherever it was asked for.
  void _showPreview() {
    if (scroll.hasClients && scroll.offset > 0) {
      unawaited(
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(load(cached: widget.cachedStore));
  }

  Future<void> load({api.WardrobeStore? cached}) async {
    setState(() {
      store = cached;
      busy = cached != null;
      loadError = null;
    });
    try {
      final value = await widget.loadWardrobe();
      if (!mounted) return;
      setState(() {
        store = value;
        busy = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        store = null;
        busy = false;
        loadError = '꾸미기 정보를 불러오지 못했어요.';
      });
    }
  }

  Future<void> run(WardrobeAction action) async {
    setState(() {
      busy = true;
      actionError = null;
      insufficient = false;
    });
    try {
      final value = await widget.runAction(action);
      if (!mounted) return;
      setState(() {
        store = value;
        busy = false;
        trial = null;
        trialBackground = null;
      });
    } on WardrobeActionException catch (e) {
      if (!mounted) return;
      _showPreview();
      setState(() {
        busy = false;
        insufficient = e.reason == WardrobeFailureReason.insufficientPoints;
        actionError = switch (e.reason) {
          WardrobeFailureReason.insufficientPoints => '포인트가 부족해요.',
          WardrobeFailureReason.incompatible => '이 강아지는 아직 입을 수 없어요.',
          WardrobeFailureReason.subscriptionRequired => '구독하면 받을 수 있는 선물이에요.',
          WardrobeFailureReason.unavailable => '지금은 할 수 없어요. 다시 불러와 주세요.',
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
          store = value;
          busy = false;
          actionError = '응답을 받지 못해 서버의 현재 상태를 다시 불러왔어요.';
        });
      } on Exception {
        if (!mounted) return;
        setState(() {
          store = null;
          busy = false;
          loadError = '처리 결과를 확인하지 못했어요. 다시 불러와 주세요.';
        });
      }
    }
  }

  String get breed => widget.dog.id;

  Map<String, Worn> wornNow(api.WardrobeStore s) => {
    for (final e in s.equipped) e.slot: Worn(e.itemId, e.colourId),
  };

  Map<String, Worn> shown(api.WardrobeStore s) => trial ?? wornNow(s);
  String shownBackground(api.WardrobeStore s) =>
      trialBackground ?? s.equippedBackground;
  bool get trying => trial != null || trialBackground != null;

  void tryItem(api.WardrobeItemView item, String colour) => setState(() {
    final base = Map.of(trial ?? wornNow(store!));
    base[item.slot] = Worn(item.itemId, colour);
    trial = base;
    _showPreview();
  });

  void trySet(api.WardrobeSetView set, String colour) => setState(() {
    final s = store!;
    final base = Map.of(trial ?? wornNow(s));
    for (final id in set.itemIds) {
      final slot = s.item(id)?.slot;
      if (slot != null) base[slot] = Worn(id, colour);
    }
    trial = base;
    trialBackground = set.backgroundId;
    _showPreview();
  });

  void tryBackground(String id) => setState(() {
    trialBackground = id;
    _showPreview();
  });

  void resetTrial() => setState(() {
    trial = null;
    trialBackground = null;
  });

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
          balance: store?.balance,
          thumbnail: thumbnail,
        ),
      ) ==
      true;

  Widget dogOn(String background, Map<String, Worn> worn, {Key? key}) =>
      ColoredBox(
        key: key,
        color: MeetingColors.stage,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Background(background),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s4,
                Space.s4,
                Space.s1,
              ),
              child: DogSprite(
                asset: dogAsset(breed),
                look: lookFor(breed, worn.values),
              ),
            ),
          ],
        ),
      );

  Future<void> buySet(api.WardrobeSetView set, String colour) async {
    final s = store!;
    final c = set.colours.firstWhere((x) => x.colourId == colour);
    final worn = Map.of(wornNow(s));
    for (final id in set.itemIds) {
      final slot = s.item(id)?.slot;
      if (slot != null) worn[slot] = Worn(id, colour);
    }
    final ok = await confirmSpend(
      title: '${set.name}(${s.colourName(colour)})를 살까요?',
      note: c.missingParts < set.itemIds.length + 1
          ? '이미 가진 것은 빼고 계산했어요. 산 뒤 \'세트로 입히기\'로 한 번에 입혀요.'
          : '산 아이템은 따로따로 입고 벗을 수 있어요.',
      price: c.price,
      thumbnail: dogOn(set.backgroundId, worn),
    );
    if (ok && mounted) {
      await run(WardrobeAction(WardrobeActionKind.buySet, set.setId, colour));
    }
  }

  Future<void> buyItem(api.WardrobeItemView item, String colour) async {
    final s = store!;
    final worn = Map.of(wornNow(s))..[item.slot] = Worn(item.itemId, colour);
    final ok = await confirmSpend(
      title: '${item.name}(${s.colourName(colour)})을 살까요?',
      note: '다른 색은 따로 사요. 산 뒤 언제든 입히고 벗길 수 있어요.',
      price: item.price,
      thumbnail: dogOn(s.equippedBackground, worn),
    );
    if (ok && mounted) {
      await run(
        WardrobeAction(WardrobeActionKind.buyItem, item.itemId, colour),
      );
    }
  }

  Future<void> buyBackground(api.WardrobeBackgroundView bg) async {
    final ok = await confirmSpend(
      title: '${bg.name} 배경을 살까요?',
      note: '산 배경은 꾸미기에서 언제든 바꿀 수 있어요.',
      price: bg.price,
      thumbnail: _Background(bg.backgroundId),
    );
    if (ok && mounted) {
      await run(
        WardrobeAction(WardrobeActionKind.buyBackground, bg.backgroundId),
      );
    }
  }

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
            bottom: false,
            child: LayoutBuilder(
              builder: (context, bounds) {
                final inset = MediaQuery.paddingOf(context).bottom;
                final gutter = pageGutter(bounds.maxWidth);
                final header = Padding(
                  padding: EdgeInsets.fromLTRB(gutter, Space.s2, gutter, 0),
                  child: mode == null
                      ? ProductTopBar(
                          onBack: widget.onBack,
                          onHome: widget.onHome,
                          title: '꾸미기',
                        )
                      : const SizedBox(
                          height: 48,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ProductTitle('꾸미기'),
                          ),
                        ),
                );
                final s = store;
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: ListView(
                            key: const ValueKey('wardrobe_scroll'),
                            controller: scroll,
                            padding: EdgeInsets.fromLTRB(
                              gutter,
                              Space.s3,
                              gutter,
                              Space.s6 + inset,
                            ),
                            children: [
                              _preview(s),
                              if (actionError != null) ...[
                                const SizedBox(height: Space.s2),
                                Text(
                                  actionError!,
                                  key: const ValueKey('wardrobe_error'),
                                  style: meetingType(
                                    14,
                                    20,
                                    FontWeight.w700,
                                    ProductColors.error,
                                  ),
                                ),
                                if (insufficient)
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton(
                                      key: const ValueKey(
                                        'wardrobe_earn_points',
                                      ),
                                      onPressed: widget.onHome,
                                      child: const Text('홈에서 걸음 포인트 받기'),
                                    ),
                                  ),
                              ],
                              const SizedBox(height: Space.s3),
                              _progress(s),
                              _WornList(
                                store: s,
                                busy: busy,
                                onTakeOff: (slot) => run(
                                  WardrobeAction(
                                    WardrobeActionKind.takeOffSlot,
                                    slot,
                                  ),
                                ),
                                onTakeOffSet: (set) => run(
                                  WardrobeAction(
                                    WardrobeActionKind.takeOffSet,
                                    set,
                                  ),
                                ),
                              ),
                              const SizedBox(height: Space.s4),
                              _Tabs(
                                tab: tab,
                                onTab: (t) => setState(() => tab = t),
                              ),
                              const SizedBox(height: Space.s3),
                              ...switch (tab) {
                                _Tab.sets => _sets(s),
                                _Tab.items => _items(s),
                                _Tab.backgrounds => _backgrounds(s),
                              },
                            ],
                          ),
                        ),
                      ),
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

  Widget _preview(api.WardrobeStore s) {
    final worn = shown(s);
    final background = shownBackground(s);
    final complete = trying
        ? completedBy(s, worn, background)
        : (s.completeSetId == null
              ? null
              : (s.set(s.completeSetId!)!, s.completeColour!));
    final amount = '${formatCount(s.balance)}P';
    return ClipRRect(
      key: const ValueKey('wardrobe_preview'),
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Background(background),
            if (complete != null) SetEffect(preset: complete.$1.effect),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s8 + Space.s4,
                Space.s8 + Space.s2,
                Space.s8 + Space.s4,
                Space.s2,
              ),
              child: DogSprite(
                asset: dogAsset(breed),
                look: lookFor(breed, worn.values),
                spriteKey: const ValueKey('wardrobe_preview_dog'),
                layerKey: const ValueKey('wardrobe_preview_layers'),
              ),
            ),
            Positioned(
              left: Space.s3,
              top: Space.s3,
              right: Space.s3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: Space.s2,
                      runSpacing: Space.s1,
                      children: [
                        if (complete != null)
                          _Band(
                            '${complete.$1.name} 완성',
                            key: const ValueKey('wardrobe_set_complete'),
                          ),
                        if (trying)
                          _Tag(
                            '입어 보는 중',
                            key: const ValueKey('wardrobe_trying'),
                          ),
                      ],
                    ),
                  ),
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
            if (trying)
              Positioned(
                right: Space.s3,
                bottom: Space.s3,
                child: FilledButton.tonal(
                  key: const ValueKey('wardrobe_trial_reset'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: resetTrial,
                  child: const Text('입은 옷으로 돌아가기'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// "One left" hint for the set the companion is closest to (mock 3).
  Widget _progress(api.WardrobeStore s) {
    if (trying || s.completeSetId != null) return const SizedBox.shrink();
    final worn = wornNow(s);
    api.WardrobeSetView? best;
    var bestCount = 0;
    var bestColour = '';
    for (final set in s.sets) {
      final counts = <String, int>{};
      for (final id in set.itemIds) {
        final slot = s.item(id)?.slot;
        final w = slot == null ? null : worn[slot];
        if (w != null && w.itemId == id) {
          counts[w.colourId] = (counts[w.colourId] ?? 0) + 1;
        }
      }
      for (final MapEntry(:key, :value) in counts.entries) {
        if (value > bestCount) {
          best = set;
          bestCount = value;
          bestColour = key;
        }
      }
    }
    final set = best;
    if (set == null) return const SizedBox.shrink();
    final missingItems = [
      for (final id in set.itemIds)
        if (worn[s.item(id)!.slot] != Worn(id, bestColour)) id,
    ];
    final backgroundOff = s.equippedBackground != set.backgroundId;
    final missing = missingItems.length + (backgroundOff ? 1 : 0);
    final colour = s.colourName(bestColour);
    final String detail;
    if (missingItems.isEmpty) {
      detail =
          '옷은 세트 완성! ${s.background(set.backgroundId)?.name ?? '세트'} 배경을 '
          '고르면 효과가 나와요.';
    } else {
      final names = missingItems.map((id) => s.item(id)!.name).join(', ');
      detail = '$names을(를) $colour(으)로 입으면 세트가 완성돼요.';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Container(
        key: const ValueKey('wardrobe_set_progress'),
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(
          color: MeetingColors.warningSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9C46A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(
              '${set.name}까지 $missing개 남았어요.',
              style: meetingType(
                14,
                20,
                FontWeight.w800,
                ProductColors.attention,
              ),
            ),
            Text(detail, style: meetingType(13, 18, FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  List<Widget> _sets(api.WardrobeStore s) => [
    if (s.sets.isEmpty) const ProductPanel(child: Text('지금 고를 수 있는 세트가 없어요.')),
    for (final set in s.sets)
      Padding(
        padding: const EdgeInsets.only(bottom: Space.s4),
        child: _setCard(s, set),
      ),
  ];

  Widget _setCard(api.WardrobeStore s, api.WardrobeSetView set) {
    final colour = colours[set.setId] ?? set.colours.first.colourId;
    final c = set.colours.firstWhere((x) => x.colourId == colour);
    final season = set.season;
    final owned = c.missingParts == 0;
    final complete = s.completeSetId == set.setId && s.completeColour == colour;
    final worn = Map.of(wornNow(s));
    for (final id in set.itemIds) {
      final slot = s.item(id)?.slot;
      if (slot != null) worn[slot] = Worn(id, colour);
    }
    final gift = season != null && season.open && !season.granted;
    final (String label, VoidCallback? action) = !c.wearable
        ? ('곧 입을 수 있어요', null)
        : gift && !s.subscriber && !set.sellable
        ? ('구독하고 받기', widget.onSubscribe)
        : gift && s.subscriber
        ? (
            '선물 받기',
            () => run(
              WardrobeAction(WardrobeActionKind.buySet, set.setId, colour),
            ),
          )
        : owned && complete
        ? (
            '세트 한 번에 벗기기',
            () => run(WardrobeAction(WardrobeActionKind.takeOffSet, set.setId)),
          )
        : owned
        ? (
            '세트로 입히기',
            () => run(
              WardrobeAction(WardrobeActionKind.wearSet, set.setId, colour),
            ),
          )
        : c.purchasable
        ? (
            '${set.name} 사기 · ${formatCount(c.price)}P',
            () => buySet(set, colour),
          )
        : ('지금은 살 수 없어요', null);
    final end = season == null || !season.open
        ? null
        : '${_kst(season.endsAt).month}월 선물 · '
              '${_kst(season.endsAt).day}일까지';
    return Container(
      key: ValueKey('wardrobe_set_${set.setId}'),
      decoration: BoxDecoration(
        color: ProductColors.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MeetingColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 3 / 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                dogOn(set.backgroundId, worn),
                if (c.wearable) SetEffect(preset: set.effect, still: true),
                Positioned(
                  left: Space.s3,
                  top: Space.s3,
                  child: _Band(
                    set.sellable ? 'SET · ${set.name}' : '구독자 선물 · ${set.name}',
                    color: set.sellable ? _setRed : _giftGreen,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s3,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        set.name,
                        style: meetingType(20, 26, FontWeight.w800),
                      ),
                    ),
                    if (end != null)
                      Text(
                        end,
                        key: ValueKey('wardrobe_set_end_${set.setId}'),
                        style: meetingType(13, 18, FontWeight.w700, _giftGreen),
                      ),
                  ],
                ),
                _ColourChips(
                  store: s,
                  colours: [for (final x in set.colours) x.colourId],
                  selected: colour,
                  keyPrefix: 'wardrobe_set_colour_${set.setId}',
                  onSelect: (id) => setState(() => colours[set.setId] = id),
                ),
                Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    for (final id in set.itemIds)
                      _Part(
                        s.item(id)?.name ?? id,
                        owned:
                            s.item(id)?.ownedColours.contains(colour) ?? false,
                      ),
                    _Part(
                      s.background(set.backgroundId)?.name ?? '배경',
                      owned: s.background(set.backgroundId)?.owned ?? false,
                    ),
                  ],
                ),
                if (set.sellable || (season?.resaleOpen ?? false))
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '따로 사면 ${formatCount(set.fullPrice)}P',
                              style:
                                  meetingType(
                                    12.5,
                                    16,
                                    FontWeight.w600,
                                    MeetingColors.muted,
                                  ).copyWith(
                                    decoration: TextDecoration.lineThrough,
                                  ),
                            ),
                            Text(
                              '세트 ${set.discountPct}% 할인'
                              '${c.missingParts < set.itemIds.length + 1 && !owned ? ' · 가진 것 빼고' : ''}',
                              style: meetingType(
                                12.5,
                                16,
                                FontWeight.w600,
                                MeetingColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        owned ? '모두 보유' : '${formatCount(c.price)}P',
                        key: ValueKey('wardrobe_set_price_${set.setId}'),
                        style: meetingType(24, 30, FontWeight.w800),
                      ),
                    ],
                  )
                else
                  Text(
                    season!.granted
                        ? '구독 선물로 모든 색을 받았어요.'
                        : s.subscriber && season.open
                        ? '이달의 구독 선물이에요. 받으면 모든 색이 내 것이 돼요.'
                        : '구독하면 모든 색을 선물로 받아요. 구독을 그만둬도 계속 입을 수 있어요.',
                    style: meetingType(
                      13,
                      18,
                      FontWeight.w600,
                      MeetingColors.muted,
                    ),
                  ),
                Row(
                  spacing: Space.s2,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(96, 44),
                      ),
                      key: ValueKey('wardrobe_set_try_${set.setId}'),
                      onPressed: c.wearable ? () => trySet(set, colour) : null,
                      child: const Text('입어 보기'),
                    ),
                    Expanded(
                      child: FilledButton(
                        key: ValueKey('wardrobe_set_action_${set.setId}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _setRed,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: busy ? null : action,
                        child: Text(busy ? '처리 중…' : label),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _items(api.WardrobeStore s) => [
    for (final slot in const ['head', 'torso', 'feet']) ...[
      Padding(
        padding: const EdgeInsets.only(bottom: Space.s2, top: Space.s1),
        child: Text(
          slotNames[slot]!,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      for (final item in s.items.where((i) => i.slot == slot))
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s3),
          child: _itemCard(s, item),
        ),
    ],
  ];

  Widget _itemCard(api.WardrobeStore s, api.WardrobeItemView item) {
    final colour =
        colours[item.itemId] ??
        (item.wearableColours.isNotEmpty
            ? item.wearableColours.first
            : item.colours.first);
    final wearable = item.wearableColours.contains(colour);
    final owned = item.ownedColours.contains(colour);
    final wearing = s.wornIn(item.slot);
    final isWorn =
        wearing != null &&
        wearing.itemId == item.itemId &&
        wearing.colourId == colour;
    final gift = item.gift;
    final giftOpen = gift != null && gift.open && !gift.granted && !owned;
    final (String label, VoidCallback? action) = !wearable
        ? ('곧 입을 수 있어요', null)
        : giftOpen && s.subscriber
        ? (
            '선물 받기',
            () => run(
              WardrobeAction(WardrobeActionKind.buyItem, item.itemId, colour),
            ),
          )
        : giftOpen && !item.sellable
        ? ('구독하고 받기', widget.onSubscribe)
        : isWorn
        ? (
            '벗기기',
            () =>
                run(WardrobeAction(WardrobeActionKind.takeOffSlot, item.slot)),
          )
        : owned
        ? (
            '입히기',
            () => run(
              WardrobeAction(WardrobeActionKind.wearItem, item.itemId, colour),
            ),
          )
        : !item.sellable
        ? ('세트로만 받아요', null)
        : ('${formatCount(item.price)}P 사기', () => buyItem(item, colour));
    return Container(
      key: ValueKey('wardrobe_item_${item.itemId}'),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: ProductColors.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWorn ? MeetingColors.primaryStrong : MeetingColors.line,
          width: isWorn ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s2,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: MeetingColors.stage,
                    child: DogSprite(
                      asset: dogAsset(breed),
                      look: wearable
                          ? lookFor(breed, [Worn(item.itemId, colour)])
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Wrap(
                      spacing: Space.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.name,
                          style: meetingType(16, 22, FontWeight.w800),
                        ),
                        for (final setId in item.setIds)
                          _SetMark(s.set(setId)?.name ?? setId),
                      ],
                    ),
                    Text(
                      owned
                          ? '${s.colourName(colour)} · 보유'
                          : '${s.colourName(colour)} · ${formatCount(item.price)}P',
                      key: ValueKey('wardrobe_item_status_${item.itemId}'),
                      style: meetingType(
                        13,
                        18,
                        FontWeight.w600,
                        MeetingColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _ColourChips(
            store: s,
            colours: item.colours,
            selected: colour,
            disabled: {
              for (final c in item.colours)
                if (!item.wearableColours.contains(c)) c,
            },
            keyPrefix: 'wardrobe_item_colour_${item.itemId}',
            onSelect: (id) => setState(() => colours[item.itemId] = id),
          ),
          Row(
            spacing: Space.s2,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 44),
                ),
                key: ValueKey('wardrobe_item_try_${item.itemId}'),
                onPressed: wearable ? () => tryItem(item, colour) : null,
                child: const Text('입어 보기'),
              ),
              Expanded(
                child: FilledButton(
                  key: ValueKey('wardrobe_item_action_${item.itemId}'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: busy ? null : action,
                  child: Text(label),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _backgrounds(api.WardrobeStore s) => [
    GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.s3,
      crossAxisSpacing: Space.s3,
      childAspectRatio: 0.78,
      children: [for (final bg in s.backgrounds) _backgroundTile(s, bg)],
    ),
  ];

  Widget _backgroundTile(api.WardrobeStore s, api.WardrobeBackgroundView bg) {
    final equipped = s.equippedBackground == bg.backgroundId;
    final (String label, VoidCallback? action) = equipped
        ? ('고른 배경', null)
        : bg.owned
        ? (
            '고르기',
            () => run(
              WardrobeAction(
                WardrobeActionKind.wearBackground,
                bg.backgroundId,
              ),
            ),
          )
        : bg.sellable
        ? ('${formatCount(bg.price)}P 사기', () => buyBackground(bg))
        : ('세트로만 받아요', null);
    return Container(
      key: ValueKey('wardrobe_background_${bg.backgroundId}'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: ProductColors.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: equipped ? MeetingColors.primaryStrong : MeetingColors.line,
          width: equipped ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s1,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => tryBackground(bg.backgroundId),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _Background(bg.backgroundId),
              ),
            ),
          ),
          Text(bg.name, style: meetingType(14, 19, FontWeight.w800)),
          if (bg.setId != null) _SetMark(s.set(bg.setId!)?.name ?? '세트'),
          FilledButton(
            key: ValueKey('wardrobe_background_action_${bg.backgroundId}'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              padding: EdgeInsets.zero,
              disabledBackgroundColor: MeetingColors.soft,
              disabledForegroundColor: MeetingColors.primaryStrong,
            ),
            onPressed: busy ? null : action,
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background(this.id);
  final String id;

  @override
  Widget build(BuildContext context) => switch (backgroundArt[id]) {
    final asset? => LayoutBuilder(
      builder: (context, constraints) => Image.asset(
        asset,
        key: ValueKey('wardrobe_bg_$id'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        cacheWidth: decodeWidth(
          constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    ),
    null => const ColoredBox(color: MeetingColors.soft),
  };
}

class _Band extends StatelessWidget {
  const _Band(this.text, {this.color = _setRed, super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(color: Color(0x33000000), offset: Offset(0, 2)),
      ],
    ),
    child: Text(
      text,
      style: meetingType(13, 17, FontWeight.w800, ProductColors.raised),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: const BoxDecoration(
      color: ProductColors.photoTag,
      borderRadius: BorderRadius.all(Radius.circular(999)),
    ),
    child: Text(text, style: meetingType(12.5, 16, FontWeight.w700)),
  );
}

class _SetMark extends StatelessWidget {
  const _SetMark(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: _setRedSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(name, style: meetingType(11.5, 15, FontWeight.w700, _setRed)),
  );
}

class _Part extends StatelessWidget {
  const _Part(this.name, {required this.owned});
  final String name;
  final bool owned;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: owned ? MeetingColors.green : MeetingColors.well,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: MeetingColors.line),
    ),
    child: Text(
      owned ? '$name · 보유' : name,
      style: meetingType(13, 18, FontWeight.w700),
    ),
  );
}

class _ColourChips extends StatelessWidget {
  const _ColourChips({
    required this.store,
    required this.colours,
    required this.selected,
    required this.keyPrefix,
    required this.onSelect,
    this.disabled = const {},
  });

  final api.WardrobeStore store;
  final List<String> colours;
  final String selected;
  final String keyPrefix;
  final ValueChanged<String> onSelect;
  final Set<String> disabled;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final id in colours)
        Semantics(
          button: true,
          selected: id == selected,
          label: store.colourName(id),
          child: GestureDetector(
            key: ValueKey('${keyPrefix}_$id'),
            onTap: () => onSelect(id),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: Space.s2),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: id == selected
                      ? MeetingColors.ink
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Opacity(
                opacity: disabled.contains(id) ? 0.35 : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(store.colour(id)?.swatch ?? 0xFF999999),
                  ),
                ),
              ),
            ),
          ),
        ),
      const SizedBox(width: Space.s1),
      Flexible(
        child: Text(
          store.colourName(selected),
          style: meetingType(13.5, 18, FontWeight.w700),
        ),
      ),
    ],
  );
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onTab});
  final _Tab tab;
  final ValueChanged<_Tab> onTab;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: MeetingColors.soft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (final (t, label) in const [
          (_Tab.sets, '세트'),
          (_Tab.items, '아이템'),
          (_Tab.backgrounds, '배경'),
        ])
          Expanded(
            child: Semantics(
              button: true,
              selected: t == tab,
              child: GestureDetector(
                key: ValueKey('wardrobe_tab_${t.name}'),
                onTap: () => onTab(t),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t == tab ? ProductColors.raised : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: meetingType(
                      15,
                      20,
                      t == tab ? FontWeight.w800 : FontWeight.w600,
                      t == tab ? MeetingColors.ink : MeetingColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// What is worn now, one row per slot (mock 2-3): a set mark, or "색 다름" when
/// another worn item of the same set has a different colour.
class _WornList extends StatelessWidget {
  const _WornList({
    required this.store,
    required this.busy,
    required this.onTakeOff,
    required this.onTakeOffSet,
  });

  final api.WardrobeStore store;
  final bool busy;
  final ValueChanged<String> onTakeOff;
  final ValueChanged<String> onTakeOffSet;

  @override
  Widget build(BuildContext context) {
    final s = store;
    if (s.equipped.isEmpty) {
      return Text(
        '아직 입은 옷이 없어요. 아래에서 입어 보고 골라 보세요.',
        key: const ValueKey('wardrobe_worn_empty'),
        style: meetingType(13.5, 19, FontWeight.w600, MeetingColors.muted),
      );
    }
    final rows = <Widget>[];
    for (final slot in const ['head', 'torso', 'feet']) {
      final e = s.wornIn(slot);
      if (e == null) continue;
      final item = s.item(e.itemId);
      String? mark;
      var off = false;
      for (final setId in item?.setIds ?? const <String>[]) {
        final set = s.set(setId)!;
        mark = set.name;
        for (final other in set.itemIds) {
          final w = s.wornIn(s.item(other)?.slot ?? '');
          if (w != null && w.itemId == other && w.colourId != e.colourId) {
            off = true;
          }
        }
      }
      rows.add(
        Container(
          key: ValueKey('wardrobe_worn_$slot'),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: Space.s2,
          ),
          decoration: BoxDecoration(
            color: ProductColors.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MeetingColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(s.colour(e.colourId)?.swatch ?? 0xFF999999),
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item?.name ?? e.itemId,
                      style: meetingType(15, 20, FontWeight.w800),
                    ),
                    Text(
                      '${slotNames[slot]} · ${s.colourName(e.colourId)}',
                      style: meetingType(
                        12.5,
                        16,
                        FontWeight.w600,
                        MeetingColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (off)
                Container(
                  key: ValueKey('wardrobe_worn_off_$slot'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: MeetingColors.pressed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '색 다름',
                    style: meetingType(
                      11.5,
                      15,
                      FontWeight.w700,
                      MeetingColors.muted,
                    ),
                  ),
                )
              else if (mark != null)
                _SetMark(mark),
              IconButton(
                key: ValueKey('wardrobe_take_off_$slot'),
                tooltip: '벗기기',
                onPressed: busy ? null : () => onTakeOff(slot),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      );
    }
    final complete = s.completeSetId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s2,
      children: [
        Text('지금 입은 것', style: Theme.of(context).textTheme.titleMedium),
        ...rows,
        if (complete != null)
          OutlinedButton(
            key: const ValueKey('wardrobe_take_off_set'),
            onPressed: busy ? null : () => onTakeOffSet(complete),
            child: const Text('세트 한 번에 벗기기'),
          ),
      ],
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
                child: Container(
                  key: const ValueKey('wardrobe_purchase_thumb'),
                  width: 180,
                  height: 120,
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
