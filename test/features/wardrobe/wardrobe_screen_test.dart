import 'dart:async';

import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/first_meeting/domain/dog_catalog.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_models.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';

const sunny = WardrobeTheme(
  id: 'sunny',
  name: '햇살 마당',
  owned: true,
  colorValue: 0xfff5eedc,
  backgroundAsset: 'assets/first_meeting/sunny.png',
);
const plain = WardrobeTheme(
  id: 'plain',
  name: '크림 무대',
  owned: true,
  colorValue: 0xffe4e7e9,
);
const store = WardrobeTheme(
  id: 'night',
  name: '저녁 마당',
  owned: false,
  colorValue: 0xffdce8ef,
  price: 300,
);
const unpriced = WardrobeTheme(
  id: 'snow',
  name: '눈 마당',
  owned: false,
  colorValue: 0xffeef3f6,
);
const ownedNight = WardrobeTheme(
  id: 'night',
  name: '저녁 마당',
  owned: true,
  colorValue: 0xffdce8ef,
  price: 300,
);

const offeredVest = WardrobeOutfits(
  items: [
    WardrobeOutfit(
      id: 'vest-low-v',
      name: '조끼',
      price: 3,
      owned: false,
      compatible: true,
    ),
  ],
);

WardrobeOutfits vest({
  bool owned = false,
  bool compatible = true,
  bool worn = false,
}) => WardrobeOutfits(
  items: [
    WardrobeOutfit(
      id: 'vest-low-v',
      name: '조끼',
      price: 3,
      owned: owned,
      compatible: compatible,
    ),
  ],
  equippedId: worn ? 'vest-low-v' : null,
);

WardrobeSnapshot snap({
  List<WardrobeTheme> themes = const [sunny, plain, store, unpriced],
  String? equipped = 'sunny',
  int? balance = 500,
  String? fixture,
  WardrobeOutfits? outfits = offeredVest,
}) => WardrobeSnapshot(
  themes: themes,
  equippedThemeId: equipped,
  balance: balance,
  fixtureLabel: fixture,
  outfits: outfits,
);

Widget host(Widget child) => MaterialApp(theme: meetingTheme(), home: child);

WardrobeScreen screen({
  required LoadWardrobe load,
  WardrobeThemeAction? purchase,
  WardrobeThemeAction? equip,
  WardrobeOutfitAction? change,
  String dog = 'shih-tzu',
  VoidCallback? onHome,
}) => WardrobeScreen(
  dog: FirstMeetingCatalog.byId(dog),
  loadWardrobe: load,
  purchaseTheme: purchase ?? (_) async => throw StateError('no purchase'),
  equipTheme: equip ?? (_) async => throw StateError('no equip'),
  changeOutfit: change ?? (_, _) async => throw StateError('no change'),
  onBack: () {},
  onHome: onHome ?? () {},
);

final outfitAction = find.byKey(
  const ValueKey('wardrobe_outfit_action_vest-low-v'),
);
final previewDog = find.byKey(const ValueKey('wardrobe_preview_dog'));
final previewOutfit = find.byKey(const ValueKey('wardrobe_preview_outfit'));

/// The approved sprite is drawn exactly as before, worn or not.
void expectBaseDog(WidgetTester tester) {
  final image = tester.widget<Image>(previewDog);
  expect(
    image.image,
    const AssetImage('assets/first_meeting/dogs/shih-tzu.png'),
  );
  expect(image.fit, BoxFit.contain);
  expect(image.filterQuality, FilterQuality.none);
}

String balanceText(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('wardrobe_balance'))).data!;

Future<void> confirmVestPurchase(WidgetTester tester) async {
  await tester.ensureVisible(outfitAction);
  await tester.tap(outfitAction);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
  await tester.pumpAndSettle();
}

String caption(WidgetTester t) => t
    .widget<Text>(find.byKey(const ValueKey('wardrobe_preview_caption')))
    .data!;

/// The preview tag's state: `trial`, `equipped` (what the server applied)
/// or `none`.
Finder previewState(String state) =>
    find.byKey(ValueKey('wardrobe_preview_$state'));

Finder actionState(String state) =>
    find.byKey(ValueKey('wardrobe_action_state_$state'));

Finder tile(String id) => find.byKey(ValueKey('wardrobe_tile_$id'));

Finder wornBadge(String id) =>
    find.byKey(ValueKey('wardrobe_theme_equipped_$id'));

