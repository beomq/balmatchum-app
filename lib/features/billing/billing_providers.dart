import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../../app/dependencies.dart';
import 'billing_controller.dart';
import 'billing_repository.dart';
import 'billing_store.dart';

final billingQueueProvider = Provider((ref) => BillingRequestQueue());

final billingAuthenticationProvider = Provider<AuthSuccess?>((ref) {
  if (serverUrl.isEmpty) return null;
  final auth = ref.watch(clientProvider).auth;
  void changed() => ref.invalidateSelf();
  auth.authInfoListenable.addListener(changed);
  ref.onDispose(() => auth.authInfoListenable.removeListener(changed));
  return auth.authInfo;
});

final billingStoreProvider = Provider<BillingStore?>((ref) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => NativeBillingStore('apple'),
    TargetPlatform.android => NativeBillingStore('google'),
    _ => null,
  };
});

final billingRepositoryProvider = Provider<ServerpodBillingRepository?>((ref) {
  final authentication = ref.watch(billingAuthenticationProvider);
  if (authentication == null) return null;
  return ServerpodBillingRepository(
    ref.watch(clientProvider),
    authentication.authUserId.toString(),
    ref.watch(billingQueueProvider),
  );
});

final billingControllerProvider = Provider<BillingController?>((ref) {
  final repository = ref.watch(billingRepositoryProvider);
  if (repository == null) return null;
  final store = ref.watch(billingStoreProvider);
  if (store == null) return null;
  final controller = BillingController(
    repository: repository,
    store: store,
    isCurrent: () => repository.isCurrent,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
