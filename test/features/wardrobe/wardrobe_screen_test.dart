import 'package:balmatchum_app/features/first_meeting/domain/dog_catalog.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_models.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_screen.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _colours = ['tomato', 'pine', 'plum', 'navy'];

WardrobeItemView _item(
  String id,
  String slot,
  String name, {
  List<String> owned = const [],
  List<String> wearable = _colours,
  bool sellable = true,
  List<String> colours = _colours,
  List<String> sets = const ['winter'],
}) => WardrobeItemView(
  itemId: id,
  slot: slot,
  name: name,
  price: 150,
  colours: colours,
  ownedColours: owned,
  wearableColours: wearable,
  sellable: sellable,
  setIds: sets,
);

/// A maltese wardrobe in the winter set's shape (server catalog 2026-11-12).
WardrobeStore snap({
  List<String> paddingOwned = const [],
  List<String> beanieOwned = const [],
  List<String> bootiesOwned = const [],
  bool duskOwned = false,
  List<WardrobeEquipView> equipped = const [],
  String background = 'sunny',
  String? complete,
  List<String> wearable = _colours,
  WardrobeSetView? season,
  bool subscriber = false,
  int balance = 1240,
}) {
  final missing = {
    for (final c in _colours)
      c:
          [
            paddingOwned,
            beanieOwned,
            bootiesOwned,
          ].where((o) => !o.contains(c)).length +
          (duskOwned ? 0 : 1),
  };
  return WardrobeStore(
    colours: [
      WardrobeColourView(
        colourId: 'tomato',
        name: '토마토 레드',
        swatch: 0xFFE0453A,
      ),
      WardrobeColourView(colourId: 'pine', name: '소나무 초록', swatch: 0xFF2E9A5E),
      WardrobeColourView(colourId: 'plum', name: '자두 보라', swatch: 0xFF8A4FC8),
      WardrobeColourView(colourId: 'navy', name: '밤하늘 남색', swatch: 0xFF2B4C9B),
    ],
    items: [
      _item('beanie', 'head', '방울 비니', owned: beanieOwned, wearable: wearable),
      _item('padding', 'torso', '패딩', owned: paddingOwned, wearable: wearable),
      _item('booties', 'feet', '부티', owned: bootiesOwned, wearable: wearable),
    ],
    backgrounds: [
      WardrobeBackgroundView(
        backgroundId: 'sunny',
        name: '맑음',
        price: 0,
        owned: true,
        sellable: true,
      ),
      WardrobeBackgroundView(
        backgroundId: 'winter-dusk',
        name: '겨울 저녁',
        price: 100,
        owned: duskOwned,
        sellable: true,
        setId: 'winter',
      ),
    ],
    sets: [
      WardrobeSetView(
        setId: 'winter',
        name: '겨울 세트',
        itemIds: ['padding', 'beanie', 'booties'],
        backgroundId: 'winter-dusk',
        effect: 'snow',
        fullPrice: 550,
        discountPct: 20,
        sellable: true,
        colours: [
          for (final c in _colours)
            WardrobeSetColourView(
              colourId: c,
              price: missing[c]! * 0 + _price(missing[c]!, duskOwned),
              missingParts: missing[c]!,
              purchasable: missing[c]! > 0 && wearable.isNotEmpty,
              wearable: wearable.contains(c),
            ),
        ],
      ),
      ?season,
    ],
    equipped: equipped,
    equippedBackground: background,
    completeSetId: complete,
    completeColour: complete == null ? null : 'tomato',
    breedId: 'maltese',
    balance: balance,
    subscriber: subscriber,
  );
}

int _price(int missing, bool duskOwned) {
  final items = duskOwned ? missing : missing - 1;
  return (items * 150 + (duskOwned ? 0 : 100)) * 80 ~/ 100;
}

final holiday = WardrobeSetView(
  setId: 'holiday',
  name: '크리스마스 세트',
  itemIds: ['rudolph-band', 'santa-cape'],
  backgroundId: 'holiday-night',
  effect: 'holiday',
  fullPrice: 400,
  discountPct: 20,
  sellable: false,
  colours: [
    for (final c in ['tomato', 'pine', 'navy'])
      WardrobeSetColourView(
        colourId: c,
        price: 320,
        missingParts: 3,
        purchasable: false,
        wearable: true,
      ),
  ],
  season: WardrobeSeasonView(
    month: '2026-12',
    releaseAt: DateTime.utc(2026, 11, 30, 15),
    endsAt: DateTime.utc(2026, 12, 31, 14, 59, 59),
    open: true,
    granted: false,
    resaleOpen: false,
  ),
);

