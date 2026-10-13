import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final evidence = Directory('.qa')..createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${evidence.path}/$name.png').writeAsBytes(bytes);
      if (name == 'meeting-native-os-keyboard') {
        final device = Platform.environment['SIMULATOR_UDID'];
        if (device == null) {
          throw StateError('SIMULATOR_UDID required for OS keyboard evidence');
        }
        final result = await Process.run('xcrun', [
          'simctl',
          'io',
          device,
          'screenshot',
          '${evidence.path}/meeting-os-keyboard-simctl.png',
        ]);
        if (result.exitCode != 0) {
          throw StateError('simctl screenshot failed: ${result.stderr}');
        }
      }
      return true;
    },
  );
}
