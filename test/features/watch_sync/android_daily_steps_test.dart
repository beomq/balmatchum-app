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
}
