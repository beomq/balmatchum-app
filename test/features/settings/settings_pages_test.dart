import 'dart:async';

import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/settings/settings_pages.dart';
import 'package:balmatchum_app/features/settings/settings_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LogoutOutcome outcome({required bool cleared}) => LogoutOutcome(
  session: SessionLogoutOutcome(serverRevoked: cleared, localCleared: cleared),
  sdkLoggedOut: cleared,
);

/// Settings with the logout confirmation pushed over it.
Future<void> openLogout(
  WidgetTester tester,
  Future<LogoutOutcome> Function() onLogout,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => LogoutScreen(
                onLogout: onLogout,
                onBack: () => Navigator.of(context).pop(),
                onHome: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          child: const SizedBox.square(dimension: 48),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('logout asks first and leaves only once the device is cleared', (
    tester,
  ) async {
    var calls = 0;
    final release = Completer<LogoutOutcome>();
    Future<LogoutOutcome> logout() {
      calls++;
      return release.future;
    }

    await openLogout(tester, logout);
    await tester.tap(find.byKey(const ValueKey('logout_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(LogoutScreen), findsNothing);
    expect(calls, 0);
    await openLogout(tester, logout);
    final confirm = find.byKey(const ValueKey('logout_confirm'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<AbsorbPointer>(find.byKey(const ValueKey('logout_lock')))
          .absorbing,
      isTrue,
    );
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump();
    expect(find.byType(LogoutScreen), findsOneWidget);
    release.complete(outcome(cleared: true));
    await tester.pumpAndSettle();
    expect(find.byType(LogoutScreen), findsNothing);
    expect(calls, 1);
  });

  testWidgets('a logout that leaves the device signed in stays here', (
    tester,
  ) async {
    for (final failing in <Future<LogoutOutcome> Function()>[
      () async => outcome(cleared: false),
      () async => throw Exception('offline'),
    ]) {
      await openLogout(tester, failing);
      await tester.tap(find.byKey(const ValueKey('logout_confirm')));
      await tester.pumpAndSettle();
      // Not closed as if it worked: the notice shows and it can run again.
      expect(find.byType(LogoutScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('logout_failed')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('logout_confirm')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('permission pages explain without asking or saying allowed', (
    tester,
  ) async {
    var reads = 0;
    final steps = DailyStepsController(
      readSteps: () async {
        reads++;
        return const DailyStepsResult(DailyStepsStatus.available, {
          'count': 6840,
          'date': '2026-10-28',
        });
      },
    );
    addTearDown(steps.dispose);
    await steps.refresh();
    for (final permission in SettingsPermission.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme().copyWith(platform: TargetPlatform.iOS),
          home: PermissionScreen(
            permission: permission,
            dailySteps: steps,
            onBack: () {},
            onHome: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('허용됨'), findsNothing);
      // No button opens the system settings before 9.1 ⑥.
      expect(find.byType(FilledButton), findsNothing);
      expect(
        find.byKey(const ValueKey('settings_permission_guide')),
        findsOneWidget,
      );
      if (permission == SettingsPermission.steps) {
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('settings_permission_state')),
              )
              .data,
          stepsReadState(steps),
        );
      }
    }
    // Only the explicit read above; the pages never read or prompt.
    expect(reads, 1);
  });
}
