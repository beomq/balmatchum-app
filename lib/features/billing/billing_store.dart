import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

abstract interface class BillingStore {
  String get store;
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> available();
  Future<ProductDetailsResponse> products(Set<String> ids);
  Future<bool> buy(ProductDetails product, String binding);
  Future<void> restore(String binding);
  Future<List<PurchaseDetails>> unfinished();
  Future<void> complete(PurchaseDetails purchase);
}

/// Only SDK-originated ownership metadata is used to route events locally.
/// It is not proof: the server independently validates the store's binding.
String? purchaseBinding(PurchaseDetails purchase) => switch (purchase) {
  SK2PurchaseDetails() => purchase.appAccountToken,
  GooglePlayPurchaseDetails() =>
    purchase.billingClientPurchase.obfuscatedAccountId,
  _ => null,
};

String? purchaseReference(PurchaseDetails purchase, String store) =>
    switch ((store, purchase)) {
      ('apple', SK2PurchaseDetails(:final purchaseID)) => purchaseID,
      ('google', GooglePlayPurchaseDetails(:final billingClientPurchase)) =>
        billingClientPurchase.purchaseToken,
      _ => null,
    };

bool purchaseIsPending(PurchaseDetails purchase) =>
    purchase.status == PurchaseStatus.pending ||
    (purchase is GooglePlayPurchaseDetails &&
        purchase.billingClientPurchase.purchaseState ==
            PurchaseStateWrapper.pending);

class NativeBillingStore implements BillingStore {
  NativeBillingStore(this.store, {InAppPurchase? sdk})
    : _sdk = sdk ?? InAppPurchase.instance;
  @override
  final String store;
  final InAppPurchase _sdk;

  @override
  Stream<List<PurchaseDetails>> get purchases => _sdk.purchaseStream;
  @override
  Future<bool> available() => _sdk.isAvailable();
  @override
  Future<ProductDetailsResponse> products(Set<String> ids) =>
      _sdk.queryProductDetails(ids);
  @override
  Future<bool> buy(ProductDetails product, String binding) =>
      _sdk.buyNonConsumable(
        purchaseParam: store == 'apple'
            ? Sk2PurchaseParam(
                productDetails: product,
                applicationUserName: binding,
              )
            : GooglePlayPurchaseParam(
                productDetails: product,
                applicationUserName: binding,
              ),
      );
  @override
  Future<void> restore(String binding) async {
    // Native StoreKit sends its callback on a separate channel from the method
    // return. Await the batch signal too, including an empty restore result.
    final batch = Completer<void>();
    final subscription = purchases.listen(
      (items) {
        if (!batch.isCompleted &&
            (items.isEmpty ||
                items.any((p) => p.status == PurchaseStatus.restored))) {
          batch.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!batch.isCompleted) batch.completeError(error, stack);
      },
    );
    try {
      await Future.wait([
        batch.future.timeout(const Duration(seconds: 30)),
        _sdk.restorePurchases(applicationUserName: binding),
      ], eagerError: true);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<List<PurchaseDetails>> unfinished() async {
    if (store == 'google') {
      final response = await _sdk
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .queryPastPurchases();
      if (response.error != null) throw StateError('Store recovery failed');
      return response.pastPurchases;
    }
    // Unlike AppStore.sync, unfinished does not ask for an Apple sign-in.
    return (await SK2Transaction.unfinishedTransactions())
        .map(
          (t) => SK2PurchaseDetails(
            productID: t.productId,
            purchaseID: t.id,
            verificationData: PurchaseVerificationData(
              localVerificationData: '',
              serverVerificationData: '',
              source: 'app_store',
            ),
            transactionDate: t.purchaseDate,
            status: PurchaseStatus.purchased,
            appAccountToken: t.appAccountToken,
          ),
        )
        .toList();
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async {
    if (store == 'google') {
      // The generic facade discards BillingResultWrapper. Check it explicitly
      // so a rejected acknowledgement is never treated as completion.
      final result =
          await (InAppPurchasePlatform.instance as InAppPurchaseAndroidPlatform)
              .completePurchase(purchase);
      if (result.responseCode != BillingResponse.ok) {
        throw StateError('Store completion failed');
      }
    } else {
      await _sdk.completePurchase(purchase);
    }
  }
}
