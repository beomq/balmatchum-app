import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../billing/billing_providers.dart';
import 'product_controller.dart';
import 'product_repository.dart';
import '../watch_sync/watch_bridge.dart';
import 'daily_steps_controller.dart';

final dailyStepsControllerProvider = Provider<DailyStepsController>((ref) {
  final controller = DailyStepsController(
    readSteps: WatchBridge().requestDailySteps,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final productControllerProvider = Provider<ProductController>((ref) {
  final controller = ProductController(
    ProductRepository(ref.watch(clientProvider)),
    ref.watch(dailyStepsControllerProvider),
    ref.watch(watchSyncServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final authenticatedProductControllerProvider = Provider<ProductController?>((
  ref,
) {
  final account = ref.watch(authenticatedAccountProvider);
  if (account == null) return null;
  final client = ref.watch(clientProvider);
  final billing = ref.watch(billingRepositoryProvider);
  final deleted = ref.watch(deletedAccountsProvider);
  final controller = ProductController(
    ProductRepository(
      client,
      accountId: account,
      billing: billing,
      pool: ref.watch(accountClientPoolProvider),
    ),
    ref.watch(dailyStepsControllerProvider),
    ref.watch(watchSyncServiceProvider),
    account: account,
    isCurrentAccount: () =>
        (billing?.isCurrent ?? false) && !deleted.contains(account),
    bootstrap: ref.watch(homeBootstrapProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