BorderSide tileSide(WidgetTester t, String id) =>
    (t.widget<Material>(tile(id)).shape! as RoundedRectangleBorder).side;

String statusText(WidgetTester t, String id) =>
    t.widget<Text>(find.byKey(ValueKey('wardrobe_theme_status_$id'))).data!;

final digit = RegExp(r'\d');

Future<void> buyNight(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown equipped state requires reload before preview', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      host(
        screen(
          load: () async =>
              ++loads == 1 ? snap(equipped: null, balance: null) : snap(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('wardrobe_preview_caption')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('product_retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('wardrobe_preview_caption')),
      findsOneWidget,
    );
    expect(loads, 2);
  });
  testWidgets('loads server equipped theme after a retry', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      host(
        screen(
          load: () async {
            if (++loads == 1) throw Exception('offline');
            return snap();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('꾸미기 정보를 불러오지 못했어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('product_retry')));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(previewState('equipped'), findsOneWidget);
    expect(caption(tester), contains(sunny.name));
    expect(
      find.byKey(const ValueKey('wardrobe_preview_bg_sunny')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('wardrobe_preview_dog')), findsOneWidget);
  });

  testWidgets('selecting previews only; equip is a separate single call', (
    tester,
  ) async {
    final equips = <String>[];
    final pending = Completer<WardrobeSnapshot>();
    await tester.pumpWidget(
      host(
        screen(
          load: () async => snap(),
          equip: (t) {
            equips.add(t.id);
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wardrobe_theme_plain')));
    await tester.pump();
    expect(previewState('trial'), findsOneWidget);
    expect(caption(tester), contains(plain.name));
    // No approved image: the server colour is shown, not a generated asset.
    expect(
      find.byKey(const ValueKey('wardrobe_preview_color_plain')),
      findsOneWidget,
    );
    expect(equips, isEmpty);
    await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
    await tester.pump();
    pending.complete(snap(equipped: 'plain'));
    await tester.pumpAndSettle();
    expect(equips, ['plain']);
    expect(previewState('equipped'), findsOneWidget);
    expect(wornBadge('plain'), findsOneWidget);
    expect(wornBadge('sunny'), findsNothing);
    expect(actionState('equipped'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('wardrobe_action')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('purchase needs confirmation and does not equip', (tester) async {
    final purchases = <String>[];
    var equips = 0;
    await tester.pumpWidget(
      host(
        screen(
          load: () async => snap(),
          purchase: (t) async {
            purchases.add(t.id);
            return snap(
              themes: [
                sunny,
                plain,
                const WardrobeTheme(
                  id: 'night',
                  name: '저녁 마당',
                  owned: true,
                  colorValue: 0xffdce8ef,
                  price: 300,
                ),
                unpriced,
              ],
              balance: 200,
            );
          },
          equip: (_) async {
            equips++;
            return snap();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
    await tester.pump();
    expect(previewState('trial'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_cancel')));
    await tester.pumpAndSettle();
    expect(purchases, isEmpty);
    await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
    await tester.pumpAndSettle();
    expect(purchases, ['night']);
    expect(equips, 0);
    expect(actionState('equip'), findsOneWidget);
    expect(balanceText(tester), '200P');
  });

  testWidgets('unknown price and balance are never invented', (tester) async {
    await tester.pumpWidget(
      host(screen(load: () async => snap(balance: null))),
    );
    await tester.pumpAndSettle();
    expect(balanceText(tester), isNot(contains(digit)));
    expect(statusText(tester, 'snow'), isNot(contains(digit)));
    expect(
      find.descendant(of: tile('snow'), matching: find.byType(PixelIcon)),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('wardrobe_theme_snow')));
    await tester.pump();
    final action = tester.widget<FilledButton>(
      find.byKey(const ValueKey('wardrobe_action')),
    );
    expect(action.onPressed, isNull);
  });

  testWidgets('server insufficient points routes home once', (tester) async {
    var home = 0;
    await tester.pumpWidget(
      host(
        screen(
          load: () async => snap(balance: null),
          purchase: (_) async => throw const WardrobeActionException(
            WardrobeFailureReason.insufficientPoints,
          ),
          onHome: () => home++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('포인트가 부족해요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wardrobe_earn_points')));
    await tester.pump();
    expect(home, 1);
  });

  testWidgets('lost purchase response reloads server ownership and balance', (
    tester,
  ) async {
    var loads = 0;
    final purchases = <String>[];
    await tester.pumpWidget(
      host(
        screen(
          load: () async => ++loads == 1
              ? snap()
              : snap(
                  themes: const [sunny, plain, ownedNight, unpriced],
                  balance: 200,
                ),
          purchase: (t) async {
            purchases.add(t.id);
            throw Exception('response lost after commit');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await buyNight(tester);
    expect(loads, 2);
    expect(purchases, ['night']);
    expect(previewState('trial'), findsOneWidget);
    // Owned now: the tile shows ownership instead of a price.
    expect(statusText(tester, 'night'), isNot(contains(digit)));
    expect(balanceText(tester), '200P');
  });

  testWidgets('unconfirmed purchase result blocks another purchase', (
    tester,
  ) async {
    var loads = 0;
    final purchases = <String>[];
    await tester.pumpWidget(
      host(
        screen(
          load: () async {
            if (++loads == 2) throw Exception('still offline');
            return snap();
          },
          purchase: (t) async {
            purchases.add(t.id);
            throw Exception('response lost');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await buyNight(tester);
    expect(loads, 2);
    expect(find.byKey(const ValueKey('wardrobe_action')), findsNothing);
    expect(find.byKey(const ValueKey('product_retry')), findsOneWidget);
    expect(purchases, ['night']);
  });

  for (final (breed, compatible) in [
    ('toy-poodle', false),
    // The server allows it, but no layer is drawn on this sprite.
    ('toy-poodle', true),
    ('shih-tzu', false),
  ]) {
    testWidgets('$breed with server compatible $compatible cannot buy vest', (
      tester,
    ) async {
      final changes = <OutfitChange>[];
      await tester.pumpWidget(
        host(
          screen(
            dog: breed,
            load: () async => snap(outfits: vest(compatible: compatible)),
            change: (_, change) async {
              changes.add(change);
              return snap();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(outfitAction);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('wardrobe_outfit_unsupported')),
            )
            .data,
        '이 강아지는 아직 입을 수 없어요',
      );
      expect(tester.widget<ButtonStyleButton>(outfitAction).onPressed, isNull);
      await tester.tap(outfitAction);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wardrobe_purchase_confirm')),
        findsNothing,
      );
      expect(changes, isEmpty);
      expect(previewOutfit, findsNothing);
    });
  }

  testWidgets('the background action alone is primary; markers stay dev-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(screen(load: () async => snap(fixture: 'dev-fixture-v1'))),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(outfitAction);
    expect(tester.widget(outfitAction), isA<OutlinedButton>());
    expect(
      tester.widgetList(find.byType(FilledButton)).length,
      lessThanOrEqualTo(1),
    );
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsNothing);
    debugFixtureLabelsVisible = true;
    addTearDown(() => debugFixtureLabelsVisible = null);
    await tester.pumpWidget(
      host(screen(load: () async => snap(fixture: 'dev-fixture-v1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsOneWidget);
  });

  testWidgets('vest above the balance cannot be bought', (tester) async {
    await tester.pumpWidget(host(screen(load: () async => snap(balance: 2))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(outfitAction);
    expect(tester.widget<ButtonStyleButton>(outfitAction).onPressed, isNull);
  });

  testWidgets('vest purchase needs confirmation and does not wear it', (
    tester,
  ) async {
    final changes = <OutfitChange>[];
    await tester.pumpWidget(
      host(
        screen(
          load: () async => snap(),
          change: (_, change) async {
            changes.add(change);
            return snap(outfits: vest(owned: true), balance: 497);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(outfitAction);
    await tester.tap(outfitAction);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_cancel')));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await confirmVestPurchase(tester);
    expect(changes, [OutfitChange.purchase]);
    expect(previewOutfit, findsNothing);
    expect(balanceText(tester), '497P');
    expect(tester.widget<ButtonStyleButton>(outfitAction).onPressed, isNotNull);
  });

  testWidgets('worn vest is drawn on the base dog canvas', (tester) async {
    await tester.pumpWidget(
      host(
        screen(load: () async => snap(outfits: vest(owned: true, worn: true))),
      ),
    );
    await tester.pumpAndSettle();
    expectBaseDog(tester);
    final layer = tester.widget<Image>(previewOutfit);
    expect(layer.image, const AssetImage('assets/wardrobe/vest/shih-tzu.png'));
    expect(layer.fit, BoxFit.contain);
    expect(layer.filterQuality, FilterQuality.none);
    expect(tester.getRect(previewOutfit), tester.getRect(previewDog));
  });

  testWidgets('owned vest left off draws only the base dog', (tester) async {
    await tester.pumpWidget(
      host(screen(load: () async => snap(outfits: vest(owned: true)))),
    );
    await tester.pumpAndSettle();
    expectBaseDog(tester);
    expect(previewOutfit, findsNothing);
  });

  testWidgets('owned vest wears and comes off with single calls', (
    tester,
  ) async {
    final changes = <OutfitChange>[];
    final wearing = Completer<WardrobeSnapshot>();
    await tester.pumpWidget(
      host(
        screen(
          load: () async => snap(outfits: vest(owned: true)),
          change: (_, change) {
            changes.add(change);
            return switch (change) {
              OutfitChange.wear => wearing.future,
              OutfitChange.purchase || OutfitChange.remove => Future.value(
                snap(outfits: vest(owned: true)),
              ),
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(outfitAction);
    final bare = tester.getRect(previewDog);
    await tester.tap(outfitAction);
    await tester.pump();
    await tester.tap(outfitAction);
    await tester.pump();
    wearing.complete(snap(outfits: vest(owned: true, worn: true)));
    await tester.pumpAndSettle();
    expect(changes, [OutfitChange.wear]);
    expectBaseDog(tester);
    expect(tester.getRect(previewDog), bare);
    expect(tester.getRect(previewOutfit), bare);
    await tester.tap(outfitAction);
    await tester.pumpAndSettle();
    expect(changes, [OutfitChange.wear, OutfitChange.remove]);
    expect(previewOutfit, findsNothing);
    expectBaseDog(tester);
    expect(tester.getRect(previewDog), bare);
  });

  testWidgets('server refusal is shown on the vest card', (tester) async {
    await tester.pumpWidget(
      host(
        screen(
          load: () async => snap(outfits: vest(owned: true)),
          change: (_, _) async => throw const WardrobeActionException(
            WardrobeFailureReason.incompatible,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(outfitAction);
    await tester.tap(outfitAction);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wardrobe_outfit_error')))
          .data,
      '이 강아지는 아직 입을 수 없어요',
    );
    expect(find.byKey(const ValueKey('wardrobe_error')), findsNothing);
    expect(previewOutfit, findsNothing);
  });

  testWidgets('lost vest response reloads the server state', (tester) async {
    var loads = 0;
    final changes = <OutfitChange>[];
    await tester.pumpWidget(
      host(
        screen(
          load: () async => ++loads == 1
              ? snap()
              : snap(outfits: vest(owned: true), balance: 497),
          change: (_, change) async {
            changes.add(change);
            throw Exception('response lost after commit');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await confirmVestPurchase(tester);
    expect(changes, [OutfitChange.purchase]);
    expect(loads, 2);
    expect(find.byKey(const ValueKey('wardrobe_outfit_error')), findsOneWidget);
    expect(balanceText(tester), '497P');
    expect(previewOutfit, findsNothing);
  });

  testWidgets('unknown outfits keep themes usable until reloaded', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      host(
        screen(load: () async => ++loads == 1 ? snap(outfits: null) : snap()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wardrobe_theme_sunny')), findsOneWidget);
    expect(outfitAction, findsNothing);
    final reload = find.byKey(const ValueKey('wardrobe_outfits_reload'));
    await tester.ensureVisible(reload);
    await tester.tap(reload);
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(outfitAction, findsOneWidget);
  });
  group('shop (guide 7.6)', () {
    Future<void> pumpAt(
      WidgetTester tester,
      Size size, {
      EdgeInsets padding = EdgeInsets.zero,
      double scale = 1,
    }) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      tester.view.padding = FakeViewPadding(
        left: padding.left * 3,
        top: padding.top * 3,
        right: padding.right * 3,
        bottom: padding.bottom * 3,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen(load: () async => snap()),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<Rect> tileRects(WidgetTester tester) => [
      for (final t in snap().themes) tester.getRect(tile(t.id)),
    ];

    for (final size in const [Size(390, 844), Size(402, 874)]) {
      testWidgets('a ${size.width.toInt()} pt phone shows three tiles a row', (
        tester,
      ) async {
        await pumpAt(
          tester,
          size,
          padding: const EdgeInsets.only(top: 47, bottom: 34),
        );
        final rects = tileRects(tester);
        expect(rects[1].top, rects[0].top);
        expect(rects[2].top, rects[0].top);
        expect(rects[3].top, greaterThan(rects[0].bottom));
        expect(rects[1].width, closeTo(rects[0].width, 0.01));
        expect(rects[2].width, closeTo(rects[0].width, 0.01));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a 320 pt screen is not forced into three a row', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(320, 568),
        padding: const EdgeInsets.only(top: 20),
      );
      final rects = tileRects(tester);
      expect(rects[1].top, rects[0].top);
      expect(rects[2].top, greaterThan(rects[0].bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Duo outer display keeps three a row left of the rail', (
      tester,
    ) async {
      useDuoViewport(tester, 'outer portrait');
      await tester.pumpWidget(duoHost(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      expect(find.byType(DuoRail), findsOneWidget);
      final rects = tileRects(tester);
      expect(rects[2].top, rects[0].top);
      expect(rects[3].top, greaterThan(rects[0].bottom));
      for (final rect in rects) {
        expect(rect.right, lessThanOrEqualTo(382));
      }
      for (final key in ['wardrobe_preview', 'wardrobe_action']) {
        expect(
          tester.getRect(find.byKey(ValueKey(key))).right,
          lessThanOrEqualTo(382),
        );
      }
      expect(tester.takeException(), isNull);
    });

    for (final (size, padding) in const [
      (Size(320, 568), EdgeInsets.only(top: 20)),
      (Size(402, 874), EdgeInsets.only(top: 62, bottom: 34)),
    ]) {
      testWidgets(
        '${size.width.toInt()} pt at the 1.15x text cap scrolls to every row',
        (tester) async {
          await pumpAt(tester, size, padding: padding, scale: 1.15);
          for (final key in [
            'wardrobe_theme_snow',
            'wardrobe_outfit_action_vest-low-v',
            'wardrobe_action',
          ]) {
            final target = find.byKey(ValueKey(key));
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            expect(target.hitTestable(), findsOneWidget, reason: key);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('the selection outline and the worn badge are separate', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      // The applied theme starts selected and worn.
      expect(tileSide(tester, 'sunny').width, 2);
      expect(wornBadge('sunny'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
      await tester.pump();
      expect(
        tileSide(tester, 'night'),
        const BorderSide(color: MeetingColors.primaryStrong, width: 2),
      );
      for (final id in ['sunny', 'plain', 'snow']) {
        expect(tileSide(tester, id).width, 1, reason: id);
      }
      expect(wornBadge('sunny'), findsOneWidget);
      expect(wornBadge('night'), findsNothing);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('wardrobe_theme_night'))),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('wardrobe_theme_sunny'))),
        isSemantics(isButton: true, isSelected: false),
      );
      semantics.dispose();
    });

    testWidgets('tiles show a price, ownership or an unknown price', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      Finder pointIcon(String id) =>
          find.descendant(of: tile(id), matching: find.byType(PixelIcon));
      expect(statusText(tester, 'night'), contains(formatCount(store.price!)));
      expect(pointIcon('night'), findsOneWidget);
      for (final id in ['sunny', 'plain', 'snow']) {
        expect(statusText(tester, id), isNot(contains(digit)), reason: id);
        expect(pointIcon(id), findsNothing, reason: id);
      }
      expect(statusText(tester, 'plain'), statusText(tester, 'sunny'));
      expect(statusText(tester, 'snow'), isNot(statusText(tester, 'sunny')));
      final counts = tester
          .widget<Text>(find.byKey(const ValueKey('wardrobe_theme_counts')))
          .data!;
      // All four from the server list, two of them owned.
      expect(RegExp(r'\d+').allMatches(counts).map((m) => m[0]), ['4', '2']);
    });

    testWidgets('the preview names the pick and carries the balance chip', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      expect(previewState('equipped'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
      await tester.pump();
      expect(previewState('trial'), findsOneWidget);
      expect(caption(tester), contains(store.name));
      expect(balanceText(tester), contains(formatCount(500)));
      final preview = tester.getRect(
        find.byKey(const ValueKey('wardrobe_preview')),
      );
      final chip = tester.getRect(
        find.byKey(const ValueKey('wardrobe_balance_chip')),
      );
      final tag = tester.getRect(previewState('trial'));
      expect(chip.top - preview.top, closeTo(Space.s3, 0.5));
      expect(preview.right - chip.right, closeTo(Space.s3, 0.5));
      expect(tag.left - preview.left, closeTo(Space.s3, 0.5));
      expect(tag.right, lessThan(chip.left));
      // Picking the applied theme again shows the server state.
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_sunny')));
      await tester.pump();
      expect(previewState('equipped'), findsOneWidget);
    });

    testWidgets('tiles and the preview draw a theme the same way', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      final tileImage = tester.widget<Image>(
        find.byKey(const ValueKey('wardrobe_tile_bg_sunny')),
      );
      final previewImage = tester.widget<Image>(
        find.byKey(const ValueKey('wardrobe_preview_bg_sunny')),
      );
      expect(
        tileImage.image,
        const AssetImage('assets/first_meeting/sunny.png'),
      );
      expect(previewImage.image, tileImage.image);
      // Without an approved picture both use the server colour.
      expect(
        find.byKey(const ValueKey('wardrobe_tile_bg_plain')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_plain')));
      await tester.pump();
      for (final key in [
        'wardrobe_tile_color_plain',
        'wardrobe_preview_color_plain',
      ]) {
        expect(
          tester.widget<ColoredBox>(find.byKey(ValueKey(key))).color,
          Color(plain.colorValue),
          reason: key,
        );
      }
    });
  });
  group('purchase confirmation (guide 7.7)', () {
    Future<void> openNightPurchase(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
      await tester.pumpAndSettle();
    }

    String dialogText(WidgetTester t, String key) =>
        t.widget<Text>(find.byKey(ValueKey('wardrobe_purchase_$key'))).data!;

    String? titleLabel(WidgetTester t) => t
        .widget<Text>(find.byKey(const ValueKey('wardrobe_purchase_title')))
        .semanticsLabel;

    Finder confirmShowing(int price) => find.descendant(
      of: find.byKey(const ValueKey('wardrobe_purchase_confirm')),
      matching: find.textContaining(formatCount(price)),
    );

    testWidgets('shows the pick with its tile surface, price and balance', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      await openNightPurchase(tester);
      final thumb = find.descendant(
        of: find.byKey(const ValueKey('wardrobe_purchase_thumb')),
        matching: find.byKey(const ValueKey('wardrobe_purchase_color_night')),
      );
      expect(
        tester.widget<ColoredBox>(thumb).color,
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('wardrobe_tile_color_night')),
            )
            .color,
      );
      expect(titleLabel(tester), contains(store.name));
      expect(dialogText(tester, 'before'), contains(formatCount(500)));
      expect(dialogText(tester, 'after'), contains(formatCount(500 - 300)));
      expect(confirmShowing(300), findsOneWidget);
      expect(
        find.byKey(const ValueKey('wardrobe_purchase_balance_unknown')),
        findsNothing,
      );
    });

    testWidgets('an unknown balance gets no estimate and the price buys once', (
      tester,
    ) async {
      final purchases = <String>[];
      await tester.pumpWidget(
        host(
          screen(
            load: () async => snap(balance: null),
            purchase: (t) async {
              purchases.add(t.id);
              return snap(balance: null);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openNightPurchase(tester);
      expect(
        find.byKey(const ValueKey('wardrobe_purchase_balance')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('wardrobe_purchase_balance_unknown')),
        findsOneWidget,
      );
      // The confirmed price is the only number; no balance is invented.
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .join(' ');
      expect(RegExp(r'\d+').allMatches(texts).map((m) => m[0]).toSet(), {
        '300',
      });
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
      await tester.pumpAndSettle();
      expect(purchases, ['night']);
    });

    testWidgets('cancel or a tap outside buys nothing; confirm buys once', (
      tester,
    ) async {
      final purchases = <String>[];
      var equips = 0;
      await tester.pumpWidget(
        host(
          screen(
            load: () async => snap(),
            purchase: (t) async {
              purchases.add(t.id);
              return snap(
                themes: const [sunny, plain, ownedNight, unpriced],
                balance: 200,
              );
            },
            equip: (_) async {
              equips++;
              return snap();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openNightPurchase(tester);
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(purchases, isEmpty);
      await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
      await tester.pumpAndSettle();
      expect(purchases, ['night']);
      // Bought, not worn: the server still wears sunny.
      expect(equips, 0);
      expect(wornBadge('sunny'), findsOneWidget);
      expect(wornBadge('night'), findsNothing);
      expect(previewState('trial'), findsOneWidget);
    });

    testWidgets('after a lost answer the next dialog asks the re-read price', (
      tester,
    ) async {
      var loads = 0;
      final purchases = <String>[];
      const repriced = WardrobeTheme(
        id: 'night',
        name: '저녁 마당',
        owned: false,
        colorValue: 0xffdce8ef,
        price: 350,
      );
      await tester.pumpWidget(
        host(
          screen(
            load: () async => ++loads == 1
                ? snap()
                : snap(themes: const [sunny, plain, repriced, unpriced]),
            purchase: (t) async {
              purchases.add(t.id);
              throw Exception('response lost');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await buyNight(tester);
      // The lost answer was re-read from the server, never resent.
      expect(loads, 2);
      expect(purchases, ['night']);
      expect(find.byKey(const ValueKey('wardrobe_error')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
      await tester.pumpAndSettle();
      expect(confirmShowing(350), findsOneWidget);
      expect(dialogText(tester, 'after'), contains(formatCount(500 - 350)));
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_cancel')));
      await tester.pumpAndSettle();
      expect(purchases, ['night']);
    });

    testWidgets('a refused purchase keeps the server state and says why', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          screen(
            load: () async => snap(),
            purchase: (_) async => throw const WardrobeActionException(
              WardrobeFailureReason.unavailable,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await buyNight(tester);
      expect(find.byKey(const ValueKey('wardrobe_error')), findsOneWidget);
      expect(statusText(tester, 'night'), contains(formatCount(300)));
      expect(balanceText(tester), contains(formatCount(500)));
    });

    testWidgets('the vest dialog shows this breed\'s own layer', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      await tester.ensureVisible(outfitAction);
      await tester.tap(outfitAction);
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      Image image(String key) => tester.widget<Image>(
        find.descendant(of: dialog, matching: find.byKey(ValueKey(key))),
      );
      expect(
        image('wardrobe_purchase_dog').image,
        const AssetImage('assets/first_meeting/dogs/shih-tzu.png'),
      );
      expect(
        image('wardrobe_purchase_outfit').image,
        const AssetImage('assets/wardrobe/vest/shih-tzu.png'),
      );
      // The shelf's hanger icon is not offered as the product.
      expect(
        find.descendant(
          of: dialog,
          matching: find.image(
            const AssetImage('assets/first_meeting/icons/wardrobe.png'),
          ),
        ),
        findsNothing,
      );
      expect(titleLabel(tester), contains('조끼'));
      expect(confirmShowing(3), findsOneWidget);
      expect(dialogText(tester, 'after'), contains(formatCount(500 - 3)));
    });
  });
  group('bottom action (guide 7.8)', () {
    FilledButton actionButton(WidgetTester t) =>
        t.widget<FilledButton>(find.byKey(const ValueKey('wardrobe_action')));

    String actionLabel(WidgetTester t) => t
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('wardrobe_action')),
            matching: find.byType(Text),
          ),
        )
        .data!;

    String actionLine(WidgetTester t) => t
        .widget<Text>(find.byKey(const ValueKey('wardrobe_action_caption')))
        .data!;

    const gold = WardrobeTheme(
      id: 'gold',
      name: '금빛 마당',
      owned: false,
      colorValue: 0xfff3dfc0,
      price: 900,
    );

    testWidgets('the four board states change one button and its surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          screen(
            load: () async =>
                snap(themes: const [sunny, plain, store, unpriced, gold]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const disabled = {WidgetState.disabled};
      // Worn: a light disabled button with brown text.
      expect(actionState('equipped'), findsOneWidget);
      expect(actionButton(tester).onPressed, isNull);
      final style = actionButton(tester).style!;
      expect(style.backgroundColor!.resolve(disabled), MeetingColors.soft);
      expect(
        style.foregroundColor!.resolve(disabled),
        MeetingColors.primaryStrong,
      );
      // Owned, not worn.
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_plain')));
      await tester.pump();
      expect(actionState('equip'), findsOneWidget);
      expect(actionButton(tester).onPressed, isNotNull);
      // Buyable: the label carries the price; the line, price and balance.
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
      await tester.pump();
      expect(actionState('buy'), findsOneWidget);
      expect(actionButton(tester).onPressed, isNotNull);
      expect(actionLabel(tester), contains(formatCount(300)));
      expect(RegExp(r'\d+').allMatches(actionLine(tester)).map((m) => m[0]), [
        '300',
        '500',
      ]);
      // Above the balance: disabled and light, with what is needed and held.
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_gold')));
      await tester.pump();
      expect(actionState('short'), findsOneWidget);
      expect(actionButton(tester).onPressed, isNull);
      expect(RegExp(r'\d+').allMatches(actionLine(tester)).map((m) => m[0]), [
        '900',
        '500',
      ]);
      expect(
        find.byKey(const ValueKey('wardrobe_earn_points')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('wardrobe_action')), findsOneWidget);
    });

    testWidgets(
      'buying leads to wear and wearing to worn; picks change nothing',
      (tester) async {
        final equips = <String>[];
        var current = snap();
        await tester.pumpWidget(
          host(
            screen(
              load: () async => current,
              purchase: (_) async => current = snap(
                themes: const [sunny, plain, ownedNight, unpriced],
                balance: 200,
              ),
              equip: (t) async {
                equips.add(t.id);
                return current = snap(
                  themes: const [sunny, plain, ownedNight, unpriced],
                  equipped: t.id,
                  balance: 200,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await buyNight(tester);
        expect(actionState('equip'), findsOneWidget);
        expect(equips, isEmpty);
        await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
        await tester.pumpAndSettle();
        expect(equips, ['night']);
        expect(actionState('equipped'), findsOneWidget);
        expect(wornBadge('night'), findsOneWidget);
        // Picking another theme only previews it; night stays worn.
        await tester.tap(find.byKey(const ValueKey('wardrobe_theme_sunny')));
        await tester.pump();
        expect(actionState('equip'), findsOneWidget);
        expect(wornBadge('night'), findsOneWidget);
        expect(previewState('trial'), findsOneWidget);
        expect(equips, ['night']);
      },
    );

    testWidgets('while a purchase runs, taps add no requests', (tester) async {
      final pending = Completer<WardrobeSnapshot>();
      final purchases = <String>[];
      await tester.pumpWidget(
        host(
          screen(
            load: () async => snap(),
            purchase: (t) {
              purchases.add(t.id);
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
      await tester.pump();
      final button = tester.element(
        find.byKey(const ValueKey('wardrobe_action')),
      );
      await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
      await tester.pumpAndSettle();
      expect(actionState('busy'), findsOneWidget);
      // The same button stays in place, so an assistive focus stays on it.
      expect(
        tester.element(find.byKey(const ValueKey('wardrobe_action'))),
        same(button),
      );
      expect(actionButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('wardrobe_action')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.ensureVisible(outfitAction);
      expect(tester.widget<ButtonStyleButton>(outfitAction).onPressed, isNull);
      pending.complete(
        snap(themes: const [sunny, plain, ownedNight, unpriced], balance: 200),
      );
      await tester.pumpAndSettle();
      expect(purchases, ['night']);
      expect(actionState('equip'), findsOneWidget);
    });

    testWidgets('no selection and an unknown price keep their guidance', (
      tester,
    ) async {
      // The worn theme left the list, so nothing is selected.
      await tester.pumpWidget(
        host(screen(load: () async => snap(equipped: 'retired'))),
      );
      await tester.pumpAndSettle();
      expect(actionState('unselected'), findsOneWidget);
      expect(find.byKey(const ValueKey('wardrobe_action')), findsNothing);
      expect(previewState('none'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_snow')));
      await tester.pump();
      expect(actionState('unpriced'), findsOneWidget);
      expect(actionButton(tester).onPressed, isNull);
      expect(actionLine(tester), isNot(contains(digit)));
    });

    testWidgets('on a phone the action is pinned down to the bottom edge', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      final bar = tester.getRect(
        find.byKey(const ValueKey('wardrobe_action_bar')),
      );
      expect(bar.bottom, 874);
      expect(bar.width, 402);
      expect(
        tester.getRect(find.byKey(const ValueKey('wardrobe_action'))).bottom,
        lessThanOrEqualTo(874 - 34),
      );
    });

    testWidgets('on the Duo outer display the bar stays left of the rail', (
      tester,
    ) async {
      useDuoViewport(tester, 'outer portrait');
      await tester.pumpWidget(duoHost(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      final bar = tester.getRect(
        find.byKey(const ValueKey('wardrobe_action_bar')),
      );
      expect(bar.right, lessThanOrEqualTo(382));
      expect(bar.bottom, 678);
      for (final key in ['duo_rail_back', 'duo_rail_home']) {
        expect(
          tester.getRect(find.byKey(ValueKey(key))).left,
          greaterThanOrEqualTo(382),
        );
      }
      await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('wardrobe_action')).hitTestable(),
        findsOneWidget,
      );
    });
  });
}
