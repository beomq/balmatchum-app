import 'dart:async';

import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_readout.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final count = find.byKey(const ValueKey('daily_steps_count'));
  final retry = find.byKey(const ValueKey('daily_steps_retry'));

  Future<DailyStepsController> mount(
    WidgetTester tester,
    Future<DailyStepsResult> Function() read, {
    VoidCallback? onRetry,
  }) async {
    final steps = DailyStepsController(readSteps: read);
    addTearDown(steps.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: steps,
            builder: (_, _) =>
                DailyStepsReadout(controller: steps, onRetry: onRetry),
          ),
        ),
      ),
    );
    return steps;
  }

  testWidgets('a read shows a grouped count and no manual refresh', (
    tester,
  ) async {
    final steps = await mount(
      tester,
      () async => const DailyStepsResult(DailyStepsStatus.available, {
        'count': 6840,
        'date': '2026-10-28',
      }),
    );
    await steps.refresh();
    await tester.pump();
    expect(tester.widget<Text>(count).data, '6,840걸음');
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets(
    'only failed reads offer a retry, and it runs the screen refresh',
    (tester) async {
      var status = DailyStepsStatus.available;
      var retries = 0;
      final steps = await mount(
        tester,
        () async => DailyStepsResult(status, null),
        onRetry: () => retries++,
      );
      const failed = {
        DailyStepsStatus.error,
        DailyStepsStatus.unavailable,
        DailyStepsStatus.permissionDenied,
        DailyStepsStatus.providerUpdateRequired,
      };
      for (final value in DailyStepsStatus.values) {
        status = value;
        await steps.refresh();
        await tester.pump();
        expect(
          retry,
          failed.contains(value) ? findsOneWidget : findsNothing,
          reason: '$value',
        );
      }
      status = DailyStepsStatus.error;
      await steps.refresh();
      await tester.pump();
      await tester.tap(retry);
      expect(retries, 1);
    },
  );

  testWidgets('a read in flight shows no stale count and no retry', (
    tester,
  ) async {
    final gate = Completer<DailyStepsResult>();
    final steps = await mount(tester, () => gate.future);
    final run = steps.refresh();
    await tester.pump();
    expect(tester.widget<Text>(count).data, '—걸음');
    expect(retry, findsNothing);
    gate.complete(const DailyStepsResult(DailyStepsStatus.error, null));
    await run;
    await tester.pump();
    expect(retry, findsOneWidget);
  });
}
