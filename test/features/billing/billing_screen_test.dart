import 'dart:async';

import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/billing/billing_controller.dart';
import 'package:balmatchum_app/features/billing/billing_disclosure.dart';
import 'package:balmatchum_app/features/billing/billing_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../support/duo_viewports.dart';
import 'billing_fakes.dart';

final _monthly = ProductDetails(
  id: 'test.monthly',
  title: '테스트 월간 구독',
  description: '로컬 QA 상품, 실제 판매 아님',
  price: '₩1,100',
  rawPrice: 1100,
  currencyCode: 'KRW',
);

/// The billing fakes behind one controller. The store returns [catalog],
/// the lifetime then the monthly product unless given.
class _Rig {
  _Rig({List<ProductDetails>? catalog, bool available = true}) {
    sdk
      ..catalog = catalog ?? [product(), _monthly]
      ..isAvailable = available;
    c = BillingController(
      repository: server,
      store: sdk,
      isCurrent: () => true,
    );
  }
  final sdk = FakeBillingStore();
  final server = FakeBillingRepository();
  late final BillingController c;
}

Future<_Rig> _open(
  WidgetTester tester, {
  List<ProductDetails>? catalog,
  bool available = true,
  Size size = const Size(390, 1400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = _Rig(catalog: catalog, available: available);
  addTearDown(() async {
    rig.c.dispose();
    await rig.sdk.events.close();
  });
  await rig.c.ready;
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: BillingScreen(controller: rig.c, onBack: () {}, onHome: () {}),
    ),
  );
  return rig;
}

Finder _key(String value) => find.byKey(ValueKey(value));

/// Every widget whose string key starts with [prefix].
Finder _keyed(String prefix) => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith(prefix),
    _ => false,
  },
);

