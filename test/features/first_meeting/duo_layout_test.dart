import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_widgets.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart' as api;
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
        useDuoViewport(tester, viewport.key);
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
          'catalog' => find.byKey(const ValueKey('breed_pager_next')),
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
      useDuoViewport(tester, viewport.key);
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
      useDuoViewport(tester, viewport.key);
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
      useDuoViewport(tester, viewport.key);
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

  group('Duo side rail', () {
    const railIds = ['settings', 'records', 'quiz', 'wardrobe', 'photo'];
    Finder rail(String id) => find.byKey(ValueKey('duo_rail_$id'));

    void usePadding(WidgetTester tester, Size size, FakeViewPadding padding) {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      tester.view.padding = padding;
      addTearDown(tester.view.reset);
    }

    Future<List<String>> pumpHome(WidgetTester tester) async {
      final opened = <String>[];
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: Profiles()..current = view(),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        duoHost(
          FirstMeetingScreen(
            controller: c,
            onOpenRecords: () => opened.add('records'),
            onOpenQuiz: () => opened.add('quiz'),
            onOpenWardrobe: () => opened.add('wardrobe'),
            onOpenPhoto: () => opened.add('photo'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets(
      'outer portrait home moves shortcuts and settings to the rail',
      (tester) async {
        // Given the measured outer portrait insets.
        useDuoViewport(tester, 'outer portrait');
        // When the authenticated home is shown.
        final opened = await pumpHome(tester);
        // Then five rail buttons sit once each on the system bar axis.
        for (final id in railIds) {
          expect(rail(id).hitTestable(), findsOneWidget, reason: id);
          expect(
            tester.getRect(rail(id)).center.dx,
            closeTo(418, 1),
            reason: id,
          );
        }
        expect(tester.getRect(rail('photo')).bottom, closeTo(642, 1));
        expect(tester.getRect(rail('settings')).top, greaterThan(235));
        expect(find.byType(MeetingShortcuts), findsNothing);
        expect(find.byTooltip('설정'), findsOneWidget);
        expect(
          find.descendant(of: rail('settings'), matching: find.byTooltip('설정')),
          findsOneWidget,
        );
        expect(find.text('기록 보기'), findsNothing);
        await tester.tap(find.text('기록'));
        await tester.tap(rail('photo'));
        expect(opened, ['records', 'photo']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('rail quiz button carries the unanswered badge', (
      tester,
    ) async {
      // Given an unanswered quiz on the product controller.
      useDuoViewport(tester, 'outer portrait');
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: Profiles()..current = view(),
      );
      final repository = AccountRepository();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final product = ProductController(repository, steps, null)
        ..quiz = api.DailyQuiz(
          date: '2027-01-04',
          questionId: 'q1',
          question: 'q',
          choices: const ['a', 'b'],
          awardedPoints: 0,
          fixtureLabel: 'dev-fixture-v1',
        );
      addTearDown(() {
        product.dispose();
        steps.dispose();
        c.dispose();
        repository.client.close();
      });
      // When the home is shown.
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
      // Then only the quiz rail button shows the badge dot.
      bool badged(String id) => tester
          .widget<Badge>(
            find.descendant(of: rail(id), matching: find.byType(Badge)),
          )
          .isLabelVisible;
      expect(badged('quiz'), isTrue);
      expect(badged('records'), isFalse);
      expect(tester.takeException(), isNull);
    });

    for (final (name, size, padding) in [
      (
        'portrait',
        const Size(390, 844),
        const FakeViewPadding(top: 177, bottom: 102),
      ),
      (
        'landscape',
        const Size(844, 390),
        const FakeViewPadding(left: 177, right: 177, bottom: 63),
      ),
    ]) {
      testWidgets('normal iPhone $name keeps header settings and shortcuts', (
        tester,
      ) async {
        // Given ordinary iPhone safe areas.
        usePadding(tester, size, padding);
        // When the home is shown.
        final opened = await pumpHome(tester);
        // Then no rail is drawn and the existing controls remain.
        expect(find.byType(DuoRail), findsNothing);
        expect(find.byType(MeetingShortcuts), findsOneWidget);
        expect(find.byTooltip('설정'), findsOneWidget);
        expect(find.text('기록 보기'), findsNothing);
        final records = find.text('기록');
        await tester.ensureVisible(records);
        await tester.tap(records);
        expect(opened, ['records']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('split view puts the rail on the left edge', (tester) async {
      // Given a window whose system column sits on its left edge.
      usePadding(
        tester,
        const Size(466, 678),
        const FakeViewPadding(left: 252, bottom: 102),
      );
      // When the home is shown.
      await pumpHome(tester);
      // Then the rail is mirrored onto the left axis.
      for (final id in railIds) {
        expect(tester.getRect(rail(id)).center.dx, closeTo(48, 1), reason: id);
      }
      expect(find.byType(MeetingShortcuts), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text keeps an icon-only rail without overflow', (
      tester,
    ) async {
      // Given the outer panel with doubled text size.
      useDuoViewport(tester, 'outer portrait');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // When the home is shown.
      await pumpHome(tester);
      // Then every rail button is a 44 pt icon and nothing overflows.
      for (final id in railIds) {
        expect(tester.getSize(rail(id)), const Size.square(44), reason: id);
      }
      expect(
        find.descendant(of: find.byType(DuoRail), matching: find.byType(Text)),
        findsNothing,
      );
      expect(tester.getRect(rail('photo')).bottom, closeTo(642, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open keyboard hides the rail until it closes', (
      tester,
    ) async {
      // Given the outer portrait home with its rail.
      useDuoViewport(tester, 'outer portrait');
      await pumpHome(tester);
      expect(find.byType(DuoRail), findsOneWidget);
      // When a keyboard inset appears.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      // Then the home falls back to its own settings and shortcuts.
      expect(find.byType(DuoRail), findsNothing);
      expect(find.byType(MeetingShortcuts), findsOneWidget);
      expect(find.byTooltip('설정'), findsOneWidget);
      // And the rail returns once the keyboard closes.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(DuoRail), findsOneWidget);
      expect(find.byType(MeetingShortcuts), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
