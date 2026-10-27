import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(theme: meetingTheme(), home: child);

final date = DateTime(2027, 1, 4);

RouteSegment segment(String id, int hourUtc, double lat) => RouteSegment(
  id: id,
  source: 'phone',
  points: [
    for (var i = 0; i < 3; i++)
      RoutePointView(
        recordedAt: DateTime.utc(2027, 1, 4, hourUtc, i * 10),
        latitude: lat + i * .001,
        longitude: 127 + i * .001,
      ),
  ],
);

RecordDay day({
  int? steps = 4200,
  StepAvailability availability = StepAvailability.confirmed,
  DayRewardStatus reward = DayRewardStatus.claimable,
  int? claimable = 4,
  int granted = 0,
  int revision = 3,
  List<RouteSegment>? routes,
  String? fixture,
}) => RecordDay(
  date: date,
  revision: revision,
  steps: steps,
  availability: availability,
  rewardStatus: reward,
  claimablePoints: claimable,
  grantedPoints: granted,
  fixtureLabel: fixture,
  routes: routes ?? [segment('r1', 0, 37.5), segment('r2', 5, 37.51)],
);

RecordDay deleted() => RecordDay(
  date: date,
  revision: 4,
  steps: null,
  availability: StepAvailability.deleted,
  rewardStatus: DayRewardStatus.canceled,
  claimablePoints: 0,
  grantedPoints: 2,
);

RecordDayScreen dayScreen({
  required LoadRecordDay load,
  DeleteRecordDay? delete,
  ClaimRecordDay? claim,
  ValueChanged<RecordDay>? changed,
}) => RecordDayScreen(
  date: date,
  loadDay: load,
  deleteDay: delete ?? (_) async => throw StateError('no delete'),
  claimDay: claim ?? (_) async => throw StateError('no claim'),
  onDayChanged: changed,
  onBack: () {},
  onHome: () {},
);

