import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

/// Walks the wardrobe against a running local server (see docs/WARDROBE.md):
/// phase \`buy\` buys an item, the winter set at its set price, wears it, and
/// receives this month's gift as a member; phase \`kept\` runs after the
/// subscription ended and wears the gift again.
const phase = String.fromEnvironment('WARDROBE_PHASE', defaultValue: 'buy');

class _MemoryStore implements FirstMeetingStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String payload) async => value = payload;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> until(
    WidgetTester tester,
    bool Function() done, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('wardrobe_scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await frames(tester);
    await tester.tap(finder);
    await frames(tester);
  }

  Future<void> top(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('wardrobe_scroll')),
      const Offset(0, 4000),
    );
    await frames(tester);
  }

  String balance(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('wardrobe_balance'))).data!;

  testWidgets('wardrobe walk-through: $phase', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final client = container.read(clientProvider);
    expect(await importDevTestSession(client), isTrue);
    final account = client.auth.authInfo!.authUserId.toString();
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final product = ProductController(
      ProductRepository(client, accountId: account),
      steps,
      null,
      account: account,
    );
    addTearDown(() {
      product.dispose();
      steps.dispose();
    });

    if (phase == 'home') {
      // A wardrobe purchase must show on the home wallet without a refresh.
      final meeting = FirstMeetingController(storage: _MemoryStore());
      addTearDown(meeting.dispose);
      await meeting.initialize();
      await meeting.enter();
      await meeting.chooseMethod(FirstMeetingMethod.catalog);
      await meeting.selectBreed('maltese');
      await meeting.confirmCandidate();
      await meeting.updateName('보리');
      await meeting.updateSex(DogSex.female);
      await meeting.submitName();
      await meeting.complete();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: meetingTheme(),
          home: FirstMeetingScreen(
            controller: meeting,
            product: product,
            onOpenWardrobe: () => navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => WardrobeScreen(
                  dog: FirstMeetingCatalog.byId('maltese'),
                  cachedStore: product.wardrobeStore,
                  loadWardrobe: product.loadWardrobe,
                  runAction: product.wardrobeAction,
                  onBack: () => navigator.currentState!.pop(),
                  onHome: () => navigator.currentState!.pop(),
                ),
              ),
            ),
          ),
        ),
      );
      final wallet = find.byKey(const ValueKey('reward_wallet'));
      await until(tester, () => wallet.evaluate().isNotEmpty);
      await frames(tester);
      String home() => tester.widget<Text>(wallet).data!;
      expect(home(), '1,000P');
      await binding.takeScreenshot('wardrobe-08-home-before');

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => WardrobeScreen(
            dog: FirstMeetingCatalog.byId('maltese'),
            loadWardrobe: product.loadWardrobe,
            runAction: product.wardrobeAction,
            onBack: () => navigator.currentState!.pop(),
            onHome: () => navigator.currentState!.pop(),
          ),
        ),
      );
      await until(tester, () => product.wardrobeStore != null);
      await frames(tester);
      await tapKey(tester, 'wardrobe_tab_items');
      await tapKey(tester, 'wardrobe_item_action_padding');
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
      await until(tester, () => product.wardrobeStore!.balance == 850);
      navigator.currentState!.pop();
      await frames(tester);
      await frames(tester);

      expect(home(), '850P');
      await binding.takeScreenshot('wardrobe-09-home-after-buy');
      return;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: WardrobeScreen(
          dog: FirstMeetingCatalog.byId('maltese'),
          loadWardrobe: product.loadWardrobe,
          runAction: product.wardrobeAction,
          onSubscribe: () async {},
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await until(tester, () => product.wardrobeStore != null);
    await frames(tester);

    if (phase == 'buy') {
      expect(product.wardrobeStore!.subscriber, isTrue);
      expect(balance(tester), '1,000P');
      await binding.takeScreenshot('wardrobe-01-sets');

      // One item in one colour: 150P.
      await tapKey(tester, 'wardrobe_tab_items');
      await tapKey(tester, 'wardrobe_item_action_padding');
      await binding.takeScreenshot('wardrobe-02-buy-item-confirm');
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
      await until(
        tester,
        () => product.wardrobeStore!.items
            .singleWhere((i) => i.itemId == 'padding')
            .ownedColours
            .contains('tomato'),
      );
      await top(tester);
      expect(balance(tester), '850P');
      await binding.takeScreenshot('wardrobe-03-item-bought');

      // The set, 20% off the parts still missing: (150 x 2 + 100) x 0.8.
      await top(tester);
      await tapKey(tester, 'wardrobe_tab_sets');
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('wardrobe_set_price_winter')),
            )
            .data,
        '320P',
      );
      await tapKey(tester, 'wardrobe_set_action_winter');
      await binding.takeScreenshot('wardrobe-04-buy-set-confirm');
      await tester.tap(find.byKey(const ValueKey('wardrobe_purchase_confirm')));
      await until(
        tester,
        () => product.wardrobeStore!.backgrounds
            .singleWhere((b) => b.backgroundId == 'winter-dusk')
            .owned,
      );
      await frames(tester);
      expect(product.wardrobeStore!.balance, 530);

      // Wear the whole set: band and snow.
      await tapKey(tester, 'wardrobe_set_action_winter');
      await until(tester, () => product.wardrobeStore!.completeSetId != null);
      await top(tester);
      expect(
        find.byKey(const ValueKey('wardrobe_set_complete')),
        findsOneWidget,
      );
      await binding.takeScreenshot('wardrobe-05-set-complete');

      // This month's gift, free for a member, in every colour.
      await tapKey(tester, 'wardrobe_set_action_holiday');
      await until(
        tester,
        () =>
            product.wardrobeStore!.sets
                .singleWhere((s) => s.setId == 'holiday')
                .season
                ?.granted ??
            false,
      );
      await frames(tester);
      expect(product.wardrobeStore!.balance, 530);
      expect(
        product.wardrobeStore!.items
            .singleWhere((i) => i.itemId == 'santa-cape')
            .ownedColours,
        hasLength(3),
      );
      await binding.takeScreenshot('wardrobe-06-gift-received');
    } else {
      // After the subscription ended the gift stays and can be worn.
      expect(product.wardrobeStore!.subscriber, isFalse);
      await tapKey(tester, 'wardrobe_set_colour_holiday_navy');
      await tapKey(tester, 'wardrobe_set_action_holiday');
      await until(
        tester,
        () => product.wardrobeStore!.completeSetId == 'holiday',
      );
      await top(tester);
      expect(find.text('크리스마스 세트 완성'), findsOneWidget);
      await binding.takeScreenshot('wardrobe-07-kept-after-unsubscribe');
    }
  });
}
