import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/first_meeting/domain/authenticated_profile_test.dart'
    show Profiles, view;
import '../test/features/first_meeting/domain/first_meeting_test.dart'
    show MemoryStorage;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native profile settings repository seam UI evidence', (
    tester,
  ) async {
    final server = Profiles()..current = view();
    final c = FirstMeetingController(
      storage: MemoryStorage(),
      profileRepository: server,
    );
    var loggedOut = false;
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meetingTheme(),
        home: FirstMeetingScreen(
          controller: c,
          onDeleteAccount: () async => deleted = true,
          onLogout: () async {
            loggedOut = true;
            return const LogoutOutcome(
              session: SessionLogoutOutcome(
                serverRevoked: true,
                localCleared: true,
              ),
              sdkLoggedOut: true,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-home');
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-settings');
    await tester.enterText(find.byKey(const ValueKey('settings_name')), '구름');
    await tester.tap(find.text('이름 저장'));
    await tester.pumpAndSettle();
    expect(c.state.name, '구름');
    server.loseResponse = true;
    await tester.enterText(find.byKey(const ValueKey('settings_goal')), '7000');
    await tester.ensureVisible(find.text('목표 저장'));
    await tester.tap(find.text('목표 저장'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-retry');
    server.loseResponse = false;
    await tester.ensureVisible(find.text('저장 결과 확인 · 재시도').last);
    await tester.tap(find.text('저장 결과 확인 · 재시도').last);
    await tester.pumpAndSettle();
    expect(c.state.goal, 7000);
    await binding.takeScreenshot('profile-native-saved');
    await tester.ensureVisible(find.text('회원 탈퇴'));
    await tester.tap(find.text('회원 탈퇴'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-delete-confirm');
    await tester.tap(find.text('계정 영구 삭제'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
