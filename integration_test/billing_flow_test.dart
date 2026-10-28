import 'package:balmatchum_app/features/billing/billing_controller.dart';
import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/billing/billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../test/features/billing/billing_fakes.dart';
import '../test/features/billing/billing_http_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native billing UI with injected SDK and real generated HTTP', (
    tester,
  ) async {
    final harness = await BillingHttpHarness.start();
    final client = harness.client();
    await client.auth.updateSignedInUser(billingTestAuth('1'));
    final queue = BillingRequestQueue();
    final sdk = FakeBillingStore();
    var repository = ServerpodBillingRepository(
      client,
      client.auth.authInfo!.authUserId.toString(),
      queue,
    );
    var c = BillingController(
      repository: repository,
      store: sdk,
      isCurrent: () => repository.isCurrent,
    );

    Future<void> render(
      String name, {
      Brightness brightness = Brightness.light,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: brightness, useMaterial3: true),
          home: BillingScreen(controller: c, onBack: () {}, onHome: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('billing-$name');
      expect(tester.takeException(), isNull);
    }

    await c.ready;
    await render('ready');
    await tester.tap(find.byKey(const ValueKey('billing_buy_test.lifetime')));
    await tester.runAsync(() => c.settled);
    await tester.pump();
    expect(sdk.bought.single.$2, bindingA);
    sdk.events.add([purchase(status: PurchaseStatus.pending)]);
    await tester.runAsync(() => c.settled);
    await render('pending');
    sdk.events.add([purchase(status: PurchaseStatus.canceled)]);
    await tester.runAsync(() => c.settled);
    await render('canceled');

    harness.result = view(active: true, ack: true);
    sdk.events.add([purchase()]);
    await tester.runAsync(() => c.settled);
    expect(sdk.completed, isEmpty);
    await render('approval-retry');
    harness.result = view(active: true);
    await tester.ensureVisible(find.byKey(const ValueKey('billing_retry')));
    await tester.tap(find.byKey(const ValueKey('billing_retry')));
    await tester.runAsync(() => c.settled);
    await render('verified');
    expect(sdk.completed, hasLength(1));

    harness.failure = 'temporarilyUnavailable';
    await tester.runAsync(c.retry);
    expect(c.entitlement, isNull);
    await render('network-failure');
    harness.failure = null;
    sdk.restores = [
      purchase(status: PurchaseStatus.restored),
      purchase(id: '102', status: PurchaseStatus.restored),
    ];
    await tester.runAsync(c.restore);
    await render('restored-dark', brightness: Brightness.dark);
    expect(harness.maximumInFlight, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await client.auth.updateSignedInUser(billingTestAuth('2'));
    repository = ServerpodBillingRepository(
      client,
      client.auth.authInfo!.authUserId.toString(),
      queue,
    );
    sdk.recovery = [purchase()];
    c = BillingController(
      repository: repository,
      store: sdk,
      isCurrent: () => repository.isCurrent,
    );
    await tester.runAsync(() => c.ready);
    expect(c.errorCode, 'accountMismatch');
    await render('old-account-rejected');

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    harness.failure = 'configurationMissing';
    c = BillingController(
      repository: repository,
      store: sdk,
      isCurrent: () => repository.isCurrent,
    );
    await tester.runAsync(() => c.ready);
    expect(c.products, isEmpty);
    await render('unconfigured');

    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    harness.failure = null;
    sdk.isAvailable = false;
    c = BillingController(
      repository: repository,
      store: sdk,
      isCurrent: () => repository.isCurrent,
    );
    await tester.runAsync(() => c.ready);
    await render('store-unavailable');
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await sdk.events.close();
    client.close();
    await harness.close();
  });
}
