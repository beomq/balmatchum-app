import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'domain/first_meeting_test.dart' show MemoryStorage;

void main() {
  test('decodeWidth scales a usable width and skips the rest', () {
    expect(decodeWidth(160, 3), 480);
    expect(decodeWidth(390.4, 2.5), 976);
    expect(decodeWidth(double.infinity, 3), isNull);
    expect(decodeWidth(0, 3), isNull);
    expect(decodeWidth(0.1, 1), isNull);
    expect(decodeWidth(double.nan, 3), isNull);
  });

  testWidgets('the splash decodes at its 160 pt width (dpr 3)', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FirstMeetingController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c),
      ),
    );
    final splash = tester.widget<Image>(
      find.byKey(const ValueKey('first_meeting_loading')),
    );
    final decoded = splash.image as ResizeImage;
    expect(
      decoded.imageProvider,
      const AssetImage('assets/brand/balmatchum_splash.png'),
    );
    expect(decoded.width, 480);
    await tester.pumpAndSettle();
  });

  for (final (name, wrap) in <(String, Widget Function(Widget))>[
    ('unbounded', (child) => UnconstrainedBox(child: child)),
    ('zero', (child) => SizedBox.shrink(child: child)),
  ]) {
    testWidgets('a $name layout width draws without a decode width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: wrap(
            LayoutBuilder(
              builder: (context, constraints) => Image.asset(
                'assets/first_meeting/sunny.png',
                width: 40,
                cacheWidth: decodeWidth(
                  constraints.maxWidth,
                  MediaQuery.devicePixelRatioOf(context),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });
  }
}
