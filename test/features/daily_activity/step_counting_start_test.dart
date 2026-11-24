import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/step_counting_start.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('step-start-');
  });
  tearDown(() => directory.delete(recursive: true));

  StepCountingStart at(DateTime now) =>
      StepCountingStart(directory: () async => directory, now: () => now);

  test('a fresh install counts from its first read and keeps it', () async {
    final first = DateTime.utc(2026, 11, 1, 3, 30);
    expect(await at(first).read(), first);
    // A later launch reads the stored instant, not its own clock.
    expect(await at(DateTime.utc(2026, 11, 2)).read(), first);
  });

  test('an install that already uploaded steps keeps whole days', () async {
    await File('${directory.path}/steps-account.json').writeAsString('{}');
    expect(await at(DateTime.utc(2026, 11, 1, 3)).read(), isNull);
    // The decision is stored, so it survives later uploads and launches.
    await File('${directory.path}/steps-account.json').delete();
    expect(await at(DateTime.utc(2026, 11, 2)).read(), isNull);
  });
}
