import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdsSetup { ready, missingConfiguration, consentRequired, failed }

abstract interface class AdsSdk {
  Future<AdsSetup> prepare();
  Future<RewardedPlacement> load(String adUnit);
  Future<void> privacyOptions();
  bool get privacyOptionsRequired;
}

abstract interface class RewardedPlacement {
  Future<void> setVerification(String userId, String customData);
  Future<void> show({
    required void Function() onReward,
    required void Function() onDismiss,
    required void Function() onFailure,
  });
  Future<void> dispose();
}

/// No sample IDs or implicit production defaults. Native metadata is authoritative.
class GoogleAdsSdk implements AdsSdk {
  static const _channel = MethodChannel('balmatchum/ads_config');
  static final instance = GoogleAdsSdk();
  Future<AdsSetup>? _preparing;
  bool _initialized = false;
  bool _consentGathered = false;
  @override
  bool privacyOptionsRequired = false;

  @override
  Future<AdsSetup> prepare() => _preparing ??= _prepare().whenComplete(() {
    _preparing = null;
  });

  Future<AdsSetup> _prepare() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return AdsSetup.missingConfiguration;
    }
    try {
      final id = await _channel.invokeMethod<String>('appId') ?? '';
      final parts = id.split('~');
      bool digits(String value) =>
          value.codeUnits.every((c) => c >= 48 && c <= 57);
      if (parts.length != 2 ||
          !parts[0].startsWith('ca-app-pub-') ||
          parts[0].length != 27 ||
          parts[1].length != 10 ||
          !digits(parts[0].substring(11)) ||
          !digits(parts[1])) {
        return AdsSetup.missingConfiguration;
      }
      const test = bool.fromEnvironment('ADMOB_TEST_ADS');
      if (id.startsWith('ca-app-pub-3940256099942544~') &&
          (!test || kReleaseMode || appFlavor != 'dev')) {
        return AdsSetup.missingConfiguration;
      }
      if (!_consentGathered) {
        final updated = Completer<bool>();
        ConsentInformation.instance.requestConsentInfoUpdate(
          ConsentRequestParameters(),
          () => updated.complete(true),
          (_) => updated.complete(false),
        );
        if (!await updated.future) return AdsSetup.failed;
        final form = Completer<bool>();
        ConsentForm.loadAndShowConsentFormIfRequired(
          (error) => form.complete(error == null),
        );
        if (!await form.future) return AdsSetup.failed;
        _consentGathered = true;
      }
      privacyOptionsRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (!await ConsentInformation.instance.canRequestAds()) {
        _consentGathered = false;
        return AdsSetup.consentRequired;
      }
      if (!_initialized) {
        await MobileAds.instance.initialize();
        _initialized = true;
      }
      return AdsSetup.ready;
    } on Exception {
      return AdsSetup.failed;
    }
  }

  @override
  Future<void> privacyOptions() async {
    if (!privacyOptionsRequired) return;
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        done.complete();
      } else {
        done.completeError(StateError('Consent options failed'));
      }
    });
    _consentGathered = false;
    await done.future;
  }

  @override
  Future<RewardedPlacement> load(String adUnit) async {
    // The returned server adUnit is never substituted, including in tests.
    const test = bool.fromEnvironment('ADMOB_TEST_ADS');
    final officialTestUnit = defaultTargetPlatform == TargetPlatform.android
        ? 'ca-app-pub-3940256099942544/5224354917'
        : 'ca-app-pub-3940256099942544/1712485313';
    if ((test &&
            (kReleaseMode ||
                appFlavor != 'dev' ||
                adUnit != officialTestUnit)) ||
        (!test && adUnit.startsWith('ca-app-pub-3940256099942544/'))) {
      throw StateError('Ad unit does not match explicit test configuration');
    }
    final loaded = Completer<RewardedPlacement>();
    await RewardedAd.load(
      adUnitId: adUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => loaded.complete(_GoogleRewardedPlacement(ad)),
        onAdFailedToLoad: (error) => loaded.completeError(error),
      ),
    );
    return loaded.future;
  }
}

class _GoogleRewardedPlacement implements RewardedPlacement {
  _GoogleRewardedPlacement(this.ad);
  final RewardedAd ad;
  bool _disposed = false;
  bool _shown = false;
  @override
  Future<void> setVerification(String userId, String customData) =>
      ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: userId, customData: customData),
      );

  @override
  Future<void> show({
    required void Function() onReward,
    required void Function() onDismiss,
    required void Function() onFailure,
  }) async {
    if (_disposed || _shown) throw StateError('Ad is no longer available');
    _shown = true;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (_) => onDismiss(),
      onAdFailedToShowFullScreenContent: (_, _) => onFailure(),
    );
    await ad.show(onUserEarnedReward: (_, _) => onReward());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await ad.dispose();
  }
}
