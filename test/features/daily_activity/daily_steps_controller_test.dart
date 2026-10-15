import 'dart:async';

import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown differs from a successfully observed zero', () async {
    final controller = DailyStepsController(
      readSteps: () async => const DailyStepsResult(
        DailyStepsStatus.available,
        {'count': 0, 'date': '2026-10-14'},
      ),
    );
    addTearDown(controller.dispose);
    expect(controller.count, isNull);
    await controller.refresh();
    expect(controller.count, 0);
    expect(controller.date, '2026-10-14');
  });

  test('failed refresh clears the previous observation', () async {
    var fail = false;
    final controller = DailyStepsController(
      readSteps: () async {
        if (fail) throw PlatformException(code: 'queryFailed');
        return const DailyStepsResult(DailyStepsStatus.available, {
          'count': 123,
          'date': '2026-10-14',
        });
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    fail = true;
    await controller.refresh();
    expect(controller.count, isNull);
    expect(controller.result?.status, DailyStepsStatus.error);
  });

  test('coalesces refresh and ignores completion after disposal', () async {
    final pending = Completer<DailyStepsResult>();
    var reads = 0;
    final controller = DailyStepsController(
      readSteps: () {
        reads++;
        return pending.future;
      },
    );
    final first = controller.refresh();
    await controller.refresh();
    expect(reads, 1);
    controller.dispose();
    pending.complete(const DailyStepsResult(DailyStepsStatus.empty, null));
    await first;
  });

  test('unsupported platform remains unknown, not zero', () async {
    final controller = DailyStepsController(
      readSteps: () async => throw MissingPluginException(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.count, isNull);
    expect(controller.result?.status, DailyStepsStatus.capabilityUnavailable);
  });
}
