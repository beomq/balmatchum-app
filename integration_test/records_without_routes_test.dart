import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('records without routes at small and large widths', (
    tester,
  ) async {
    final date = DateTime(2026, 10, 18);
    final day = RecordDay(
      date: date,
      revision: 1,
      steps: 4200,
      availability: StepAvailability.confirmed,
      rewardStatus: DayRewardStatus.paid,
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
        for (final detail in [true, false]) {
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
                    child: detail
                        ? RecordDayScreen(
                            date: date,
                            loadDay: (_) async => day,
                            deleteDay: (_) async => throw Exception('not used'),
                            claimDay: (_) async => 0,
                            onBack: () {},
                            onHome: () {},
                          )
                        : RecordsCalendarScreen(
                            initialMonth: date,
                            loadMonth: (month) async =>
                                RecordMonth(month: month, days: [day]),
                            onOpenDay: (_) {},
                            onBack: () {},
                            onHome: () {},
                          ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (detail) {
            expect(find.text('4,200걸음'), findsOneWidget);
            expect(find.text('이 날짜의 포인트를 모두 받았어요.'), findsOneWidget);
          } else {
            expect(
              find.bySemanticsLabel(RegExp('^10월 18일, 4,200걸음')),
              findsOneWidget,
            );
          }
          expect(find.textContaining('GPS'), findsNothing);
          expect(find.byKey(const ValueKey('records_route_map')), findsNothing);
          expect(find.byKey(const ValueKey('records_naver_map')), findsNothing);
          expect(tester.takeException(), isNull);
          await binding.takeScreenshot(
            'records-${detail ? 'day' : 'calendar'}-${width.toInt()}-${brightness.name}',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  });
}
