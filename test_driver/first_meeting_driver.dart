import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final evidence = Directory('.qa')..createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${evidence.path}/$name.png').writeAsBytes(bytes);
      // UIKit keyboard evidence is captured at KEYBOARD_CAPTURE_READY while
      // the test is live, not here after the test has completed.
      return true;
    },
  );
}
