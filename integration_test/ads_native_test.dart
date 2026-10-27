import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Opt-in native SDK smoke, official test unit only. No live ad or reward grant.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('official native rewarded test ad loads with SSV options', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('ADMOB_TEST_ADS'), isTrue);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('AdMob SDK test'))),
    );
    final sdk = GoogleAdsSdk.instance;
    final result = await tester.runAsync(sdk.prepare);
    expect(
      result,
      AdsSetup.ready,
      reason: 'Native metadata and UMP must be valid',
    );
    final ad = await tester.runAsync(
      () => sdk.load('ca-app-pub-3940256099942544/1712485313'),
    );
    expect(ad, isNotNull);
    await tester.runAsync(
      () => ad!.setVerification('native-test-user', 'native-test-nonce'),
    );
    await tester.runAsync(() => ad!.dispose());
  });
}
