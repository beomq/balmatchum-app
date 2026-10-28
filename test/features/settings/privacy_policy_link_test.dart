import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/settings/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _policy = 'https://beomq.github.io/balmatchum-legal/privacy-policy.html';
const _failure = '개인정보처리방침을 열지 못했어요. 잠시 후 다시 시도해 주세요.';

/// 설정 > 서비스 정보 holds the policy link (guide 6.4, SET-09).
Future<void> _openPolicy(
  WidgetTester tester,
  Future<bool> Function(Uri) openUrl,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: ServiceInfoScreen(onBack: () {}, onHome: () {}, openUrl: openUrl),
    ),
  );
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey('settings_privacy_policy'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('privacy policy entry opens the published policy URL', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _openPolicy(tester, (url) async {
      opened.add(url);
      return true;
    });
    expect(opened, [Uri.parse(_policy)]);
    expect(find.text(_failure), findsNothing);
  });

  testWidgets('privacy policy shows a notice when no app can open it', (
    tester,
  ) async {
    await _openPolicy(tester, (_) async => false);
    expect(find.text(_failure), findsOneWidget);
  });

  testWidgets('privacy policy shows a notice when the launcher throws', (
    tester,
  ) async {
    await _openPolicy(
      tester,
      (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );
    expect(find.text(_failure), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
