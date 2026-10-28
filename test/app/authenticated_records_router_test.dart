import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/billing/billing_screen.dart';
import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_providers.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/daily_activity/product_controller_test.dart'
    show AccountRepository;
import '../features/quiz/authenticated_quiz_test.dart' show Quizzes;
import '../features/first_meeting/domain/first_meeting_test.dart'
    show MemoryStorage;
import '../features/photo/photo_screen_test.dart' show idle;
import '../features/first_meeting/domain/authenticated_profile_test.dart'
    show Profiles, view;

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('RECORDS_RENDER')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${Platform.environment['RUN_TMP']}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'signed out and unfinished profile cannot open protected routes',
    (tester) async {
      if (appFlavor == 'dev') return;
      final meeting = FirstMeetingController(storage: MemoryStorage());
      await meeting.initialize();
      for (final controller in [null, meeting]) {
        final container = ProviderContainer(
          overrides: [
            authenticatedMeetingControllerProvider.overrideWithValue(
              controller,
            ),
            authenticatedProductControllerProvider.overrideWith(
              (ref) => throw StateError('Protected product accessed'),
            ),
          ],
        );
        final router = container.read(routerProvider);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        for (final route in [
          '/photo',
          '/records',
          '/records/2026-10-15',
          '/quiz',
          '/billing',
          '/wardrobe',
          '/settings',
          '/settings/steps',
          '/settings/info',
          '/settings/logout',
          '/settings/delete',
        ]) {
          router.go(route);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
      meeting.dispose();
    },
  );

  testWidgets(
    'completed account opens photo with actual dog and record routes',
    (tester) async {
      if (appFlavor == 'dev') return;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final family in ['Pretendard', 'Galmuri11']) {
          final font = FontLoader(family)
            ..addFont(
              rootBundle.load(
                family == 'Pretendard'
                    ? 'assets/fonts/PretendardVariable.ttf'
                    : 'assets/fonts/Galmuri11.ttf',
              ),
            );
          await font.load();
        }
      });
      final profiles = Profiles()..current = view(name: '실제친구');
      final meeting = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: profiles,
      );
      await meeting.initialize();
      final repository = AccountRepository();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final product = ProductController(repository, steps, null, account: 'A');
      final quizzes = Quizzes();
      final quiz = QuizController(quizzes, isCurrentAccount: () => true);
      final container = ProviderContainer(
        overrides: [
          authenticatedMeetingControllerProvider.overrideWithValue(meeting),
          authenticatedProductControllerProvider.overrideWithValue(product),
          authenticatedQuizControllerProvider.overrideWithValue(quiz),
          dailyStepsControllerProvider.overrideWithValue(steps),
        ],
      );
      final router = container.read(routerProvider);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp.router(
            theme: meetingTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'records-home');
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/settings',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings_billing')),
      );
      await tester.tap(find.byKey(const ValueKey('settings_billing')));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/billing',
      );
      expect(find.byType(BillingScreen), findsOneWidget);
      router.go('/photo');
      await tester.runAsync(() => tester.pump());
      await tester.runAsync(
        () => idle(tester.state<PhotoScreenState>(find.byType(PhotoScreen))),
      );
      await tester.pumpAndSettle();
      final photo = tester.widget<PhotoScreen>(find.byType(PhotoScreen));
      expect(photo.dogName, '실제친구');
      expect(photo.dogAssetPath, meeting.state.candidate!.spritePath);
      await capture(tester, boundary, 'records-photo');
      router.go('/records');
      await tester.pumpAndSettle();
      expect(find.byType(RecordsCalendarScreen), findsOneWidget);
      final calendar = tester.widget<RecordsCalendarScreen>(
        find.byType(RecordsCalendarScreen),
      );
      // Today's goal and the account's reads feed the tiles and the card.
      expect(calendar.todayGoal, meeting.state.goal);
      expect(calendar.loadSummary, isNotNull);
      expect(calendar.loadQuiz, isNotNull);
      await capture(tester, boundary, 'records-calendar');
      router.go('/records/invalid');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/records');
      router.go('/records/2026-10-15');
      await tester.pumpAndSettle();
      expect(find.byType(RecordDayScreen), findsOneWidget);
      // Sub screens take the user's own sprite from the router (guide 3.6).
      final record = tester.widget<RecordDayScreen>(
        find.byType(RecordDayScreen),
      );
      expect(record.dogAsset, meeting.state.candidate!.spritePath);
      // A past date gets no goal; only today's is known (guide 7.1-5).
      expect(record.goal, isNull);
      expect(record.loadQuiz, isNotNull);
      expect(find.byKey(const ValueKey('reward_free_claim')), findsOneWidget);
      await capture(tester, boundary, 'records-day');
      await tester.ensureVisible(
        find.byKey(const ValueKey('records_delete_day')),
      );
      await tester.tap(find.byKey(const ValueKey('records_delete_day')));
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'records-delete-confirm');
      await tester.tap(find.byKey(const ValueKey('records_delete_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('records_deleted')), findsOneWidget);
      await capture(tester, boundary, 'records-deleted');
      expect(repository.calls, isNot(contains('dev')));
      expect(repository.calls, isNot(contains('quiz')));
      router.go('/quiz');
      await tester.pumpAndSettle();
      expect(find.byType(AuthenticatedQuizScreen), findsOneWidget);
      expect(
        tester
            .widget<AuthenticatedQuizScreen>(
              find.byType(AuthenticatedQuizScreen),
            )
            .dogAsset,
        meeting.state.candidate!.spritePath,
      );
      expect(find.byKey(const ValueKey('quiz_1_choice_0')), findsOneWidget);
      container.updateOverrides([
        authenticatedMeetingControllerProvider.overrideWithValue(null),
        authenticatedProductControllerProvider.overrideWithValue(null),
        authenticatedQuizControllerProvider.overrideWithValue(null),
        dailyStepsControllerProvider.overrideWithValue(steps),
      ]);
      final signedOut = container.read(routerProvider);
      await tester.pumpWidget(MaterialApp.router(routerConfig: signedOut));
      signedOut.go('/records/2026-10-15');
      await tester.pumpAndSettle();
      expect(signedOut.routeInformationProvider.value.uri.path, '/');
      expect(find.byType(RecordDayScreen), findsNothing);
      signedOut.go('/quiz');
      await tester.pumpAndSettle();
      expect(signedOut.routeInformationProvider.value.uri.path, '/');
      expect(find.byType(AuthenticatedQuizScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      product.dispose();
      quiz.dispose();
      quizzes.client.close();
      steps.dispose();
      meeting.dispose();
      repository.client.close();
    },
  );
}
