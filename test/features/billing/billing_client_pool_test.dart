import 'dart:io';

import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/daily_activity/scoped_client.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'billing_http_harness.dart';

class _RealHttp extends HttpOverrides {}

class _CountingClient extends Client {
  _CountingClient(super.host, {super.connectionTimeout});
  int closeCalls = 0;

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('billing requests share one pooled client and retire it on header '
      'change', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final harness = await BillingHttpHarness.start();
      addTearDown(harness.close);
      final client = harness.client();
      addTearDown(client.close);
      final created = <_CountingClient>[];
      final pool = ScopedClientPool(
        host: client.host,
        connectionTimeout: client.connectionTimeout,
        factory: (host, timeout) {
          final scoped = _CountingClient(host, connectionTimeout: timeout);
          created.add(scoped);
          return scoped;
        },
      );
      addTearDown(pool.close);
      final queue = BillingRequestQueue();

      await client.auth.updateSignedInUser(billingTestAuth('1'));
      final first = ServerpodBillingRepository(
        client,
        client.auth.authInfo!.authUserId.toString(),
        queue,
        pool: pool,
      );
      await first.entitlement();
      await first.entitlement();
      await first.entitlement();

      expect(created, hasLength(1));
      expect(created.single.closeCalls, 0);
      expect(harness.requests, hasLength(3));

      await client.auth.updateSignedInUser(billingTestAuth('2'));
      final second = ServerpodBillingRepository(
        client,
        client.auth.authInfo!.authUserId.toString(),
        queue,
        pool: pool,
      );
      await second.entitlement();

      expect(created, hasLength(2));
      expect(created[0].closeCalls, 1);
      expect(created[1].closeCalls, 0);
      expect(harness.requests.last.$2, 'Bearer local-billing-fixture-2');
    }, _RealHttp());
  });
}
