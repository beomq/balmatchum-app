import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import '../../support/duo_viewports.dart';
import '../daily_activity/product_controller_test.dart' show AccountRepository;
import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;

void main() {
  for (final viewport in duoViewports.entries) {
    for (final stage in ['catalog', 'name', 'goal']) {
      testWidgets('$stage fits Duo ${viewport.key}', (tester) async {
        // Given a first meeting at this stage and the actual panel size.
        useDuoViewport(tester, viewport.value);
        final c = FirstMeetingController(storage: MemoryStorage());
        addTearDown(c.dispose);
        await c.initialize();
        await c.enter();
        await c.chooseCatalog();
        if (stage != 'catalog') {
          await c.selectBreed('shih-tzu');
          await c.confirmCandidate();
        }
        if (stage == 'goal') {
          await c.updateName('몽글');
          await c.updateSex(DogSex.female);
          await c.submitName();
        }
        // When the real screen lays out its content.
        await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
        await tester.pumpAndSettle();
        // Then the final control is reachable without a layout exception.
        final control = switch (stage) {
          'catalog' => find.byKey(const ValueKey('meeting_catalog_page')),
          'name' => find.text('이름과 성별 저장'),
          'goal' => find.text('목표 저장하고 홈 보기'),
          _ => throw StateError('Unknown fixture stage'),
        };
        await tester.ensureVisible(control);
        expect(control.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('home and steps fit Duo ${viewport.key}', (tester) async {
      // Given the existing authenticated profile and product fakes.
      useDuoViewport(tester, viewport.value);
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: Profiles()..current = view(),
      );
      final repository = AccountRepository();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final product = ProductController(repository, steps, null, account: 'A');
      addTearDown(() {
        product.dispose();
        steps.dispose();
        c.dispose();
        repository.client.close();
      });
      // When the home loads its server-backed steps and rewards.
      await tester.pumpWidget(
        duoHost(
          FirstMeetingScreen(
            controller: c,
            dailySteps: steps,
            product: product,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Then both the companion and bottom actions remain reachable.
      final dog = find.image(
        const AssetImage('assets/first_meeting/dogs/pug.png'),
      );
      expect(dog, findsOneWidget);
      final action = find.text('퀴즈');
      await tester.ensureVisible(action);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('settings privacy link fits Duo ${viewport.key}', (
      tester,
    ) async {
      // Given an authenticated home with a successful URL launcher.
      useDuoViewport(tester, viewport.value);
      final opened = <Uri>[];
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: Profiles()..current = view(),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        duoHost(
          FirstMeetingScreen(
            controller: c,
            openUrl: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // When settings opens and its privacy link is activated.
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      final policy = find.byKey(const ValueKey('settings_privacy_policy'));
      await tester.ensureVisible(policy);
      expect(policy.hitTestable(), findsOneWidget);
      await tester.tap(policy);
      await tester.pumpAndSettle();
      // Then the published URL is dispatched with no rendering exception.
      expect(opened, [
        Uri.parse(
          'https://beomq.github.io/balmatchum-legal/privacy-policy.html',
        ),
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('login controls fit Duo ${viewport.key}', (tester) async {
      // Given the real login and existing unconfigured starter fake.
      useDuoViewport(tester, viewport.value);
      // When the screen is rendered at the panel size.
      await tester.pumpWidget(
        duoHost(const SignInScreen(starter: NotConnectedSignInStarter())),
      );
      await tester.pumpAndSettle();
      // Then every provider and the privacy control is reachable by scrolling.
      final buttons = find.descendant(
        of: find.byType(SocialButtonList),
        matching: find.byType(TextButton),
      );
      for (final button in buttons.evaluate().map(
        (e) => find.byWidget(e.widget),
      )) {
        await tester.ensureVisible(button);
        expect(button.hitTestable(), findsOneWidget);
      }
      final policy = find.byKey(const ValueKey('sign_in_privacy_policy'));
      await tester.ensureVisible(policy);
      expect(policy.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
