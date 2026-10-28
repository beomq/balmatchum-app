import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/settings/account_deletion_screen.dart';
import 'package:balmatchum_app/features/settings/settings_pages.dart';
import 'package:balmatchum_app/features/settings/settings_screen.dart';
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
    await c.initialize();
    var loggedOut = false;
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meetingTheme(),
        home: Builder(
          builder: (context) {
            void push(WidgetBuilder page) =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: page));
            return SettingsScreen(
              controller: c,
              onBack: () {},
              onHome: () {},
              onOpenLogout: () => push(
                (context) => LogoutScreen(
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
                  onBack: () => Navigator.of(context).pop(),
                  onHome: () => Navigator.of(context).pop(),
                ),
              ),
              onOpenDeletion: () => push(
                (context) => AccountDeletionScreen(
                  onDelete: () async => deleted = true,
                  onBack: () => Navigator.of(context).pop(),
                  onHome: () => Navigator.of(context).pop(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-settings');
    await tester.tap(find.byKey(const ValueKey('settings_profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings_name')), '구름');
    await tester.tap(find.byKey(const ValueKey('settings_name_save')));
    await tester.pumpAndSettle();
    expect(c.state.name, '구름');
    server.loseResponse = true;
    await tester.tap(find.byKey(const ValueKey('settings_goal_row')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings_goal')), '7000');
    await tester.tap(find.byKey(const ValueKey('settings_goal_save')));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-retry');
    server.loseResponse = false;
    await tester.tap(find.byKey(const ValueKey('settings_edit_retry')));
    await tester.pumpAndSettle();
    expect(c.state.goal, 7000);
    await binding.takeScreenshot('profile-native-saved');
    final delete = find.byKey(const ValueKey('settings_delete_account'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('profile-native-delete-confirm');
    await tester.tap(find.byKey(const ValueKey('account_deletion_confirm')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    await tester.tap(find.byKey(const ValueKey('account_deletion_cancel')));
    await tester.pumpAndSettle();
    final logout = find.byKey(const ValueKey('settings_logout'));
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logout_confirm')));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
