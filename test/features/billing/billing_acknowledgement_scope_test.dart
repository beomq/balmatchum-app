import 'package:balmatchum_app/features/billing/billing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'billing_fakes.dart';

void main() {
  for (final store in ['apple', 'google']) {
    for (final unrelated in ['other product', 'other store']) {
      test(
        '$store completes when acknowledgement belongs to $unrelated',
        () async {
          // Given a verified purchase and a pending, unrelated purchase.
          final sdk = FakeBillingStore(store: store);
          final server = FakeBillingRepository()
            ..current = config(store: store);
          final controller = BillingController(
            repository: server,
            store: sdk,
            isCurrent: () => true,
          );
          addTearDown(() async {
            controller.dispose();
            await sdk.events.close();
          });
          await controller.ready;
          final pending = view(
            active: true,
            ack: true,
            store: store,
          ).purchases.single;
          if (unrelated == 'other product') {
            pending.productId = 'test.monthly';
          } else {
            pending.store = store == 'apple' ? 'google' : 'apple';
          }
          server.currentView = view(active: true, store: store)
            ..purchases.add(pending);
          final purchased = purchase(store: store);

          // When the store delivers the current purchase.
          sdk.events.add([purchased]);
          await controller.settled.timeout(const Duration(seconds: 2));

          // Then only that purchase is completed, without entering retry.
          expect(sdk.completed, [purchased]);
          expect(controller.phase, BillingPhase.ready);
          expect(controller.errorCode, isNull);
        },
      );
    }
  }
}
