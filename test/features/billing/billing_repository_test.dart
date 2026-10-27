import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'billing_fakes.dart';
import 'billing_http_harness.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final method in [
    'getPurchaseConfiguration',
    'verifyPurchase',
    'restorePurchase',
    'getEntitlement',
  ]) {
    test('generated HTTP $method exact payload and captured auth', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final harness = await BillingHttpHarness.start();
        addTearDown(harness.close);
        final client = harness.client();
        addTearDown(client.close);
        await client.auth.updateSignedInUser(billingTestAuth('1'));
        final repository = ServerpodBillingRepository(
          client,
          client.auth.authInfo!.authUserId.toString(),
          BillingRequestQueue(),
        );
        final input = PurchaseInput(
          store: 'apple',
          productId: 'test.lifetime',
          purchaseReference: '101',
        );
        final Object response = switch (method) {
          'getPurchaseConfiguration' => await repository.configuration('apple'),
          'verifyPurchase' => await repository.verify(input),
          'restorePurchase' => await repository.restore(input),
          _ => await repository.entitlement(),
        };
        expect(
          response,
          method == 'getPurchaseConfiguration'
              ? isA<PurchaseConfiguration>()
              : isA<EntitlementView>(),
        );
        final request = harness.requests.single;
        expect(request.$1, method);
        expect(request.$2, 'Bearer local-billing-fixture-1');
        if (method == 'getPurchaseConfiguration') {
          expect(request.$3, {'store': 'apple'});
        } else if (method != 'getEntitlement') {
          final body = request.$3['input'] as Map<String, dynamic>;
          expect(body['store'], 'apple');
          expect(body['productId'], 'test.lifetime');
          expect(body['purchaseReference'], '101');
          expect(body.containsKey('accountBinding'), isFalse);
          expect(body.containsKey('owner'), isFalse);
        }
      }, _RealHttp());
    });
  }

  test(
    'account queue survives repository replacement and fixes auth at send',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final harness = await BillingHttpHarness.start();
        addTearDown(harness.close);
        final client = harness.client();
        addTearDown(client.close);
        await client.auth.updateSignedInUser(billingTestAuth('1'));
        final queue = BillingRequestQueue();
        final account = client.auth.authInfo!.authUserId.toString();
        final first = ServerpodBillingRepository(client, account, queue);
        final input = PurchaseInput(
          store: 'apple',
          productId: 'test.lifetime',
          purchaseReference: '101',
        );
        harness.verificationGate = Completer<void>();
        final arrival = harness.arrivals.stream.first;
        final verifying = first.verify(input);
        final failure = expectLater(verifying, throwsStateError);
        await arrival.timeout(const Duration(seconds: 5));
        await client.auth.updateSignedInUser(billingTestAuth('2'));
        await client.auth.updateSignedInUser(billingTestAuth('1'));
        final next = ServerpodBillingRepository(client, account, queue);
        final queued = next.entitlement();
        expect(harness.requests, hasLength(1));
        harness.verificationGate!.complete();
        await failure;
        await queued;
        expect(harness.maximumInFlight, 1);
        expect(harness.requests.map((r) => r.$1), [
          'verifyPurchase',
          'getEntitlement',
        ]);
        expect(harness.requests.first.$2, 'Bearer local-billing-fixture-1');
        await expectLater(first.entitlement(), throwsStateError);
      }, _RealHttp());
    },
  );

  test(
    'generated BillingException is parsed instead of cached entitlement',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final harness = await BillingHttpHarness.start();
        addTearDown(harness.close);
        final client = harness.client();
        addTearDown(client.close);
        await client.auth.updateSignedInUser(billingTestAuth('1'));
        final repository = ServerpodBillingRepository(
          client,
          client.auth.authInfo!.authUserId.toString(),
          BillingRequestQueue(),
        );
        harness.result = view(active: true);
        expect((await repository.entitlement()).active, isTrue);
        harness.failure = 'configurationMissing';
        await expectLater(
          repository.entitlement(),
          throwsA(
            isA<BillingException>().having(
              (e) => e.code,
              'code',
              'configurationMissing',
            ),
          ),
        );
      }, _RealHttp());
    },
  );
}
