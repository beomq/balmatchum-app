import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ads_fakes.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('sheet fits $width $brightness with large text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = AdsController(
          server: FakeAdsServer([]),
          sdk: FakeAdsSdk([]),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: const TextScaler.linear(2),
                ),
                child: AdsSheet(
                  controller: controller,
                  purpose: 'dailyReward',
                  targetDate: '2026-10-19',
                  targetRevision: 2,
                ),
              ),
            ),
          ),
        );
        for (final status in AdsStatus.values) {
          controller.status = status;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 844),
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: AdsSheet(
                    key: ValueKey(status),
                    controller: controller,
                    purpose: 'dailyReward',
                    targetDate: '2026-10-19',
                    targetRevision: 2,
                  ),
                ),
              ),
            ),
          );
          expect(
            find.byKey(ValueKey('ads_status_${status.name}')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
