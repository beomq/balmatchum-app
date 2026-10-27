import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/record_map.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native stored route no-key surface at small and large widths', (
    tester,
  ) async {
    expect(naverMapClientId, isEmpty);
    await recordMapRuntime.initialize(clientId: naverMapClientId);
    expect(recordMapRuntime.value, RecordMapStatus.unconfigured);
    final date = DateTime(2026, 10, 18);
    final day = RecordDay(
      date: date,
      revision: 1,
      steps: 4200,
      availability: StepAvailability.confirmed,
      rewardStatus: DayRewardStatus.paid,
      fixtureLabel: '지도 QA용 합성 좌표 · 실제 개인 기록 아님',
      routes: [
        for (var segment = 0; segment < 2; segment++)
          RouteSegment(
            id: 'qa-$segment',
            source: 'phone',
            points: [
              for (var i = 0; i < 3; i++)
                RoutePointView(
                  recordedAt: DateTime.utc(2026, 10, 18, segment, i),
                  latitude: 37.5 + segment * .02 + i * .001,
                  longitude: 127 + segment * .02 + i * .001,
                ),
            ],
          ),
      ],
    );
    for (final width in [320.0, 768.0]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1000),
                platformBrightness: brightness,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: RecordDayScreen(
                    date: date,
                    loadDay: (_) async => day,
                    deleteDay: (_) async => throw Exception('not used'),
                    claimDay: (_) async => 0,
                    onBack: () {},
                    onHome: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('records_route_map')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NaverMap), findsNothing);
        expect(
          find.byKey(const ValueKey('records_map_unconfigured')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(
          'map-no-key-${width.toInt()}-${brightness.name}',
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