void main() {
  test('bundled KR holiday lookup is offline and date exact', () {
    expect(koreanHolidayName(DateTime(2026, 1, 1)), '신정');
    // 2027 bundled name is English; the Korean description is shown.
    expect(koreanHolidayName(DateTime(2027, 1, 1)), '신정연휴');
    expect(koreanHolidayName(DateTime(2027, 1, 2)), isNull);
  });

  testWidgets('calendar loads, fails, retries and opens a day once', (
    tester,
  ) async {
    final requests = <DateTime>[];
    var fail = true;
    final opened = <DateTime>[];
    await tester.pumpWidget(
      host(
        RecordsCalendarScreen(
          initialMonth: DateTime(2027, 1, 15),
          loadMonth: (month) async {
            requests.add(month);
            if (fail) throw Exception('offline');
            return RecordMonth(
              month: month,
              days: [
                day(steps: 0, reward: DayRewardStatus.paid, routes: []),
                RecordDay(
                  date: DateTime(2027, 1, 5),
                  revision: 1,
                  steps: null,
                  availability: StepAvailability.unavailable,
                  rewardStatus: DayRewardStatus.pending,
                ),
              ],
            );
          },
          onOpenDay: opened.add,
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기록을 불러오지 못했어요.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('product_retry')));
    await tester.pumpAndSettle();
    expect(requests, [DateTime(2027, 1), DateTime(2027, 1)]);
    // Measured zero and unknown are distinct.
    expect(find.bySemanticsLabel(RegExp('^1월 4일, 0걸음')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^1월 5일, 걸음 확인 불가')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^1월 1일, 신정')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('records_day_4')));
    await tester.pump();
    expect(opened, [DateTime(2027, 1, 4)]);
    await tester.tap(find.byKey(const ValueKey('records_next_month')));
    await tester.pumpAndSettle();
    expect(requests.last, DateTime(2027, 2));
  });

  testWidgets(
    'day renders steps and rewards without route UI when routes exist',
    (tester) async {
      // Given a stored day that still contains server route data.
      final stored = day(fixture: 'dev-fixture-v1');
      // When the first-release record screen loads it.
      await tester.pumpWidget(host(dayScreen(load: (_) async => stored)));
      await tester.pumpAndSettle();
      // Then steps and rewards remain usable without any route surface.
      expect(find.text('4,200걸음'), findsOneWidget);
      expect(find.text('4포인트를 받을 수 있어요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product_fixture_badge')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('records_route_map')), findsNothing);
      expect(find.byKey(const ValueKey('records_naver_map')), findsNothing);
      expect(find.textContaining('GPS'), findsNothing);
      expect(find.byKey(const ValueKey('records_claim')), findsOneWidget);
    },
  );

  testWidgets('calendar hides routes when a stored day contains coordinates', (
    tester,
  ) async {
    // Given an existing server record with coordinates and claimable rewards.
    final stored = day();
    // When the month containing it renders.
    await tester.pumpWidget(
      host(
        RecordsCalendarScreen(
          initialMonth: date,
          loadMonth: (month) async => RecordMonth(month: month, days: [stored]),
          onOpenDay: (_) {},
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Then only steps and rewards are advertised, including accessibility.
    expect(
      find.bySemanticsLabel(RegExp('^1월 4일, 4,200걸음, 받을 포인트 있음')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('GPS')), findsNothing);
    expect(find.textContaining('GPS'), findsNothing);
  });

  testWidgets('unavailable steps-only day differs from zero', (tester) async {
    await tester.pumpWidget(
      host(
        dayScreen(
          load: (_) async => day(
            steps: null,
            availability: StepAvailability.unavailable,
            reward: DayRewardStatus.pending,
            claimable: null,
            routes: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('0걸음과는 달라요'), findsOneWidget);
    expect(find.textContaining('GPS'), findsNothing);
    expect(find.byKey(const ValueKey('records_claim')), findsNothing);
  });

  testWidgets('cancelled day delete calls nothing; copy covers both rules', (
    tester,
  ) async {
    var deletes = 0;
    await tester.pumpWidget(
      host(
        dayScreen(
          load: (_) async => day(routes: []),
          delete: (_) async {
            deletes++;
            return deleted();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('records_delete_day'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('1월 4일 기록을 모두 삭제할까요?'), findsOneWidget);
    expect(find.textContaining('받지 않은 포인트는 취소'), findsOneWidget);
    expect(find.textContaining('이미 받은 포인트는 그대로 유지'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('records_delete_cancel')));
    await tester.pumpAndSettle();
    expect(deletes, 0);
  });

  testWidgets('confirmed delete runs once for the whole day', (tester) async {
    final pending = Completer<RecordDay>();
    final calls = <DateTime>[];
    final changed = <RecordDay>[];
    await tester.pumpWidget(
      host(
        dayScreen(
          load: (_) async => day(),
          delete: (d) {
            calls.add(d);
            return pending.future;
          },
          changed: changed.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('records_delete_day'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records_delete_confirm')));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('records_claim')))
          .onPressed,
      isNull,
    );
    pending.complete(deleted());
    await tester.pumpAndSettle();
    expect(calls, [date]);
    expect(changed.single.isDeleted, isTrue);
    expect(find.byKey(const ValueKey('records_deleted')), findsOneWidget);
    expect(find.byKey(const ValueKey('records_route_map')), findsNothing);
    expect(find.byKey(const ValueKey('records_naver_map')), findsNothing);
    expect(find.byKey(const ValueKey('records_delete_day')), findsNothing);
  });

  testWidgets('failed delete keeps the day and explains', (tester) async {
    await tester.pumpWidget(
      host(
        dayScreen(
          load: (_) async => day(),
          delete: (_) async => throw Exception('500'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('records_delete_day'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('records_delete_confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('삭제하지 못했어요'), findsOneWidget);
    expect(find.text('4,200걸음'), findsOneWidget);
  });

  testWidgets('claim fails, retries once, then reloads server state', (
    tester,
  ) async {
    var loads = 0;
    final claims = <int>[];
    var fail = true;
    final changed = <RecordDay>[];
    await tester.pumpWidget(
      host(
        dayScreen(
          load: (_) async => ++loads == 1
              ? day()
              : day(
                  reward: DayRewardStatus.paid,
                  claimable: 0,
                  granted: 4,
                  revision: 4,
                ),
          claim: (d) async {
            claims.add(d.revision);
            if (fail) throw Exception('stale');
            return 4;
          },
          changed: changed.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final claim = find.byKey(const ValueKey('records_claim'));
    await tester.tap(claim);
    await tester.pumpAndSettle();
    expect(find.textContaining('포인트를 받지 못했어요'), findsOneWidget);
    expect(loads, 1);
    fail = false;
    await tester.tap(claim);
    await tester.pumpAndSettle();
    expect(claims, [3, 3]);
    expect(loads, 2);
    expect(find.text('4포인트를 받았어요.'), findsOneWidget);
    expect(find.text('이 날짜의 포인트를 모두 받았어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('records_claim')), findsNothing);
    expect(changed.single.rewardStatus, DayRewardStatus.paid);
  });

  testWidgets('back and home each fire once', (tester) async {
    var back = 0;
    var home = 0;
    await tester.pumpWidget(
      host(
        RecordDayScreen(
          date: date,
          loadDay: (_) async => day(),
          deleteDay: (_) async => deleted(),
          claimDay: (_) async => 0,
          onBack: () => back++,
          onHome: () => home++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product_back')));
    await tester.tap(find.byKey(const ValueKey('product_home')));
    expect((back, home), (1, 1));
  });
}
