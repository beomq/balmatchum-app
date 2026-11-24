import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.beomq.balmatchum/watch');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final status in ['permissionDenied', 'providerUpdateRequired']) {
    test('preserves $status without inventing a step count', () async {
      // Given a native Health Connect outcome with no observation.
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'requestDailySteps');
        expect(call.arguments, isNull);
        return {'status': status, 'dailySteps': null};
      });

      // When the shared bridge reads today's steps.
      final result = await WatchBridge().requestDailySteps();

      // Then Android's actionable outcome survives the channel boundary.
      expect(result.status.name, status);
      expect(result.dailySteps, isNull);
    });
  }

  test('sends the install instant for the native window', () async {
    Object? arguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      arguments = call.arguments;
      return {'status': 'empty', 'dailySteps': null};
    });
    await WatchBridge().requestDailySteps(
      since: DateTime.utc(2026, 11, 1, 3, 30),
    );
    expect(arguments, {'since': '2026-11-01T03:30:00.000Z'});
  });
}
