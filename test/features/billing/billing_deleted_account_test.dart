import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/billing/billing_providers.dart';
import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/daily_activity/home_bootstrap.dart';
import 'package:balmatchum_app/features/daily_activity/scoped_client.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'billing_fakes.dart';

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async => value = data;
}

/// Billing whose auth still looks current, as it does when the sign-out after
/// a deletion never ran; every server request it is asked for is recorded.
class _CurrentBilling extends ServerpodBillingRepository {
  _CurrentBilling(Client client) : super(client, 'A', BillingRequestQueue());
  final server = FakeBillingRepository();
  @override
  bool get isCurrent => true;
  @override
  Future<PurchaseConfiguration> configuration(String store) =>
      server.configuration(store);
  @override
  Future<EntitlementView> entitlement() => server.entitlement();
  @override
  Future<EntitlementView> verify(PurchaseInput input) => server.verify(input);
  @override
  Future<EntitlementView> restore(PurchaseInput input) => server.restore(input);
}

const _host = 'http://localhost:1/';

void main() {
  late Client client;
  late ScopedClientPool pool;
  late _CurrentBilling billing;
  late FakeBillingStore store;

  setUp(() {
    client = Client(_host)
      ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
    pool = ScopedClientPool(host: _host);
    billing = _CurrentBilling(client);
    store = FakeBillingStore();
  });

  tearDown(() async {
    await store.events.close();
    billing.close();
    pool.close();
    client.close();
  });

  /// Account A signed in, with the app's own deletion and billing wiring.
  ProviderContainer signedIn() {
    final container = ProviderContainer(
      overrides: [
        authenticatedAccountProvider.overrideWithValue('A'),
        clientProvider.overrideWithValue(client),
        accountClientPoolProvider.overrideWithValue(pool),
        homeBootstrapProvider.overrideWithValue(HomeBootstrap()),
        billingRepositoryProvider.overrideWithValue(billing),
        billingStoreProvider.overrideWithValue(store),
        logoutProvider.overrideWithValue(
          () async => throw StateError('sign-out is not reached'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('after the server deleted the account, billing sends nothing', () async {
    final container = signedIn();
    final controller = container.read(billingControllerProvider)!;
    await controller.ready;
    expect(controller.canBuy, isTrue);
    final before = List.of(billing.server.calls);

    // The deletion flow forgets the account before the steps that may still
    // fail; billing's own auth is untouched by that.
    container.read(accountDeletionProvider)!.forgetAccount();

    final canBuy = controller.canBuy;
    await controller.buy(controller.products.single);
    // A purchase the store delivers late for the deleted account.
    store.events.add([purchase()]);
    await controller.settled;

    debugPrint(
      'deleted: canBuy=$canBuy calls=${billing.server.calls} '
      'bought=${store.bought.length}',
    );
    expect(canBuy, isFalse);
    expect(billing.server.calls, before);
    expect(store.bought, isEmpty);
  });

  test('without a deletion the same account still buys', () async {
    final container = signedIn();
    final controller = container.read(billingControllerProvider)!;
    await controller.ready;
    final before = List.of(billing.server.calls);

    await controller.buy(controller.products.single);
    await controller.settled;

    debugPrint(
      'control: calls=${billing.server.calls} bought=${store.bought.length}',
    );
    expect(billing.server.calls, [...before, 'configuration']);
    expect(store.bought.single.$2, bindingA);
  });
}
