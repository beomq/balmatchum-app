import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../daily_activity/scoped_client.dart';

abstract interface class BillingRepository {
  Future<PurchaseConfiguration> configuration(String store);
  Future<EntitlementView> verify(PurchaseInput input);
  Future<EntitlementView> restore(PurchaseInput input);
  Future<EntitlementView> entitlement();
}

/// Shared across controller lifetimes: even A -> B -> A cannot overlap A's
/// observations. The server sequence is account-wide, not purchase-wide.
class BillingRequestQueue {
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String account, Future<T> Function() action) {
    final result = (_tails[account] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[account] = tail;
    tail.then((_) {
      if (identical(_tails[account], tail)) _tails.remove(account);
    });
    return result;
  }
}

class ServerpodBillingRepository implements BillingRepository {
  ServerpodBillingRepository(
    this.client,
    this.account,
    this.queue, {
    ScopedClientPool? pool,
  }) : pool =
           pool ??
           ScopedClientPool(
             host: client.host,
             connectionTimeout: client.connectionTimeout,
           ),
       _authentication = client.auth.authInfo;

  final Client client;
  final String account;
  final BillingRequestQueue queue;
  final ScopedClientPool pool;
  final AuthSuccess? _authentication;

  void close() => pool.close();

  bool get isCurrent =>
      _authentication != null &&
      _authentication.authUserId.toString() == account &&
      identical(_authentication, client.auth.authInfo);

  // Premium observations and consumption reserve the same server sequence.
  Future<T> request<T>(Future<T> Function(Client) action) =>
      queue.run(account, () async {
        if (!isCurrent) throw StateError('Billing authentication changed');
        final header = await client.auth.authHeaderValue;
        if (header == null || !isCurrent) {
          throw StateError('Billing authentication changed');
        }
        return pool.run(header, _BillingHeader.new, (scoped) async {
          final result = await action(scoped);
          if (!isCurrent) throw StateError('Billing authentication changed');
          return result;
        });
      });

  @override
  Future<PurchaseConfiguration> configuration(String store) =>
      request((c) => c.billing.getPurchaseConfiguration(store));
  @override
  Future<EntitlementView> verify(PurchaseInput input) =>
      request((c) => c.billing.verifyPurchase(input));
  @override
  Future<EntitlementView> restore(PurchaseInput input) =>
      request((c) => c.billing.restorePurchase(input));
  @override
  Future<EntitlementView> entitlement() =>
      request((c) => c.billing.getEntitlement());
}

class _BillingHeader implements ClientAuthKeyProvider {
  _BillingHeader(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}
