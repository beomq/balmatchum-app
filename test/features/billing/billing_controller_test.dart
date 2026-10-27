import 'dart:async';

import 'package:balmatchum_app/features/billing/billing_controller.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_fakes.dart';

void main() {
  late FakeBillingStore sdk;
  late FakeBillingRepository server;
  late BillingController controller;
  var current = true;

  Future<void> start({String store = 'apple'}) async {
    current = true;
    sdk = FakeBillingStore(store: store);
    server = FakeBillingRepository()..current = config(store: store);
    controller = BillingController(
      repository: server,
      store: sdk,
      isCurrent: () => current,
    );
    addTearDown(() async {
      controller.dispose();
      await sdk.events.close();
    });
    await controller.ready;
  }

  test(
    'allowlist only, localized price and server UUID purchase parameter',
    () async {
      await start();
      expect(sdk.queried.single, {'test.lifetime', 'test.monthly'});
      expect(controller.products.single.price, '€12,34');
      await controller.buy(product('wrong'));
      expect(sdk.bought, isEmpty);
      await controller.buy(controller.products.single);
      expect(sdk.bought.single.$2, bindingA);
      expect(controller.phase, BillingPhase.purchasing);
    },
  );

  for (final store in ['apple', 'google']) {
    test(
      '$store verification finishes before completion, repeated delivery rechecks',
      () async {
        await start(store: store);
        final entered = Completer<void>();
        final release = Completer<EntitlementView>();
        server.verification = (_) {
          entered.complete();
          return release.future;
        };
        sdk.events.add([purchase(store: store)]);
        await entered.future;
        expect(sdk.completed, isEmpty);
        expect(controller.entitlement, isNull);
        expect(
          server.inputs.single.purchaseReference,
          store == 'apple' ? '101' : 'token-101',
        );
        release.complete(view(active: true, store: store));
        await controller.settled;
        expect(sdk.completed, hasLength(1));
        server.verification = null;
        server.currentView = view(active: true, store: store);
        sdk.events.add([purchase(store: store)]);
        await controller.settled;
        expect(server.inputs, hasLength(2));
      },
    );
  }

  test('two purchases and refresh never overlap verification', () async {
    await start();
    final entered = Completer<void>();
    final release = Completer<EntitlementView>();
    server.verification = (input) {
      if (input.purchaseReference == '101') {
        entered.complete();
        return release.future;
      }
      return Future.value(view(active: true));
    };
    sdk.events.add([purchase(), purchase(id: '102')]);
    await entered.future;
    await controller.retry();
    expect(server.inputs, hasLength(1));
    release.complete(view(active: true));
    await controller.settled;
    expect(server.inputs.map((p) => p.purchaseReference), ['101', '102']);
  });

  test(
    'account switch during verify neither completes nor shows old entitlement',
    () async {
      await start();
      final entered = Completer<void>();
      final release = Completer<EntitlementView>();
      server.verification = (_) {
        entered.complete();
        return release.future;
      };
      sdk.events.add([purchase()]);
      await entered.future;
      current = false;
      release.complete(view(active: true));
      await controller.settled;
      expect(sdk.completed, isEmpty);
      expect(controller.entitlement, isNull);
    },
  );

  test(
    'old account, missing binding and wrong product never reach server',
    () async {
      await start();
      for (final p in [
        purchase(binding: bindingB),
        purchase(binding: null),
        purchase(productId: 'wrong'),
      ]) {
        sdk.events.add([p]);
        await controller.settled;
        expect(controller.entitlement, isNull);
      }
      expect(server.inputs, isEmpty);
      expect(sdk.completed, isEmpty);
    },
  );

  test('pending cancel error never verify or finish', () async {
    await start();
    sdk.events.add([purchase(status: PurchaseStatus.pending)]);
    await controller.settled;
    expect(controller.phase, BillingPhase.pending);
    await controller.retry();
    expect(controller.phase, BillingPhase.pending);
    expect(controller.canBuy, isFalse);
    sdk.events.add([purchase(status: PurchaseStatus.canceled)]);
    await controller.settled;
    expect(controller.phase, BillingPhase.canceled);
    await controller.buy(controller.products.single);
    sdk.events.add([purchase(status: PurchaseStatus.error)]);
    await controller.settled;
    expect(controller.phase, BillingPhase.retry);
    expect(server.inputs, isEmpty);
    expect(sdk.completed, isEmpty);
  });

  test(
    'Google pending masked by SDK restore status still never verifies',
    () async {
      await start(store: 'google');
      sdk.events.add([
        purchase(
          store: 'google',
          pending: true,
          status: PurchaseStatus.restored,
        ),
      ]);
      await controller.settled;
      expect(controller.phase, BillingPhase.pending);
      expect(server.inputs, isEmpty);
    },
  );

  test('StoreKit pending without transaction binding only updates own attempted product', () async {
    await start();
    await controller.buy(controller.products.single);
    sdk.events.add([purchase(binding: null, status: PurchaseStatus.pending)]);
    await controller.settled;
    expect(controller.phase, BillingPhase.pending);
    expect(server.inputs, isEmpty);
    expect(sdk.completed, isEmpty);
    sdk.events.add([
      purchase(
        binding: null,
        productId: 'other',
        status: PurchaseStatus.pending,
      ),
    ]);
    await controller.settled;
    expect(controller.errorCode, 'accountMismatch');
  });

  test(
    'acknowledgementPending remains explicitly retryable without completion',
    () async {
      await start(store: 'google');
      server.currentView = view(active: true, ack: true, store: 'google');
      sdk.events.add([purchase(store: 'google')]);
      await controller.settled;
      expect(controller.errorCode, 'acknowledgementPending');
      expect(controller.canBuy, isFalse);
      expect(sdk.completed, isEmpty);
      server.currentView = view(active: true, store: 'google');
      await controller.retry();
      expect(server.inputs, hasLength(2));
      expect(sdk.completed, hasLength(1));
      expect(controller.errorCode, isNull);
    },
  );

  test(
    'inactive Google result is never acknowledged or consumed locally',
    () async {
      await start(store: 'google');
      sdk.events.add([purchase(store: 'google')]);
      await controller.settled;
      expect(controller.errorCode, 'purchaseNotActive');
      expect(sdk.completed, isEmpty);
      expect(controller.canBuy, isFalse);
    },
  );

  test('HTTP failure drops cached entitlement, retry preserves original transaction', () async {
    await start();
    server.currentView = view(active: true);
    await controller.retry();
    expect(controller.entitlement!.active, isTrue);
    server.failure = BillingException(code: 'temporarilyUnavailable');
    sdk.events.add([purchase()]);
    await controller.settled;
    expect(controller.entitlement, isNull);
    expect(sdk.completed, isEmpty);
    server.failure = null;
    await controller.retry();
    expect(server.inputs.map((p) => p.purchaseReference), ['101', '101']);
    expect(sdk.completed, hasLength(1));
  });

  test('completion failure re-verifies on explicit retry', () async {
    await start();
    sdk.completionFails = true;
    sdk.events.add([purchase()]);
    await controller.settled;
    expect(controller.entitlement, isNull);
    sdk.completionFails = false;
    await controller.retry();
    expect(server.inputs, hasLength(2));
    expect(sdk.completed, hasLength(1));
  });

  test(
    'restore serially verifies each transaction then fetches fresh entitlement',
    () async {
      await start();
      sdk.restores = [
        purchase(status: PurchaseStatus.restored),
        purchase(id: '102', status: PurchaseStatus.restored),
      ];
      server.calls.clear();
      await controller.restore();
      await controller.settled;
      expect(server.calls, ['restore', 'restore', 'entitlement']);
      expect(sdk.completed, hasLength(2));
      expect(sdk.restoredBinding, bindingA);
    },
  );

  test(
    'restart recovers unfinished transactions with original binding',
    () async {
      sdk = FakeBillingStore()
        ..recovery = [purchase(), purchase(binding: bindingB)];
      server = FakeBillingRepository();
      controller = BillingController(
        repository: server,
        store: sdk,
        isCurrent: () => true,
      );
      addTearDown(() async {
        controller.dispose();
        await sdk.events.close();
      });
      await controller.ready;
      expect(server.inputs, hasLength(1));
      expect(sdk.completed, hasLength(1));
      expect(controller.errorCode, 'accountMismatch');
    },
  );

  test(
    'mixed restore preserves failure even if a later purchase succeeds',
    () async {
      await start();
      sdk.restores = [
        purchase(binding: bindingB, status: PurchaseStatus.restored),
        purchase(status: PurchaseStatus.restored),
      ];
      server.currentView = view(active: true);
      await controller.restore();
      expect(controller.errorCode, 'accountMismatch');
      expect(controller.entitlement, isNull);
      expect(sdk.completed, hasLength(1));
    },
  );

  test(
    'restored Google pending is not replaced by empty fresh success',
    () async {
      await start(store: 'google');
      sdk.restores = [
        purchase(
          store: 'google',
          pending: true,
          status: PurchaseStatus.restored,
        ),
      ];
      await controller.restore();
      expect(controller.phase, BillingPhase.pending);
      expect(controller.entitlement, isNull);
      expect(sdk.completed, isEmpty);
    },
  );

  for (final failure in ['configurationMissing', 'storeUnavailable']) {
    test('$failure fails closed without a placeholder price', () async {
      sdk = FakeBillingStore()..isAvailable = failure != 'storeUnavailable';
      server = FakeBillingRepository();
      if (failure == 'configurationMissing') {
        server.failure = BillingException(code: failure);
      }
      controller = BillingController(
        repository: server,
        store: sdk,
        isCurrent: () => true,
      );
      addTearDown(() async {
        controller.dispose();
        await sdk.events.close();
      });
      await controller.ready;
      expect(controller.products, isEmpty);
      expect(controller.entitlement, isNull);
      expect(controller.errorCode, failure);
      expect(sdk.bought, isEmpty);
    });
  }

  test(
    'stale observation makes exactly one fresh query without retry loop',
    () async {
      await start();
      server.verification = (_) async =>
          throw BillingException(code: 'staleObservation');
      server.calls.clear();
      sdk.events.add([purchase()]);
      await controller.settled;
      expect(server.calls, ['verify', 'entitlement']);
      expect(sdk.completed, isEmpty);
      expect(controller.phase, BillingPhase.retry);
    },
  );
}
