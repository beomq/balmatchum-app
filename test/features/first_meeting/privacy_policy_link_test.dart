import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;

const _policy = 'https://beomq.github.io/balmatchum-legal/privacy-policy.html';
const _failure = '개인정보처리방침을 열지 못했어요. 잠시 후 다시 시도해 주세요.';

Future<FirstMeetingController> _openSettings(
  WidgetTester tester,
  Future<bool> Function(Uri) openUrl,
) async {
  final c = FirstMeetingController(
    storage: MemoryStorage(),
    profileRepository: Profiles()..current = view(),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: FirstMeetingScreen(controller: c, openUrl: openUrl),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('설정'));
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey('settings_privacy_policy'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('privacy policy entry opens the published policy URL', (
    tester,
  ) async {
    final opened = <Uri>[];
    final c = await _openSettings(tester, (url) async {
      opened.add(url);
      return true;
    });
    expect(opened, [Uri.parse(_policy)]);
    expect(find.text(_failure), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('privacy policy shows a notice when no app can open it', (
    tester,
  ) async {
    final c = await _openSettings(tester, (_) async => false);
    expect(find.text(_failure), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('privacy policy shows a notice when the launcher throws', (
    tester,
  ) async {
    final c = await _openSettings(
      tester,
      (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );
    expect(find.text(_failure), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
