import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_repository.dart';
import 'billing_store.dart';

enum BillingPhase {
  loading,
  ready,
  purchasing,
  pending,
  verifying,
  canceled,
  retry,
  unavailable,
}

class BillingController extends ChangeNotifier {
  BillingController({
    required this.repository,
    required this.store,
    required this.isCurrent,
  }) {
    // Queue initialization before subscribing; startup redelivery waits for the
    // allowlist and binding, but the stream is attached before any native await.
    ready = _enqueue(_load);
    _subscription = store.purchases.listen(
      _received,
      onError: (Object _) {
        if (_current) _fail('storeUnavailable');
      },
    );
  }

  final BillingRepository repository;
  final BillingStore store;
  final bool Function() isCurrent;
  late final Future<void> ready;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  Future<void> _tail = Future<void>.value();
  final _retry = <String, PurchaseDetails>{};
  final _pendingProducts = <String>{};
  bool _disposed = false;
  bool _restoring = false;
  String? _restoreFailure;
  bool _command = false;
  String? _attemptProduct;
  PurchaseConfiguration? configuration;
  List<ProductDetails> products = [];
  EntitlementView? entitlement;
  BillingPhase phase = BillingPhase.loading;
  String? errorCode;

  bool get _current => !_disposed && isCurrent();
  bool get busy =>
      _command ||
      switch (phase) {
        BillingPhase.loading ||
        BillingPhase.purchasing ||
        BillingPhase.verifying => true,
        _ => false,
      };
  bool get acknowledgementPending =>
      entitlement?.purchases.any((p) => p.acknowledgementPending) ?? false;
  bool get canBuy =>
      _current &&
      !busy &&
      phase != BillingPhase.pending &&
      errorCode == null &&
      !acknowledgementPending &&
      _retry.isEmpty &&
      _pendingProducts.isEmpty;
  Future<void> get settled => _tail;

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) async {
      if (!_current) return;
      try {
        await action();
      } on BillingException catch (error) {
        if (!_current) return;
        _fail(error.code);
        // Exactly one fresh observation; no automatic verification loop.
        if (error.code == 'staleObservation') {
          try {
            final fresh = await repository.entitlement();
            if (_current) {
              entitlement = fresh;
              _notify();
            }
          } on Object {
            if (_current) _fail('temporarilyUnavailable');
          }
        }
      } on Object {
        if (_current) _fail('temporarilyUnavailable');
      }
    });
    _tail = result;
    return result;
  }

  void _notify() {
    if (_current) notifyListeners();
  }

  void _fail(String code) {
    if (_restoring) _restoreFailure ??= code;
    entitlement = null;
    errorCode = code;
    phase = code == 'configurationMissing' || code == 'storeUnavailable'
        ? BillingPhase.unavailable
        : BillingPhase.retry;
    _notify();
  }

  Future<void> _load() async {
    phase = BillingPhase.loading;
    configuration = null;
    errorCode = null;
    entitlement = null;
    products = [];
    _notify();
    final config = await repository.configuration(store.store);
    if (!_current) return;
    if (config.store != store.store ||
        config.accountBinding.isEmpty ||
        config.products.isEmpty ||
        config.products.any(
          (p) =>
              p.productId.isEmpty ||
              (p.kind != 'subscription' && p.kind != 'lifetime'),
        )) {
      _fail('configurationMissing');
      return;
    }
    configuration = config;
    if (!await store.available()) {
      if (_current) _fail('storeUnavailable');
      return;
    }
    if (!_current) return;
    final ids = config.products.map((p) => p.productId).toSet();
    final response = await store.products(ids);
    if (!_current) return;
    if (response.error != null) {
      _fail('storeUnavailable');
      return;
    }
    products = response.productDetails
        .where((p) => ids.contains(p.id))
        .toList();
    await _refresh();
    if (!_current) return;
    if (products.isEmpty) _fail('productsUnavailable');
    for (final purchase in await store.unfinished()) {
      if (!_current) return;
      await _process(purchase);
    }
  }

  Future<void> _refresh() async {
    entitlement = null;
    _notify();
    final fresh = await repository.entitlement();
    if (!_current) return;
    entitlement = fresh;
    errorCode = fresh.purchases.any((p) => p.acknowledgementPending)
        ? 'acknowledgementPending'
        : null;
    phase = errorCode != null
        ? BillingPhase.retry
        : _pendingProducts.isNotEmpty
        ? BillingPhase.pending
        : BillingPhase.ready;
    _notify();
  }

  Future<void> buy(ProductDetails product) async {
    if (!canBuy || !products.contains(product)) return;
    final config = configuration!;
    _command = true;
    phase = BillingPhase.purchasing;
    errorCode = null;
    _notify();
    try {
      await _enqueue(() async {
        // Configuration is checked again at the purchase boundary.
        final fresh = await repository.configuration(store.store);
        if (!_current) return;
        if (fresh.accountBinding != config.accountBinding ||
            !fresh.products.any((p) => p.productId == product.id)) {
          _fail('configurationMissing');
          return;
        }
        _attemptProduct = product.id;
        if (!await store.buy(product, config.accountBinding) && _current) {
          _fail('storeUnavailable');
        }
      });
    } finally {
      _command = false;
      _notify();
    }
  }

  void _received(List<PurchaseDetails> purchases) {
    if (!_current) return;
    for (final purchase in purchases) {
      unawaited(_enqueue(() => _process(purchase)));
    }
  }

  Future<void> _process(PurchaseDetails purchase) async {
    final config = configuration;
    if (config == null || !_current) return;
    // Cancellation/error callbacks may lack product and account fields. They
    // never verify or finish anything and cannot confer an entitlement.
    if (purchase.status == PurchaseStatus.canceled ||
        purchase.status == PurchaseStatus.error) {
      if (phase == BillingPhase.purchasing || phase == BillingPhase.pending) {
        _pendingProducts.remove(_attemptProduct ?? purchase.productID);
        _attemptProduct = null;
        entitlement = null;
        phase = purchase.status == PurchaseStatus.canceled
            ? BillingPhase.canceled
            : BillingPhase.retry;
        errorCode = purchase.status == PurchaseStatus.error
            ? 'storeUnavailable'
            : null;
        _notify();
      }
      return;
    }
    // StoreKit pending has no transaction or appAccountToken yet. It can only
    // update the in-flight UI for this session's exact attempted product.
    if (purchaseIsPending(purchase) &&
        purchaseBinding(purchase) == null &&
        _attemptProduct == purchase.productID) {
      _pendingProducts.add(purchase.productID);
      entitlement = null;
      phase = BillingPhase.pending;
      errorCode = null;
      _notify();
      return;
    }
    if (purchaseBinding(purchase)?.toLowerCase() !=
        config.accountBinding.toLowerCase()) {
      _fail('accountMismatch');
      return;
    }
    if (!config.products.any((p) => p.productId == purchase.productID)) {
      _fail('invalidPurchase');
      return;
    }
    if (purchaseIsPending(purchase)) {
      _pendingProducts.add(purchase.productID);
      entitlement = null;
      phase = BillingPhase.pending;
      errorCode = null;
      _notify();
      return;
    }
    final reference = purchaseReference(purchase, store.store);
    if (reference == null || reference.isEmpty) {
      _fail('invalidPurchase');
      return;
    }
    _retry[reference] = purchase;
    _pendingProducts.remove(purchase.productID);
    entitlement = null;
    phase = BillingPhase.verifying;
    errorCode = null;
    _notify();
    final input = PurchaseInput(
      store: store.store,
      productId: purchase.productID,
      purchaseReference: reference,
    );
    final result = purchase.status == PurchaseStatus.restored
        ? await repository.restore(input)
        : await repository.verify(input);
    if (!_current) return;
    entitlement = result;
    if (store.store == 'google' &&
        !result.purchases.any(
          (p) =>
              p.store == 'google' &&
              p.productId == purchase.productID &&
              p.active,
        )) {
      phase = BillingPhase.retry;
      errorCode = 'purchaseNotActive';
      _notify();
      return;
    }
    if (result.purchases.any((p) => p.acknowledgementPending)) {
      phase = BillingPhase.retry;
      errorCode = 'acknowledgementPending';
      _notify();
      return;
    }
    // A restored StoreKit2 detail reports pendingCompletePurchase=false even
    // when the original transaction was unfinished. Finishing its verified ID
    // is idempotent, so restore must also reach this branch.
    if (purchase.pendingCompletePurchase || store.store == 'apple') {
      await store.complete(purchase);
      if (!_current) return;
    }
    _retry.remove(reference);
    _attemptProduct = null;
    phase = BillingPhase.ready;
    _notify();
  }

  Future<void> retry() async {
    if (busy || !_current) return;
    _command = true;
    _notify();
    try {
      await _enqueue(() async {
        if (configuration == null ||
            products.isEmpty ||
            errorCode == 'configurationMissing' ||
            errorCode == 'storeUnavailable') {
          await _load();
          return;
        }
        for (final purchase in _retry.values.toList()) {
          if (!_current) return;
          await _process(purchase);
          if (errorCode != null) return;
        }
        if (_current) await _refresh();
      });
    } finally {
      _command = false;
      _notify();
    }
  }

  Future<void> restore() async {
    if (busy || _restoring || configuration == null || !_current) return;
    _restoring = true;
    _restoreFailure = null;
    _command = true;
    entitlement = null;
    errorCode = null;
    phase = BillingPhase.verifying;
    _notify();
    try {
      await _enqueue(() => store.restore(configuration!.accountBinding));
      // Stream callbacks enqueue each purchase before the SDK restore future
      // resolves. Queue the final fresh observation behind those verifications.
      await _enqueue(() async {
        if (_restoreFailure != null) {
          _fail(_restoreFailure!);
        } else if (errorCode == null && phase != BillingPhase.pending) {
          await _refresh();
        }
      });
    } finally {
      _restoring = false;
      _command = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    entitlement = null;
    _retry.clear();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
