import 'dart:async';

import 'package:balmatchum_app/features/billing/billing_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'billing_fakes.dart';

class _Platform extends InAppPurchasePlatform {
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  PurchaseParam? parameter;
  final restoreCalled = Completer<void>();
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    parameter = purchaseParam;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalled.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late InAppPurchase sdk;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    sdk = InAppPurchase.instance;
    platform = _Platform();
    InAppPurchasePlatform.instance = platform;
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await platform.events.close();
  });

  for (final store in ['apple', 'google']) {
    test(
      '$store adapter forwards exact server binding through official SDK',
      () async {
        final adapter = NativeBillingStore(store, sdk: sdk);
        final p = product();
        expect(await adapter.buy(p, bindingA), isTrue);
        expect(platform.parameter!.applicationUserName, bindingA);
        expect(platform.parameter!.productDetails, same(p));
        expect(
          platform.parameter,
          store == 'apple'
              ? isA<Sk2PurchaseParam>()
              : isA<GooglePlayPurchaseParam>(),
        );
      },
    );
  }

  test(
    'restore waits for actual stream signal after SDK method return',
    () async {
      final adapter = NativeBillingStore('apple', sdk: sdk);
      var finished = false;
      final restored = adapter.restore(bindingA).then((_) => finished = true);
      await platform.restoreCalled.future;
      expect(finished, isFalse);
      platform.events.add([]);
      await restored;
      expect(finished, isTrue);
    },
  );
}
