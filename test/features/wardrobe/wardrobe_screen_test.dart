import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/domain/dog_catalog.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_models.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<void> buyNight(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('wardrobe_scope_store')));
  await tester.pumpAndSettle();
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
    expect(caption(tester), '실제 적용 상태');
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
    expect(caption(tester), '보유함 · 실제 적용 전');
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
    expect(caption(tester), '실제 적용 상태');
    expect(find.text('착용 중'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('wardrobe_scope_store')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe_theme_night')));
    await tester.pump();
    expect(caption(tester), '미리보기 · 실제 적용 전');
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
    expect(find.text('착용하기'), findsOneWidget);
    expect(find.text('구매 완료 · 아직 적용 전'), findsOneWidget);
    expect(find.text('보유 200포인트'), findsOneWidget);
  });

  testWidgets('unknown price and balance are never invented', (tester) async {
    await tester.pumpWidget(
      host(screen(load: () async => snap(balance: null))),
    );
    await tester.pumpAndSettle();
    expect(find.text('포인트 확인 전'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wardrobe_scope_store')));
    await tester.pumpAndSettle();
    expect(find.textContaining('가격 확인 전'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('wardrobe_scope_store')));
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
    expect(caption(tester), '보유함 · 실제 적용 전');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('wardrobe_balance'))).data,
      '보유 200포인트',
    );
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
    expect(balanceText(tester), '보유 497포인트');
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
    expect(balanceText(tester), '보유 497포인트');
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
}
