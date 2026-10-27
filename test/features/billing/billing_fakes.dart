import 'dart:async';

import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/billing/billing_store.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

const bindingA = '10000000-0000-4000-8000-000000000001';
const bindingB = '10000000-0000-4000-8000-000000000002';

ProductDetails product([String id = 'test.lifetime']) => ProductDetails(
  id: id,
  title: '테스트 평생 구매',
  description: '로컬 QA 상품, 실제 판매 아님',
  price: '€12,34',
  rawPrice: 12.34,
  currencyCode: 'EUR',
);

PurchaseConfiguration config({
  String store = 'apple',
  String binding = bindingA,
}) => PurchaseConfiguration(
  store: store,
  environment: 'sandbox',
  accountBinding: binding,
  products: [
    PurchaseProduct(productId: 'test.lifetime', kind: 'lifetime'),
    PurchaseProduct(productId: 'test.monthly', kind: 'subscription'),
  ],
);

EntitlementView view({
  bool active = false,
  bool ack = false,
  String store = 'apple',
}) => EntitlementView(
  active: active,
  purchases: active
      ? [
          PurchaseView(
            store: store,
            productId: 'test.lifetime',
            kind: 'lifetime',
            state: 'active',
            active: true,
            observedAt: DateTime.utc(2026, 10, 19),
            acknowledgementPending: ack,
          ),
        ]
      : [],
);

PurchaseDetails purchase({
  String id = '101',
  String productId = 'test.lifetime',
  String? binding = bindingA,
  PurchaseStatus status = PurchaseStatus.purchased,
  String store = 'apple',
  bool acknowledged = false,
  bool pending = false,
}) {
  if (store == 'google') {
    final p = GooglePlayPurchaseDetails.fromPurchase(
      PurchaseWrapper(
        orderId: 'order-$id',
        packageName: 'test.local',
        purchaseTime: 1,
        purchaseToken: 'token-$id',
        signature: '',
        products: [productId],
        isAutoRenewing: false,
        originalJson: '{}',
        isAcknowledged: acknowledged,
        obfuscatedAccountId: binding,
        purchaseState: pending
            ? PurchaseStateWrapper.pending
            : PurchaseStateWrapper.purchased,
      ),
    ).single;
    p.status = status;
    return p;
  }
  return SK2PurchaseDetails(
    productID: productId,
    purchaseID: id,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'not-a-transaction-id',
      source: 'app_store',
    ),
    transactionDate: '1',
    status: status,
    appAccountToken: binding,
  );
}

class FakeBillingStore implements BillingStore {
  FakeBillingStore({this.store = 'apple'});
  @override
  final String store;
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  final completed = <PurchaseDetails>[];
  final bought = <(ProductDetails, String)>[];
  final queried = <Set<String>>[];
  List<PurchaseDetails> recovery = [];
  List<PurchaseDetails> restores = [];
  List<ProductDetails> catalog = [product()];
  bool isAvailable = true;
  bool launched = true;
  bool completionFails = false;
  bool restoreFails = false;
  String? restoredBinding;
  Future<bool> Function()? launch;
  @override
  Stream<List<PurchaseDetails>> get purchases => events.stream;
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<ProductDetailsResponse> products(Set<String> ids) async {
    queried.add(ids);
    return ProductDetailsResponse(productDetails: catalog, notFoundIDs: []);
  }

  @override
  Future<bool> buy(ProductDetails product, String binding) async {
    bought.add((product, binding));
    return launch == null ? launched : await launch!();
  }

  @override
  Future<void> restore(String binding) async {
    restoredBinding = binding;
    if (restoreFails) throw StateError('Store unavailable');
    events.add(restores);
  }

  @override
  Future<List<PurchaseDetails>> unfinished() async => recovery;
  @override
  Future<void> complete(PurchaseDetails purchase) async {
    if (completionFails) throw StateError('Completion failed');
    completed.add(purchase);
  }
}

class FakeBillingRepository implements BillingRepository {
  PurchaseConfiguration current = config();
  EntitlementView currentView = view();
  Object? failure;
  final calls = <String>[];
  final inputs = <PurchaseInput>[];
  Future<EntitlementView> Function(PurchaseInput)? verification;
  @override
  Future<PurchaseConfiguration> configuration(String store) async {
    calls.add('configuration');
    if (failure != null) throw failure!;
    return current;
  }

  @override
  Future<EntitlementView> entitlement() async {
    calls.add('entitlement');
    if (failure != null) throw failure!;
    return currentView;
  }

  Future<EntitlementView> _verify(String method, PurchaseInput input) async {
    calls.add(method);
    inputs.add(input);
    if (failure != null) throw failure!;
    return verification == null ? currentView : await verification!(input);
  }

  @override
  Future<EntitlementView> verify(PurchaseInput input) =>
      _verify('verify', input);
  @override
  Future<EntitlementView> restore(PurchaseInput input) =>
      _verify('restore', input);
}
