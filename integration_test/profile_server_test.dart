import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_app/features/first_meeting/data/first_meeting_file_storage.dart';
import 'package:balmatchum_app/features/first_meeting/data/profile_repository.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real session profile create settings and disk restore', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final client = container.read(clientProvider);
    expect(await importDevTestSession(client), isTrue);
    final owner = client.auth.authInfo!.authUserId.toString();
    final repository = ServerpodProfileRepository(client);
    final storage = FirstMeetingFileStorage.forAccount(owner);
    var controller = FirstMeetingController(
      storage: storage,
      profileRepository: repository,
    );
    await controller.initialize();
    expect(controller.profile, isNull);
    await controller.enter();
    await controller.chooseCatalog();
    await controller.selectBreed('pug');
    await controller.confirmCandidate();
    await controller.updateName('검증친구');
    await controller.updateSex(DogSex.female);
    await controller.submitName();
    await controller.commit();
    expect(
      controller.state.isComplete,
      isTrue,
      reason: controller.profileError,
    );
    final firstMetAt = controller.profile!.firstMetAt;
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: SettingsScreen(
          controller: controller,
          onBack: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings_name')), '구름');
    await tester.tap(find.byKey(const ValueKey('settings_name_save')));
    await tester.runAsync(() async {
      // Controller commands serialize with the UI mutation already submitted.
      await controller.initialize();
    });
    await tester.pumpAndSettle();
    expect(controller.state.name, '구름');
    await tester.tap(find.byKey(const ValueKey('settings_goal_row')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings_goal')), '7000');
    await tester.tap(find.byKey(const ValueKey('settings_goal_save')));
    await tester.runAsync(() => controller.initialize());
    await tester.pumpAndSettle();
    expect(controller.state.goal, 7000);
    await binding.takeScreenshot('profile-server-settings');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    controller = FirstMeetingController(
      storage: FirstMeetingFileStorage.forAccount(owner),
      profileRepository: repository,
    );
    await controller.initialize();
    expect(controller.state.name, '구름');
    expect(controller.state.goal, 7000);
    expect(controller.profile!.firstMetAt, firstMetAt);
    expect((await repository.getProfile())!.name, '구름');
    controller.dispose();
  });
}
