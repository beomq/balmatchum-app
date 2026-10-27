import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart' as api;
import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:balmatchum_app/features/photo/platform_photo_adapter.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'authenticated activity HTTP disk records deletion and profile photo',
    (tester) async {
      final date = ProductRepository.today;
      final key = ProductRepository.dateKey(date);
      final sensor = DailyStepsController(
        readSteps: () async => DailyStepsResult(DailyStepsStatus.available, {
          'date': key,
          'count': 5000,
          'observedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      addTearDown(sensor.dispose);
      final container = ProviderContainer(
        overrides: [
          dailyStepsControllerProvider.overrideWithValue(sensor),
          // Watch transport is outside this phone activity upload QA.
          watchSyncServiceProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      final client = container.read(clientProvider);
      expect(await importDevTestSession(client), isTrue);
      expect(
        await client.modules.serverpod_auth_core.status.isSignedIn(),
        isTrue,
      );
      final account = client.auth.authInfo!.authUserId.toString();
      expect(container.read(authenticatedAccountProvider), account);
      var profile = await client.profile.getProfile();
      profile ??= await client.profile.createProfile(
        api.ProfileInput(
          breedId: 'pug',
          name: '활동친구',
          sex: 'female',
          dailyGoal: 7000,
        ),
        api.Uuid().v4(),
      );
      final meeting = container.read(authenticatedMeetingControllerProvider)!;
      await meeting.initialize();
      expect(meeting.state.isComplete, isTrue);
      expect(meeting.state.name, profile.name);
      expect(meeting.state.candidate!.id, profile.breedId);
      final product = container.read(authenticatedProductControllerProvider)!;
      expect(product.account, account);
      expect(product.repository.accountId, account);
      expect(product.repository, isA<ProductRepository>());
      expect(
        (await product.repository.day(date)).deleted,
        isFalse,
        reason:
            'Use a fresh harness account: deletion tombstones are permanent.',
      );
      await product.connect();
      expect(product.connected, isTrue, reason: product.error);
      expect(product.store, isNull);
      expect(product.quiz, isNull);
      await product.sync();
      expect(product.error, isNull);
      expect(product.today!.steps, 5000);
      final support = await getApplicationSupportDirectory();
      final disk = jsonDecode(
        await File('${support.path}/steps-$account.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(disk['generation'], product.today!.streamGeneration);
      expect(disk['revision'], product.today!.stepRevision);
      expect(disk['revision'], greaterThan(0));
      expect(disk.containsKey('pending'), isFalse);
      final remote = await product.repository.day(date);
      expect(remote.steps, 5000);
      expect(remote.availability, 'confirmed');
      final evidence = Directory('${support.path}/activity-qa');
      await evidence.create(recursive: true);
      Future<void> capture(String name) async {
        final bytes = await binding.takeScreenshot(name);
        await File('${evidence.path}/$name.png').writeAsBytes(bytes);
      }

      Future<void> mount(Widget child) =>
          tester.pumpWidget(MaterialApp(theme: meetingTheme(), home: child));
      final monthLoaded = Completer<RecordMonth>();
      final opened = Completer<DateTime>();
      await mount(
        RecordsCalendarScreen(
          initialMonth: date,
          loadMonth: (month) async {
            final value = await product.loadMonth(month);
            if (!monthLoaded.isCompleted) monthLoaded.complete(value);
            return value;
          },
          onOpenDay: (value) {
            opened.complete(value);
          },
          onBack: () {},
          onHome: () {},
        ),
      );
      final month = await tester.runAsync(
        () => monthLoaded.future.timeout(const Duration(seconds: 20)),
      );
      expect(month!.day(date.day)!.steps, 5000);
      await tester.pumpAndSettle();
      expect(find.text('5.0k'), findsOneWidget);
      await capture('activity-server-month');
      // Opening the day is observed before replacing the route surface.
      await tester.tap(find.byKey(ValueKey('records_day_${date.day}')));
      expect(
        await opened.future.timeout(const Duration(seconds: 5)),
        DateTime(date.year, date.month, date.day),
      );
      final dayLoaded = Completer<RecordDay>();
      final deleted = Completer<RecordDay>();
      await mount(
        RecordDayScreen(
          date: date,
          loadDay: (value) async {
            final day = await product.loadDay(value);
            dayLoaded.complete(day);
            return day;
          },
          deleteDay: product.deleteDay,
          claimDay: product.claim,
          onDayChanged: deleted.complete,
          onBack: () {},
          onHome: () {},
        ),
      );
      await tester.runAsync(
        () => dayLoaded.future.timeout(const Duration(seconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('5,000걸음'), findsOneWidget);
      expect(find.byKey(const ValueKey('records_claim')), findsNothing);
      await capture('activity-server-day');
      await tester.ensureVisible(
        find.byKey(const ValueKey('records_delete_day')),
      );
      await tester.tap(find.byKey(const ValueKey('records_delete_day')));
      await tester.pumpAndSettle();
      await capture('activity-server-delete-confirm');
      await tester.tap(find.byKey(const ValueKey('records_delete_confirm')));
      final deletion = await tester.runAsync(
        () => deleted.future.timeout(const Duration(seconds: 20)),
      );
      expect(deletion!.isDeleted, isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('records_deleted')), findsOneWidget);
      await capture('activity-server-deleted');
      final tombstone = await product.repository.day(date);
      expect(tombstone.deleted, isTrue);
      expect(tombstone.deletionVersion, greaterThan(0));
      expect(tombstone.steps, isNull);
      expect(tombstone.routes, isEmpty);
      await product.sync();
      expect(product.error, isNull);
      expect((await product.repository.day(date)).deleted, isTrue);
      expect((await product.loadMonth(date)).day(date.day)!.isDeleted, isTrue);
      await mount(
        PhotoScreen(
          dogAssetPath: meeting.state.candidate!.spritePath,
          dogName: meeting.state.name,
          adapter: PlatformPhotoAdapter(),
          onBack: () {},
          onHome: () {},
        ),
      );
      final photo = tester.widget<PhotoScreen>(find.byType(PhotoScreen));
      expect(photo.dogName, profile.name);
      expect(photo.dogAssetPath, meeting.state.candidate!.spritePath);
      final editor = tester
          .state<PhotoScreenState>(find.byType(PhotoScreen))
          .editor;
      if (editor.dog == null && editor.busy) {
        final ready = Completer<void>();
        void changed() {
          if (!editor.busy && !ready.isCompleted) ready.complete();
        }

        editor.addListener(changed);
        await tester.runAsync(
          () => ready.future.timeout(const Duration(seconds: 20)),
        );
        editor.removeListener(changed);
      }
      expect(editor.dog, isNotNull);
      await tester.pumpAndSettle();
      expect(find.text('${profile.name}를 사진에 담아 보세요.'), findsOneWidget);
      await capture('activity-server-photo-profile');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
