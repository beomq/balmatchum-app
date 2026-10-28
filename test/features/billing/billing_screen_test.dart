import 'package:balmatchum_app/features/billing/billing_controller.dart';
import 'package:balmatchum_app/features/billing/billing_screen.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_fakes.dart';

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
            home: BillingScreen(controller: c),
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
}
