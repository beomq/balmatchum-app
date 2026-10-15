import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
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

WardrobeSnapshot snap({
  List<WardrobeTheme> themes = const [sunny, plain, store, unpriced],
  String? equipped = 'sunny',
  int? balance = 500,
  String? fixture,
}) => WardrobeSnapshot(
  themes: themes,
  equippedThemeId: equipped,
  balance: balance,
  fixtureLabel: fixture,
);

Widget host(Widget child) => MaterialApp(theme: meetingTheme(), home: child);

WardrobeScreen screen({
  required LoadWardrobe load,
  WardrobeThemeAction? purchase,
  WardrobeThemeAction? equip,
  VoidCallback? onHome,
}) => WardrobeScreen(
  dogAsset: 'assets/first_meeting/dogs/shih-tzu.png',
  loadWardrobe: load,
  purchaseTheme: purchase ?? (_) async => throw StateError('no purchase'),
  equipTheme: equip ?? (_) async => throw StateError('no equip'),
  onBack: () {},
  onHome: onHome ?? () {},
);

String caption(WidgetTester t) => t
    .widget<Text>(find.byKey(const ValueKey('wardrobe_preview_caption')))
    .data!;

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
}
