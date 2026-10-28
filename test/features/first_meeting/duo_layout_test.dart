import 'dart:async';

import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_widgets.dart';
import 'package:balmatchum_app/features/settings/settings_pages.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_signin_kit/social_signin_kit.dart';

import '../../support/duo_viewports.dart';
import '../daily_activity/product_controller_test.dart' show AccountRepository;
import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;
import 'name_input_test.dart' show PausedStore;

/// Holds the first storage read so the loading page stays on screen.
class _HeldReadStorage extends MemoryStorage {
  final release = Completer<void>();

  @override
  Future<String?> read() async {
    await release.future;
    return super.read();
  }
}

void main() {
  void usePadding(WidgetTester tester, Size size, FakeViewPadding padding) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    tester.view.padding = padding;
    addTearDown(tester.view.reset);
  }

  const normalIPhones = [
    ('portrait', Size(390, 844), FakeViewPadding(top: 177, bottom: 102)),
    (
      'landscape',
      Size(844, 390),
      FakeViewPadding(left: 177, right: 177, bottom: 63),
    ),
  ];

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
          'name' => find.byKey(const ValueKey('meeting_name_submit')),
          'goal' => find.byKey(const ValueKey('meeting_goal_start')),
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
      // Given settings > service info with a successful URL launcher.
      useDuoViewport(tester, viewport.key);
      final opened = <Uri>[];
      await tester.pumpWidget(
        duoHost(
          ServiceInfoScreen(
            onBack: () {},
            onHome: () {},
            openUrl: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // When its privacy link is activated.
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

    for (final (name, size, padding) in normalIPhones) {
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

  group('Duo onboarding rail', () {
    final back = find.byKey(const ValueKey('duo_rail_back'));
    final topBack = find.byKey(const ValueKey('meeting_back'));

    /// Walks a Dev first meeting forward until it reaches [step].
    Future<FirstMeetingController> meetingAt(
      FirstMeetingStep step, {
      FirstMeetingStorage? storage,
    }) async {
      final c = FirstMeetingController(storage: storage ?? MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      final recommend =
          step == FirstMeetingStep.question || step == FirstMeetingStep.results;
      final moves = <Future<void> Function()>[
        c.enter,
        if (recommend) ...[
          c.chooseRecommendation,
          for (var i = 0; i < 3; i++) () => c.answer(false),
        ] else ...[
          c.chooseCatalog,
          () => c.selectBreed('shih-tzu'),
          c.confirmCandidate,
          () => c.updateName('몽글'),
          () => c.updateSex(DogSex.female),
          c.submitName,
        ],
      ];
      for (final move in moves) {
        if (c.state.step == step) break;
        await move();
      }
      expect(c.state.step, step);
      return c;
    }

    for (final (step, previous) in const [
      (FirstMeetingStep.method, FirstMeetingStep.login),
      (FirstMeetingStep.question, FirstMeetingStep.method),
      (FirstMeetingStep.results, FirstMeetingStep.method),
      (FirstMeetingStep.catalog, FirstMeetingStep.method),
      (FirstMeetingStep.confirm, FirstMeetingStep.catalog),
      (FirstMeetingStep.name, FirstMeetingStep.confirm),
      (FirstMeetingStep.goal, FirstMeetingStep.name),
    ]) {
      testWidgets('outer portrait ${step.name} moves back to the rail', (
        tester,
      ) async {
        // Given the measured outer panel at this onboarding step.
        useDuoViewport(tester, 'outer portrait');
        final c = await meetingAt(step);
        await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
        await tester.pumpAndSettle();
        // Then back is the only rail button, on the bar axis at the bottom.
        expect(back.hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DuoRail),
            matching: find.byType(IconButton),
          ),
          findsOneWidget,
        );
        expect(tester.getRect(back).center.dx, closeTo(418, 1));
        expect(tester.getRect(back).bottom, closeTo(642, 1));
        expect(find.byTooltip('뒤로'), findsOneWidget);
        // And the top bar no longer repeats it.
        expect(topBack, findsNothing);
        // When the rail back is tapped.
        await tester.tap(back);
        await tester.pumpAndSettle();
        // Then the step goes back like the top-bar back did.
        expect(c.state.step, previous);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('authenticated method step shows no back anywhere', (
      tester,
    ) async {
      // Given a signed-in account without a profile, which starts at method.
      final c = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: Profiles(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.state.step, FirstMeetingStep.method);
      expect(c.canGoBack, isFalse);
      // When it shows on the Duo outer panel.
      useDuoViewport(tester, 'outer portrait');
      await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
      await tester.pumpAndSettle();
      // Then the column is painted without a back button.
      expect(find.byType(DuoRail), findsOneWidget);
      expect(back, findsNothing);
      expect(topBack, findsNothing);
      // And a normal iPhone shows no top-bar back either.
      await tester.pumpWidget(const SizedBox.shrink());
      final (_, size, padding) = normalIPhones.first;
      usePadding(tester, size, padding);
      await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byType(DuoRail), findsNothing);
      expect(topBack, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a busy step disables the rail back like the top bar', (
      tester,
    ) async {
      // Given the name step whose next storage write is held open.
      useDuoViewport(tester, 'outer portrait');
      final store = PausedStore();
      final c = await meetingAt(FirstMeetingStep.name, storage: store);
      await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
      await tester.pumpAndSettle();
      VoidCallback? onBack() => tester.widget<IconButton>(back).onPressed;
      expect(onBack(), isNotNull);
      // When a save is in flight.
      store.writeStarted = Completer<void>();
      store.writeReleased = Completer<void>();
      final saving = c.updateSex(DogSex.male);
      await store.writeStarted!.future.timeout(const Duration(seconds: 5));
      await tester.pump();
      // Then the rail keeps back but disables it, and the top bar stays empty.
      expect(c.isBusy, isTrue);
      expect(onBack(), isNull);
      expect(topBack, findsNothing);
      // And back is enabled again once the save completes.
      store.writeReleased!.complete();
      await saving;
      await tester.pumpAndSettle();
      expect(onBack(), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text keeps back as a 44 pt rail icon', (tester) async {
      // Given the outer panel with doubled text size at the goal step.
      useDuoViewport(tester, 'outer portrait');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await meetingAt(FirstMeetingStep.goal);
      // When the step is shown.
      await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
      await tester.pumpAndSettle();
      // Then the compact rail keeps the 44 pt back without overflow.
      expect(tester.getSize(back), const Size.square(44));
      expect(tester.getRect(back).bottom, closeTo(642, 1));
      expect(topBack, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open keyboard returns back to the top bar', (tester) async {
      // Given the goal step with its rail on the outer panel.
      useDuoViewport(tester, 'outer portrait');
      final c = await meetingAt(FirstMeetingStep.goal);
      await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);
      // When a keyboard inset appears.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      // Then the rail hides and the top bar shows back again.
      expect(find.byType(DuoRail), findsNothing);
      expect(topBack.hitTestable(), findsOneWidget);
      // And the rail returns once the keyboard closes.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);
      expect(topBack, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading and login paint an empty rail', (tester) async {
      // Given the outer panel and a Dev meeting whose first read is held.
      useDuoViewport(tester, 'outer portrait');
      final storage = _HeldReadStorage();
      final c = FirstMeetingController(storage: storage);
      addTearDown(c.dispose);
      // When the screen starts loading.
      await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
      await tester.pump();
      // Then the loading page already paints the empty side column.
      expect(find.text('이 기기의 체험 기록을 읽고 있어요.'), findsOneWidget);
      expectEmptyDuoRail(tester);
      // When the read completes on the login step.
      storage.release.complete();
      await tester.pumpAndSettle();
      // Then login keeps the empty column and offers no back anywhere.
      expect(c.state.step, FirstMeetingStep.login);
      expectEmptyDuoRail(tester);
      expect(back, findsNothing);
      expect(topBack, findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final (name, size, padding) in normalIPhones) {
      testWidgets('normal iPhone $name keeps the top-bar back', (tester) async {
        // Given an ordinary iPhone safe area at the confirm step.
        usePadding(tester, size, padding);
        final c = await meetingAt(FirstMeetingStep.confirm);
        await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: c)));
        await tester.pumpAndSettle();
        // Then no rail is drawn and the top-bar back still works.
        expect(find.byType(DuoRail), findsNothing);
        expect(back, findsNothing);
        await tester.tap(topBack);
        await tester.pumpAndSettle();
        expect(c.state.step, FirstMeetingStep.catalog);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
