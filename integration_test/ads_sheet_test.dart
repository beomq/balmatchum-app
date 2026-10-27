import 'dart:async';

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:balmatchum_app/features/ads/ads_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/ads/ads_fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('invokable sheet exposes pending refresh verified and close', (
    tester,
  ) async {
    final events = <String>[];
    final server = FakeAdsServer(events);
    final sdk = FakeAdsSdk(events);
    final controller = AdsController(server: server, sdk: sdk);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  showAdsSheet(
                    context,
                    controller: controller,
                    purpose: 'dailyReward',
                    targetDate: '2026-10-19',
                    targetRevision: 2,
                  ),
                );
              },
              child: const Text('Open ads'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open ads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ads_start')));
    await tester.pump();
    sdk.ad.reward();
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ads_status_pending')), findsOneWidget);
    await binding.takeScreenshot('ads-pending');
    server.status = 'verified';
    await tester.tap(find.byKey(const ValueKey('ads_refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ads_status_verified')), findsOneWidget);
    await binding.takeScreenshot('ads-verified');
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    expect(find.byType(AdsSheet), findsNothing);
    controller.dispose();
  });

  testWidgets('real SDK missing native AppID is safe and retryable', (
    tester,
  ) async {
    // iOS linked SDK requires metadata at native startup; exercise missing-ID
    // boundary via channel injection, not by shipping an app that crashes.
    const channel = MethodChannel('balmatchum/ads_config');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => '');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final controller = AdsController(
      server: FakeAdsServer([]),
      sdk: GoogleAdsSdk.instance,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdsSheet(
            controller: controller,
            purpose: 'dailyReward',
            targetDate: '2026-10-19',
            targetRevision: 2,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ads_start')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ads_status_missingConfiguration')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ads_retry')), findsOneWidget);
    await binding.takeScreenshot('ads-missing-config');
    controller.dispose();
  });
}
