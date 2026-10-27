import 'dart:async';

import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const config = MethodChannel('balmatchum/ads_config');
  final ads = MethodChannel(
    'plugins.flutter.io/google_mobile_ads',
    StandardMethodCodec(AdMessageCodec()),
  );
  final ump = MethodChannel(
    'plugins.flutter.io/google_mobile_ads/ump',
    StandardMethodCodec(UserMessagingCodec()),
  );
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(config, null);
    messenger.setMockMethodCallHandler(ads, null);
    messenger.setMockMethodCallHandler(ump, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('missing native metadata never invokes Google SDK', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(config, (_) async => '');
    messenger.setMockMethodCallHandler(ads, (call) async {
      calls.add(call.method);
      return null;
    });
    expect(await GoogleAdsSdk().prepare(), AdsSetup.missingConfiguration);
    expect(calls, isEmpty);
  });

  test(
    'UMP gathers consent before initialize and blocks denied consent',
    () async {
      final events = <String>[];
      var allowed = false;
      messenger.setMockMethodCallHandler(
        config,
        (_) async => 'ca-app-pub-1234567890123456~1234567890',
      );
      messenger.setMockMethodCallHandler(ump, (call) async {
        events.add(call.method);
        if (call.method.endsWith('canRequestAds')) return allowed;
        if (call.method.endsWith('getPrivacyOptionsRequirementStatus')) {
          return 0;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(ads, (call) async {
        events.add(call.method);
        if (call.method == 'MobileAds#initialize') {
          return InitializationStatus({});
        }
        return null;
      });
      final sdk = GoogleAdsSdk();
      expect(await sdk.prepare(), AdsSetup.consentRequired);
      expect(events.any((e) => e == 'MobileAds#initialize'), isFalse);
      allowed = true;
      expect(await sdk.prepare(), AdsSetup.ready);
      expect(
        events.indexOf('ConsentInformation#requestConsentInfoUpdate'),
        lessThan(
          events.indexOf(
            'UserMessagingPlatform#loadAndShowConsentFormIfRequired',
          ),
        ),
      );
      expect(
        events.indexOf('ConsentInformation#canRequestAds'),
        lessThan(events.indexOf('MobileAds#initialize')),
      );
    },
  );

  test('official sample AppID requires explicit dev test config', () async {
    messenger.setMockMethodCallHandler(
      config,
      (_) async => 'ca-app-pub-3940256099942544~1458002511',
    );
    expect(await GoogleAdsSdk().prepare(), AdsSetup.missingConfiguration);
  });

  test('UMP failure never initializes or requests an ad', () async {
    messenger.setMockMethodCallHandler(
      config,
      (_) async => 'ca-app-pub-1234567890123456~1234567890',
    );
    messenger.setMockMethodCallHandler(ump, (_) async {
      throw PlatformException(code: '1', message: 'consent update failed');
    });
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ads, (call) async {
      calls.add(call.method);
      return null;
    });
    expect(await GoogleAdsSdk().prepare(), AdsSetup.failed);
    expect(calls, isEmpty);
  });

  Future<AdRequest> requestSentOn(TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    final sent = Completer<AdRequest>();
    messenger.setMockMethodCallHandler(ads, (call) async {
      if (call.method == 'loadRewardedAd') {
        sent.complete((call.arguments as Map)['request'] as AdRequest);
      }
      return null;
    });
    unawaited(GoogleAdsSdk().load('unit-returned-by-server'));
    return sent.future.timeout(const Duration(seconds: 5));
  }

  test('iOS rewarded request is non-personalized without ATT', () async {
    expect(
      await requestSentOn(TargetPlatform.iOS),
      const AdRequest(nonPersonalizedAds: true),
    );
  });

  test('Android rewarded request is unchanged so UMP decides', () async {
    expect(await requestSentOn(TargetPlatform.android), const AdRequest());
  });

  test(
    'real rewarded SDK sends exact unit, SSV before show, dispose once',
    () async {
      final calls = <MethodCall>[];
      final load = Completer<int>();
      messenger.setMockMethodCallHandler(ads, (call) async {
        calls.add(call);
        if (call.method == 'loadRewardedAd') {
          load.complete((call.arguments as Map)['adId'] as int);
        }
        return null;
      });
      final sdk = GoogleAdsSdk();
      final loading = sdk.load('unit-returned-by-server');
      final id = await load.future.timeout(const Duration(seconds: 5));
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        ads.name,
        ads.codec.encodeMethodCall(
          MethodCall('onAdEvent', {'adId': id, 'eventName': 'onAdLoaded'}),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      final placement = await loading;
      await placement.setVerification('exact-user', 'exact-data');
      await placement.show(onReward: () {}, onDismiss: () {}, onFailure: () {});
      await placement.dispose();
      await placement.dispose();
      expect(calls.map((c) => c.method), [
        'loadRewardedAd',
        'setServerSideVerificationOptions',
        'showAdWithoutView',
        'disposeAd',
      ]);
      expect(
        (calls.first.arguments as Map)['adUnitId'],
        'unit-returned-by-server',
      );
      final ssv = (calls[1].arguments as Map)['serverSideVerificationOptions'];
      expect(ssv.userId, 'exact-user');
      expect(ssv.customData, 'exact-data');
    },
  );
}