WardrobeEquipView worn(String slot, String item, String colour) =>
    WardrobeEquipView(slot: slot, itemId: item, colourId: colour);

final actions = <WardrobeAction>[];
var subscribed = 0;

Widget screen({
  LoadWardrobe? load,
  RunWardrobeAction? run,
  WardrobeStore? after,
  Key? key,
  Future<void> Function()? subscribe,
}) => MaterialApp(
  home: WardrobeScreen(
    key: key,
    dog: FirstMeetingCatalog.byId('maltese'),
    loadWardrobe: load ?? () async => snap(),
    runAction:
        run ??
        (action) async {
          actions.add(action);
          return after ?? snap();
        },
    onSubscribe: subscribe ?? () async => subscribed++,
    onBack: () {},
    onHome: () {},
  ),
);

Future<void> settle(WidgetTester tester) async {
  // The set effect ticks forever, so never wait for an idle frame.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // The list builds lazily; scroll until the target exists and is shown.
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('wardrobe_scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  setUp(() {
    actions.clear();
    subscribed = 0;
  });

  testWidgets('set card shows the band and the 20% set price', (tester) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    expect(find.text('SET · 겨울 세트'), findsOneWidget);
    expect(find.text('따로 사면 550P'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wardrobe_set_price_winter')))
          .data,
      '440P',
    );
  });

  testWidgets('buying a set in a chosen colour asks first, then buys it', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_colour_winter_pine')),
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_action_winter')),
    );
    expect(
      find.byKey(const ValueKey('wardrobe_purchase_title')),
      findsOneWidget,
    );
    expect(actions, isEmpty);
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
    await settle(tester);

    expect(actions, [
      const WardrobeAction(WardrobeActionKind.buySet, 'winter', 'pine'),
    ]);
  });

  testWidgets('trying a set on shows completion locally without the server', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settle(tester);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_try_winter')),
    );

    expect(find.byKey(const ValueKey('wardrobe_trying')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe_set_complete')), findsOneWidget);
    expect(find.text('겨울 세트 완성'), findsOneWidget);
    expect(actions, isEmpty);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_trial_reset')),
    );
    expect(find.byKey(const ValueKey('wardrobe_trying')), findsNothing);
    expect(find.byKey(const ValueKey('wardrobe_set_complete')), findsNothing);
  });

  testWidgets('an owned set is worn as a set and a complete one taken off', (
    tester,
  ) async {
    const all = ['tomato'];
    await tester.pumpWidget(
      screen(
        load: () async => snap(
          paddingOwned: all,
          beanieOwned: all,
          bootiesOwned: all,
          duskOwned: true,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('세트로 입히기'), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_action_winter')),
    );
    expect(actions.single.kind, WardrobeActionKind.wearSet);

    await tester.pumpWidget(
      screen(
        key: const ValueKey('complete'),
        load: () async => snap(
          paddingOwned: all,
          beanieOwned: all,
          bootiesOwned: all,
          duskOwned: true,
          background: 'winter-dusk',
          complete: 'winter',
          equipped: [
            worn('head', 'beanie', 'tomato'),
            worn('torso', 'padding', 'tomato'),
            worn('feet', 'booties', 'tomato'),
          ],
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('wardrobe_set_complete')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe_take_off_set')), findsOneWidget);
  });

  testWidgets(
    'one item in another colour breaks the set and says what is left',
    (tester) async {
      await tester.pumpWidget(
        screen(
          load: () async => snap(
            paddingOwned: ['tomato'],
            beanieOwned: ['plum'],
            bootiesOwned: ['tomato'],
            duskOwned: true,
            background: 'winter-dusk',
            equipped: [
              worn('head', 'beanie', 'plum'),
              worn('torso', 'padding', 'tomato'),
              worn('feet', 'booties', 'tomato'),
            ],
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('wardrobe_set_complete')), findsNothing);
      expect(find.text('겨울 세트까지 1개 남았어요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('wardrobe_worn_off_head')),
        findsOneWidget,
      );
    },
  );

  testWidgets('items: buy an unowned colour, wear an owned one', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(load: () async => snap(paddingOwned: ['tomato'])),
    );
    await settle(tester);
    await tapVisible(tester, find.byKey(const ValueKey('wardrobe_tab_items')));

    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('wardrobe_item_action_padding')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '입히기',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_item_action_padding')),
    );
    expect(
      actions.last,
      const WardrobeAction(WardrobeActionKind.wearItem, 'padding', 'tomato'),
    );

    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_item_colour_padding_navy')),
    );
    expect(find.text('150P 사기'), findsWidgets);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_item_action_padding')),
    );
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
    await settle(tester);
    expect(
      actions.last,
      const WardrobeAction(WardrobeActionKind.buyItem, 'padding', 'navy'),
    );
  });

  testWidgets('a breed without art can try nothing and buy nothing', (
    tester,
  ) async {
    await tester.pumpWidget(screen(load: () async => snap(wearable: const [])));
    await settle(tester);
    await tapVisible(tester, find.byKey(const ValueKey('wardrobe_tab_items')));

    expect(find.text('곧 입을 수 있어요'), findsWidgets);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('wardrobe_item_action_beanie')),
    );
    expect(button.onPressed, isNull);
    final trial = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('wardrobe_item_try_beanie')),
    );
    expect(trial.onPressed, isNull);
  });

  testWidgets('a season set asks a non-subscriber to subscribe', (
    tester,
  ) async {
    await tester.pumpWidget(screen(load: () async => snap(season: holiday)));
    await settle(tester);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_action_holiday')),
    );
    expect(find.text('구독자 선물 · 크리스마스 세트'), findsOneWidget);
    expect(find.text('12월 선물 · 31일까지'), findsOneWidget);

    expect(subscribed, 1);
    expect(actions, isEmpty);
  });

  testWidgets('coming back from subscribing reloads and offers the gift', (
    tester,
  ) async {
    var loads = 0;
    var member = false;
    await tester.pumpWidget(
      screen(
        load: () async {
          loads++;
          return snap(season: holiday, subscriber: member);
        },
        subscribe: () async => member = true,
      ),
    );
    await settle(tester);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_action_holiday')),
    );
    await settle(tester);

    expect(loads, 2);
    await tester.scrollUntilVisible(
      find.text('선물 받기'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('wardrobe_scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('선물 받기'), findsOneWidget);
  });

  testWidgets('a subscriber not yet gifted receives the set for free', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(load: () async => snap(season: holiday, subscriber: true)),
    );
    await settle(tester);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_action_holiday')),
    );

    expect(actions, [
      const WardrobeAction(WardrobeActionKind.buySet, 'holiday', 'tomato'),
    ]);
  });

  testWidgets('a single-item gift is received by a member from its card', (
    tester,
  ) async {
    final gift = WardrobeSeasonView(
      month: '2027-03',
      releaseAt: DateTime.utc(2027, 2, 28, 15),
      endsAt: DateTime.utc(2027, 3, 31, 14, 59, 59),
      open: true,
      granted: false,
      resaleOpen: false,
    );
    final base = snap(subscriber: true);
    final store = base.copyWith(
      items: [
        for (final i in base.items)
          i.itemId == 'beanie' ? i.copyWith(sellable: false, gift: gift) : i,
      ],
    );
    await tester.pumpWidget(screen(load: () async => store));
    await settle(tester);
    await tapVisible(tester, find.byKey(const ValueKey('wardrobe_tab_items')));
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_item_action_beanie')),
    );

    expect(actions, [
      const WardrobeAction(WardrobeActionKind.buyItem, 'beanie', 'tomato'),
    ]);
  });

  testWidgets('a refused purchase for points says so and offers a way home', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        run: (_) async => throw const WardrobeActionException(
          WardrobeFailureReason.insufficientPoints,
        ),
      ),
    );
    await settle(tester);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('wardrobe_set_action_winter')),
    );
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
    await settle(tester);

    expect(find.text('포인트가 부족해요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe_earn_points')), findsOneWidget);
  });
}
