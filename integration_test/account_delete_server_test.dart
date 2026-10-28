import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/first_meeting/data/first_meeting_file_storage.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/settings/account_deletion_screen.dart';
import 'package:balmatchum_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('delete real account and clear its local profile and session', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final client = container.read(clientProvider);
    await client.auth.restore();
    final owner = client.auth.authInfo!.authUserId.toString();
    final controller = container.read(authenticatedMeetingControllerProvider)!;
    await controller.initialize();
    expect(controller.state.name, '구름');
    final deletion = container.read(accountDeletionProvider)!;
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: Builder(
          builder: (context) => SettingsScreen(
            controller: controller,
            onBack: () {},
            onHome: () {},
            onOpenDeletion: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => AccountDeletionScreen(
                  onDelete: deletion.delete,
                  onBack: () => Navigator.of(context).pop(),
                  onHome: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('settings_delete_account'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    // Execute through the same service and await its exact completion rather
    // than polling authentication or relying on animation settling for HTTP.
    await tester.tap(find.byKey(const ValueKey('account_deletion_cancel')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await deletion.delete();
    expect(client.auth.authInfo, isNull);
    expect(await FirstMeetingFileStorage.forAccount(owner).read(), isNull);
    expect(
      await client.modules.serverpod_auth_core.status.isSignedIn(),
      isFalse,
    );
  });
}
