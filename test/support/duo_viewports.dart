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

/// Physical (@3) safe-area padding for each viewport.
const duoPaddings = {
  // Measured on the iOS 27.1 simulator: right 84, bottom 34 pt.
  'outer portrait': FakeViewPadding(right: 252, bottom: 102),
  // Not measured; conservative values.
  'inner portrait': FakeViewPadding(top: 186, bottom: 102),
  // Not measured; assumes the right column and a 21 pt bottom.
  'inner landscape': FakeViewPadding(right: 252, bottom: 63),
  // Not measured; exercises the no-rail path.
  'outer landscape': FakeViewPadding(top: 186, bottom: 102),
};

void useDuoViewport(WidgetTester tester, String name) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = duoViewports[name]! * 3;
  tester.view.padding = duoPaddings[name]!;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
}

Widget duoHost(Widget screen) =>
    MaterialApp(theme: meetingTheme(), home: screen);
