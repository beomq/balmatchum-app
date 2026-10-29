import 'dart:async';

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/account_deletion.dart';
import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/billing/billing_screen.dart';
import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/quiz_providers.dart';
import 'package:balmatchum_app/features/settings/settings_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/duo_viewports.dart';
import '../daily_activity/product_controller_test.dart' show AccountRepository;
import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;

const _cleared = LogoutOutcome(
  session: SessionLogoutOutcome(serverRevoked: true, localCleared: true),
  sdkLoggedOut: true,
);

/// The signed-in app on the real router, with fake deletion and logout
/// services at the provider seams the router reads.
Future<GoRouter> pumpApp(
  WidgetTester tester,
  FirstMeetingController meeting, {
  Future<void> Function()? deleteRemote,
  Future<LogoutOutcome> Function()? logout,
}) async {
  final steps = DailyStepsController(
    readSteps: () async => const DailyStepsResult(DailyStepsStatus.empty, null),
  );
  final repository = AccountRepository();
  final product = ProductController(repository, steps, null, account: 'A');
  final container = ProviderContainer(
    overrides: [
      authenticatedMeetingControllerProvider.overrideWithValue(meeting),
      authenticatedProductControllerProvider.overrideWithValue(product),
      authenticatedQuizControllerProvider.overrideWithValue(null),
      dailyStepsControllerProvider.overrideWithValue(steps),
      logoutProvider.overrideWithValue(logout ?? () async => _cleared),
      accountDeletionProvider.overrideWithValue(
        AccountDeletion(
          deleteRemote: deleteRemote ?? () async {},
          clearLocal: () async {},
          signOut: () async {},
          markPending: () async {},
          clearPending: () async {},
          wasRemoteDeleted: () async => false,
          markRemoteDeleted: () async {},
          revokeProviders: () async {},
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    product.dispose();
    steps.dispose();
    repository.client.close();
  });
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    MaterialApp.router(theme: meetingTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<FirstMeetingController> signedIn(Profiles server) async {
  final c = FirstMeetingController(
    storage: MemoryStorage(),
    profileRepository: server,
  );
  await c.initialize();
  return c;
}

String location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

Future<void> tapVisible(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'deletion requires confirmation and blocks settings while pending',
    (tester) async {
      if (appFlavor == 'dev') return;
      final c = await signedIn(Profiles()..current = view());
      final release = Completer<void>();
      var calls = 0;
      final router = await pumpApp(
        tester,
        c,
        deleteRemote: () async {
          calls++;
          await release.future;
        },
      );
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(location(router), '/settings');
      // Opening the confirmation and cancelling it delete nothing.
      await tapVisible(tester, 'settings_delete_account');
      expect(location(router), '/settings/delete');
      expect(calls, 0);
      await tapVisible(tester, 'account_deletion_cancel');
      expect(location(router), '/settings');
      expect(calls, 0);
      await tapVisible(tester, 'settings_delete_account');
      await tester.tap(find.byKey(const ValueKey('account_deletion_confirm')));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('account_deletion_lock')),
            )
            .absorbing,
        isTrue,
      );
      release.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  for (final duo in [false, true]) {
    testWidgets('${duo ? 'the Duo rail' : 'the home button'} opens settings; '
        'billing returns to it and back goes home', (tester) async {
      if (appFlavor == 'dev') return;
      if (duo) {
        useDuoViewport(tester, 'outer portrait');
      } else {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      final c = await signedIn(Profiles()..current = view());
      final router = await pumpApp(tester, c);
      await tester.tap(
        duo
            ? find.byKey(const ValueKey('duo_rail_settings'))
            : find.byTooltip('설정'),
      );
      await tester.pumpAndSettle();
      expect(location(router), '/settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tapVisible(tester, 'settings_billing');
      expect(location(router), '/billing');
      expect(find.byType(BillingScreen), findsOneWidget);
      // Billing's own back, in the top bar or the Duo rail.
      await tester.tap(
        find.byKey(ValueKey(duo ? 'duo_rail_back' : 'product_back')),
      );
      await tester.pumpAndSettle();
      expect(location(router), '/settings');
      await tester.tap(
        find.byKey(ValueKey(duo ? 'duo_rail_back' : 'product_back')),
      );
      await tester.pumpAndSettle();
      expect(location(router), '/');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('settings save retry and logout at width $width', (
      tester,
    ) async {
      if (appFlavor == 'dev') return;
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = Profiles()..current = view();
      final c = await signedIn(server);
      var logoutCalls = 0;
      final router = await pumpApp(
        tester,
        c,
        logout: () async {
          logoutCalls++;
          return _cleared;
        },
      );
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      await tapVisible(tester, 'settings_profile');
      await tester.enterText(
        find.byKey(const ValueKey('settings_name')),
        '새친구',
      );
      await tapVisible(tester, 'settings_name_save');
      expect(c.state.name, '새친구');
      server.loseResponse = true;
      await tapVisible(tester, 'settings_goal_row');
      await tester.enterText(
        find.byKey(const ValueKey('settings_goal')),
        '7000',
      );
      await tapVisible(tester, 'settings_goal_save');
      expect(c.hasPendingMutation, isTrue);
      server.loseResponse = false;
      await tapVisible(tester, 'settings_edit_retry');
      expect(c.state.goal, 7000);
      await tapVisible(tester, 'settings_logout');
      expect(location(router), '/settings/logout');
      await tapVisible(tester, 'logout_confirm');
      expect(logoutCalls, 1);
      // A cleared device leaves the confirmation; the session change then
      // replaces the signed-in routes.
      expect(location(router), '/settings');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
}
