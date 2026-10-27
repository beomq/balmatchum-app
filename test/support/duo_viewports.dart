import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Installed Xcode 27.1 simulator device profile:
// /Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype/
// Contents/Resources/capabilities.plist, capabilities.displays.
// Outer: 1398 x 2034 @3; inner: 2007 x 2853 @3.
const duoViewports = {
  'outer portrait': Size(466, 678),
  'inner portrait': Size(669, 951),
  'inner landscape': Size(951, 669),
  'outer landscape': Size(678, 466),
};

void useDuoViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  // Conservative safe-area fixture, not measured camera/fold geometry.
  tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
}

Widget duoHost(Widget screen) =>
    MaterialApp(theme: meetingTheme(), home: screen);
