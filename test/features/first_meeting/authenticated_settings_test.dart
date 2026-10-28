import 'dart:async';

import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;

void main() {
  testWidgets(
    'deletion requires confirmation and blocks settings while pending',
    (tester) async {
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: Profiles()..current = view(),
      );
      final release = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: FirstMeetingScreen(
            controller: c,
            onDeleteAccount: () async {
              calls++;
              await release.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('회원 탈퇴'));
      await tester.tap(find.text('회원 탈퇴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('회원 탈퇴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계정 영구 삭제'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<AbsorbPointer>(find.byType(AbsorbPointer).last).absorbing,
        isTrue,
      );
      release.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets('settings keep deletion red at the bottom with no primary', (
    tester,
  ) async {
    final c = FirstMeetingController(
      storage: MemoryStorage(),
      profileRepository: Profiles()..current = view(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c, onDeleteAccount: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    // Two equal saves never compete as primaries (guide 3.3).
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    final delete = find.byKey(const ValueKey('settings_delete_account'));
    await tester.ensureVisible(delete);
    final ink = tester.widget<Material>(
      find.descendant(of: delete, matching: find.byType(Material)),
    );
    expect(ink.textStyle?.color, MeetingColors.error);
    expect(
      tester.getRect(delete).top,
      greaterThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('settings_privacy_policy')))
            .bottom,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('settings save retry and logout at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = Profiles()..current = view();
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: server,
      );
      var logoutCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: FirstMeetingScreen(
            controller: c,
            onLogout: () async {
              logoutCalls++;
              return const LogoutOutcome(
                session: SessionLogoutOutcome(
                  serverRevoked: false,
                  localCleared: true,
                ),
                sdkLoggedOut: true,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings_name')),
        '새친구',
      );
      await tester.tap(find.text('이름 저장'));
      await tester.pumpAndSettle();
      expect(c.state.name, '새친구');
      server.loseResponse = true;
      await tester.enterText(
        find.byKey(const ValueKey('settings_goal')),
        '7000',
      );
      await tester.ensureVisible(find.text('목표 저장'));
      await tester.tap(find.text('목표 저장'));
      await tester.pumpAndSettle();
      expect(c.hasPendingMutation, isTrue);
      server.loseResponse = false;
      final retry = find.text('저장 결과 확인 · 재시도').last;
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(c.state.goal, 7000);
      await tester.ensureVisible(find.text('로그아웃'));
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(logoutCalls, 1);
      expect(find.byKey(const ValueKey('settings_name')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
}