VoidCallback? _onPressed(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed;

/// The tap of a price card; null while it cannot be picked.
GestureTapCallback? _onPick(WidgetTester tester, String id) => tester
    .widget<InkWell>(
      find.descendant(
        of: _key('billing_plan_$id'),
        matching: find.byType(InkWell),
      ),
    )
    .onTap;

Future<void> _pick(WidgetTester tester, String id) async {
  await tester.tap(_key('billing_plan_$id'));
  await tester.pump();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('billing live UI $width $brightness', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sdk = FakeBillingStore();
        final server = FakeBillingRepository();
        final c = BillingController(
          repository: server,
          store: sdk,
          isCurrent: () => true,
        );
        addTearDown(() async {
          c.dispose();
          await sdk.events.close();
        });
        await c.ready;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: BillingScreen(controller: c, onBack: () {}, onHome: () {}),
          ),
        );
        final retry = find.byKey(const ValueKey('billing_retry'));
        expect(find.text('€12,34 · 스토어에서 구매'), findsOneWidget);
        // A healthy store state has no manual status check (guide 3.1).
        expect(retry, findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('billing_buy_test.lifetime')),
        );
        await c.settled;
        await tester.pump();
        expect(sdk.bought.single.$2, bindingA);
        sdk.events.add([purchase(status: PurchaseStatus.pending)]);
        await tester.pumpAndSettle();
        expect(c.phase, BillingPhase.pending);
        expect(retry, findsNothing);
        sdk.events.add([purchase()]);
        await tester.pumpAndSettle();
        expect(sdk.completed, hasLength(1));
        expect(retry, findsNothing);
        // A failed observation is the one case with a retry, and it recovers.
        server.failure = BillingException(code: 'temporarilyUnavailable');
        await tester.ensureVisible(
          find.byKey(const ValueKey('billing_restore')),
        );
        await tester.tap(find.byKey(const ValueKey('billing_restore')));
        await tester.pumpAndSettle();
        expect(c.entitlement, isNull);
        expect(c.phase, BillingPhase.retry);
        expect(retry, findsOneWidget);
        server.failure = null;
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(c.phase, BillingPhase.ready);
        expect(retry, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('ready puts the benefit lines, the price cards and one '
      'purchase button first, in that order', (tester) async {
    await _open(tester);
    final benefits = [for (var i = 0; i < 3; i++) _key('billing_benefit_$i')];
    // The existing benefit and its limits, one line each, nothing added.
    expect([
      for (final line in benefits) tester.widget<Text>(line).semanticsLabel,
    ], billingBenefits);
    expect(_keyed('billing_benefit_'), findsNWidgets(3));
    final lifetime = _key('billing_plan_test.lifetime');
    final monthly = _key('billing_plan_test.monthly');
    final buy = _key('billing_buy');
    expect(
      tester.getRect(benefits.last).bottom,
      lessThan(tester.getRect(lifetime).top),
    );
    expect(
      tester.getRect(lifetime).bottom,
      lessThan(tester.getRect(monthly).top),
    );
    expect(tester.getRect(monthly).bottom, lessThan(tester.getRect(buy).top));
    // The store's localized prices, never a made-up amount.
    expect(
      tester.widget<Text>(_key('billing_price_test.lifetime')).data,
      contains(product().price),
    );
    expect(
      tester.widget<Text>(_key('billing_price_test.monthly')).data,
      contains(_monthly.price),
    );
    // One primary button; restore and the links are text actions.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    // A healthy store has no manual check or retry (guide 3.1).
    expect(_key('billing_retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing is picked among several products, and the pick '
      'decides the button, its price and its terms', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await _open(tester);
    // No default plan before the owner decides one (guide 9.1 ⑧).
    expect(_onPressed(tester, _key('billing_buy')), isNull);
    expect(_keyed('billing_terms_'), findsNothing);

    await _pick(tester, 'test.monthly');
    final buyMonthly = _key('billing_buy_test.monthly');
    expect(_onPressed(tester, buyMonthly), isNotNull);
    expect(
      find.descendant(
        of: buyMonthly,
        matching: find.textContaining(_monthly.price),
      ),
      findsOneWidget,
    );
    final monthlyTerms = _key('billing_terms_test.monthly');
    expect(
      tester.widget<Text>(monthlyTerms).data,
      billingTerms(subscription: true, price: _monthly.price),
    );
    expect(_keyed('billing_terms_'), findsOneWidget);
    // Right under the button that buys it.
    expect(
      tester.getRect(monthlyTerms).top,
      greaterThan(tester.getRect(buyMonthly).bottom),
    );
    expect(
      tester.getSemantics(_key('billing_plan_test.monthly')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(_key('billing_plan_test.lifetime')),
      isSemantics(isButton: true, isSelected: false),
    );

    await _pick(tester, 'test.lifetime');
    expect(buyMonthly, findsNothing);
    expect(
      tester.widget<Text>(_key('billing_terms_test.lifetime')).data,
      billingTerms(subscription: false, price: product().price),
    );
    expect(_keyed('billing_terms_'), findsOneWidget);

    // The one button buys exactly the picked product.
    await tester.tap(_key('billing_buy_test.lifetime'));
    await rig.c.settled;
    await tester.pump();
    expect(rig.sdk.bought.single.$1.id, 'test.lifetime');
    semantics.dispose();
  });

  testWidgets('a single product is the purchase itself, with its terms', (
    tester,
  ) async {
    await _open(tester, catalog: [product()]);
    expect(_onPick(tester, 'test.lifetime'), isNull);
    expect(_onPressed(tester, _key('billing_buy_test.lifetime')), isNotNull);
    expect(
      tester.widget<Text>(_key('billing_terms_test.lifetime')).data,
      billingTerms(subscription: false, price: product().price),
    );
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('restore is a small text action at the bottom with a 44 pt '
      'target, and it still restores', (tester) async {
    final rig = await _open(tester);
    final restore = _key('billing_restore');
    expect(tester.widget(restore), isA<TextButton>());
    expect(tester.getSize(restore).height, greaterThanOrEqualTo(44));
    // Below the purchase disclosures, above the legal links.
    expect(
      tester.getRect(restore).top,
      greaterThan(tester.getRect(find.text(billingRefund)).bottom),
    );
    expect(
      tester.getRect(_key('billing_privacy_policy')).top,
      greaterThanOrEqualTo(tester.getRect(restore).bottom),
    );
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(rig.sdk.restoredBinding, bindingA);
    expect(rig.server.calls.last, 'entitlement');
    expect(rig.c.phase, BillingPhase.ready);
  });

  testWidgets('a store that cannot be used shows its cause in one line and '
      'one real retry, with nothing disabled stacked under it', (tester) async {
    final rig = await _open(tester, available: false);
    expect(rig.c.phase, BillingPhase.unavailable);
    final panel = find.byType(ProductLoadState);
    // The cause line and the retry label.
    expect(
      find.descendant(of: panel, matching: find.byType(Text)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: _key('billing_retry')),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsOneWidget);
    expect(_keyed('billing_plan_'), findsNothing);
    expect(_keyed('billing_buy'), findsNothing);
    expect(_key('billing_status'), findsNothing);
    expect(_key('billing_restore'), findsNothing);
    // The legal links stay in the bottom area.
    expect(_key('billing_privacy_policy'), findsOneWidget);

    // The retry is real: it loads the store again and never buys.
    rig.sdk.isAvailable = true;
    await tester.tap(_key('billing_retry'));
    await tester.pumpAndSettle();
    expect(rig.c.phase, BillingPhase.ready);
    expect(_keyed('billing_plan_'), findsNWidgets(2));
    expect(rig.sdk.bought, isEmpty);
  });

  testWidgets('a failed product fetch shows its cause and one retry, and '
      'restore stays a working bottom action', (tester) async {
    final rig = await _open(tester, catalog: []);
    expect(rig.c.errorCode, 'productsUnavailable');
    expect(find.byType(FilledButton), findsOneWidget);
    expect(_key('billing_retry'), findsOneWidget);
    expect(_keyed('billing_plan_'), findsNothing);
    expect(_keyed('billing_buy'), findsNothing);
    expect(_onPressed(tester, _key('billing_restore')), isNotNull);

    rig.sdk.catalog = [product(), _monthly];
    await tester.tap(_key('billing_retry'));
    await tester.pumpAndSettle();
    expect(rig.c.errorCode, isNull);
    expect(_keyed('billing_plan_'), findsNWidgets(2));
  });

  testWidgets('purchasing, pending and verifying keep their progress line '
      'and lock input, and none of them reads as a failure', (tester) async {
    final rig = await _open(tester);
    final launch = Completer<bool>();
    rig.sdk.launch = () => launch.future;
    await _pick(tester, 'test.monthly');
    await tester.tap(_key('billing_buy_test.monthly'));
    await tester.pump();

    void expectLocked(BillingPhase phase, {required bool restore}) {
      expect(rig.c.phase, phase);
      expect(_key('billing_status'), findsOneWidget);
      expect(
        find.byType(LinearProgressIndicator),
        rig.c.busy ? findsOneWidget : findsNothing,
      );
      expect(_key('billing_retry'), findsNothing);
      expect(find.byType(ProductLoadState), findsNothing);
      expect(_onPick(tester, 'test.lifetime'), isNull);
      expect(_onPick(tester, 'test.monthly'), isNull);
      expect(_onPressed(tester, _key('billing_buy_test.monthly')), isNull);
      expect(_onPressed(tester, _key('billing_restore')) != null, restore);
    }

    expectLocked(BillingPhase.purchasing, restore: false);
    launch.complete(true);
    await rig.c.settled;
    rig.sdk.events.add([
      purchase(productId: 'test.monthly', status: PurchaseStatus.pending),
    ]);
    await rig.c.settled;
    await tester.pump();
    // Approval waits on the store, not on a request: restore stays usable.
    expectLocked(BillingPhase.pending, restore: true);

    final gate = Completer<EntitlementView>();
    rig.server.verification = (_) => gate.future;
    rig.sdk.events.add([purchase(productId: 'test.monthly')]);
    await tester.pump();
    expectLocked(BillingPhase.verifying, restore: false);

    gate.complete(view(active: true));
    await rig.c.settled;
    await tester.pump();
    expect(rig.c.phase, BillingPhase.ready);
    expect(_onPressed(tester, _key('billing_buy_test.monthly')), isNotNull);
  });

  testWidgets('a canceled purchase is not a failure: no retry, and the pick '
      'and the button work again', (tester) async {
    final rig = await _open(tester);
    await _pick(tester, 'test.monthly');
    await tester.tap(_key('billing_buy_test.monthly'));
    await rig.c.settled;
    rig.sdk.events.add([
      purchase(productId: 'test.monthly', status: PurchaseStatus.canceled),
    ]);
    await rig.c.settled;
    await tester.pump();
    expect(rig.c.phase, BillingPhase.canceled);
    expect(rig.c.errorCode, isNull);
    expect(_key('billing_retry'), findsNothing);
    expect(find.byType(ProductLoadState), findsNothing);
    expect(_key('billing_status'), findsOneWidget);
    expect(_onPressed(tester, _key('billing_buy_test.monthly')), isNotNull);
    expect(_onPick(tester, 'test.lifetime'), isNotNull);
  });

  testWidgets('without a controller the page says where purchases work and '
      'has no dead retry', (tester) async {
    var back = 0;
    var home = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: BillingScreen(
          controller: null,
          onBack: () => back++,
          onHome: () => home++,
        ),
      ),
    );
    expect(_key('billing_unsupported'), findsOneWidget);
    expect(_key('billing_retry'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    // Back and home are the page's only actions, and both work.
    await tester.tap(_key('product_back'));
    await tester.tap(_key('product_home'));
    expect((back, home), (1, 1));
  });

  testWidgets('on the Duo outer display back and home move to the rail', (
    tester,
  ) async {
    useDuoViewport(tester, 'outer portrait');
    final rig = _Rig();
    addTearDown(() async {
      rig.c.dispose();
      await rig.sdk.events.close();
    });
    await rig.c.ready;
    var back = 0;
    var home = 0;
    await tester.pumpWidget(
      duoHost(
        BillingScreen(
          controller: rig.c,
          onBack: () => back++,
          onHome: () => home++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DuoRail), findsOneWidget);
    expect(_key('product_back'), findsNothing);
    await tester.tap(_key('duo_rail_back'));
    await tester.tap(_key('duo_rail_home'));
    expect((back, home), (1, 1));
    // The page stays left of the rail's column.
    expect(tester.getRect(_key('billing_buy')).right, lessThanOrEqualTo(382));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(1024, 768)]) {
    testWidgets('$size at the 1.15x text cap lays out and keeps the terms '
        'whole', (tester) async {
      await _open(tester, size: size, textScale: 1.15);
      await tester.ensureVisible(_key('billing_plan_test.monthly'));
      await _pick(tester, 'test.monthly');
      final terms = _key('billing_terms_test.monthly');
      await tester.ensureVisible(terms);
      await tester.pump();
      expect(
        tester.renderObject<RenderParagraph>(terms).didExceedMaxLines,
        isFalse,
      );
      await tester.ensureVisible(_key('billing_manage_subscription'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
