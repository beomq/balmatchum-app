import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/onboarding_widgets.dart';
import 'package:balmatchum_app/features/records/product_page.dart'
    show formatCount;
import 'package:balmatchum_app/features/wardrobe/dog_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'domain/authenticated_profile_test.dart' show Profiles;
import 'domain/first_meeting_test.dart' show MemoryStorage;

final _value = find.byKey(const ValueKey('meeting_goal_value'));
final _minus = find.byKey(const ValueKey('meeting_goal_minus'));
final _plus = find.byKey(const ValueKey('meeting_goal_plus'));
final _start = find.byKey(const ValueKey('meeting_goal_start'));
final _estimate = find.byKey(const ValueKey('meeting_goal_estimate'));
final _range = find.byKey(const ValueKey('meeting_goal_range'));
final _line = find.byKey(const ValueKey('meeting_goal_line'));
final _badge = find.byKey(const ValueKey('meeting_goal_recommended'));
final _back = find.byKey(const ValueKey('meeting_back'));
const _presets = FirstMeetingController.goalPresets;
Finder _preset(int value) => find.byKey(ValueKey('meeting_goal_preset_$value'));

/// A first meeting at the goal step; [server] makes it a signed-in account.
Future<FirstMeetingController> atGoal({
  Profiles? server,
  MemoryStorage? storage,
}) async {
  final c = FirstMeetingController(
    storage: storage ?? MemoryStorage(),
    profileRepository: server,
  );
  await c.initialize();
  if (server == null) await c.enter();
  await c.chooseCatalog();
  await c.selectBreed('pug');
  await c.confirmCandidate();
  await c.updateName('보리');
  await c.updateSex(DogSex.female);
  await c.submitName();
  expect(c.state.step, FirstMeetingStep.goal);
  return c;
}

/// An iPhone 17 safe area, or [size] with no insets.
Future<void> show(
  WidgetTester tester,
  FirstMeetingController c, {
  Size size = const Size(402, 874),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  if (size == const Size(402, 874)) {
    tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
  }
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: duoHost(FirstMeetingScreen(controller: c)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  String shown(WidgetTester tester) => tester.widget<Text>(_value).data!;
  String text(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).data!;
  GoalPresetCard card(WidgetTester tester, int value) =>
      tester.widget<GoalPresetCard>(_preset(value));
  VoidCallback? minus(WidgetTester tester) =>
      tester.widget<IconButton>(_minus).onPressed;
  VoidCallback? plus(WidgetTester tester) =>
      tester.widget<IconButton>(_plus).onPressed;
  VoidCallback? start(WidgetTester tester) =>
      tester.widget<FilledButton>(_start).onPressed;
  Finder badgeOn(int value) =>
      find.descendant(of: _preset(value), matching: _badge);

  testWidgets('the recommended goal starts selected and wears the badge', (
    tester,
  ) async {
    final c = await atGoal();
    addTearDown(c.dispose);
    await show(tester, c);
    expect(c.state.goalInput, '${FirstMeetingController.recommendedGoal}');
    expect(shown(tester), formatCount(5000));
    final nav = tester.widget<OnboardingStepNav>(
      find.byType(OnboardingStepNav),
    );
    expect((nav.step, nav.total), (3, 3));
    for (final value in _presets) {
      expect(card(tester, value).selected, value == 5000);
      expect(badgeOn(value), value == 5000 ? findsOneWidget : findsNothing);
    }
    expect(start(tester), isNotNull);
  });

  testWidgets('a card selects its value and the badge stays on 5,000', (
    tester,
  ) async {
    final c = await atGoal();
    addTearDown(c.dispose);
    await show(tester, c);
    await tester.tap(_preset(8000));
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '8000');
    expect(shown(tester), formatCount(8000));
    for (final value in _presets) {
      expect(card(tester, value).selected, value == 8000);
    }
    expect(badgeOn(5000), findsOneWidget);
    // A value off the cards selects none of them.
    await tester.tap(_plus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '8500');
    expect(shown(tester), formatCount(8500));
    for (final value in _presets) {
      expect(card(tester, value).selected, isFalse);
    }
    expect(badgeOn(5000), findsOneWidget);
  });

  testWidgets('the stepper moves by 500 and stops at 1,000 and 30,000', (
    tester,
  ) async {
    final c = await atGoal();
    addTearDown(c.dispose);
    await show(tester, c);
    await tester.tap(_plus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '5500');
    await tester.tap(_minus);
    await tester.pumpAndSettle();
    await tester.tap(_minus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '4500');
    // The low end.
    await c.updateGoal('1500');
    await tester.pumpAndSettle();
    await tester.tap(_minus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '1000');
    expect(minus(tester), isNull);
    expect(plus(tester), isNotNull);
    // The high end.
    await c.updateGoal('29500');
    await tester.pumpAndSettle();
    await tester.tap(_plus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '30000');
    expect(plus(tester), isNull);
    expect(minus(tester), isNotNull);
    expect(start(tester), isNotNull);
  });

  testWidgets('the estimate and the line follow the goal on screen', (
    tester,
  ) async {
    final c = await atGoal();
    addTearDown(c.dispose);
    await show(tester, c);
    final estimate = text(tester, _estimate);
    final line = text(tester, _line);
    expect(line, contains(formatCount(5000)));
    await tester.tap(_preset(10000));
    await tester.pumpAndSettle();
    expect(text(tester, _estimate), isNot(estimate));
    expect(text(tester, _line), isNot(line));
    expect(text(tester, _line), contains(formatCount(10000)));
    // The companion is the breed this meeting chose, not a fixed one.
    final dog = tester.widget<DogSprite>(
      find.descendant(
        of: find.byType(DogSpeechPreview),
        matching: find.byType(DogSprite),
      ),
    );
    expect(dog.asset, c.state.candidate!.spritePath);
    expect(c.state.candidate!.id, 'pug');
  });

  testWidgets('starting right after a card completes with that card', (
    tester,
  ) async {
    final c = await atGoal();
    addTearDown(c.dispose);
    await show(tester, c);
    // Both taps land before the card's save has finished.
    await tester.tap(_preset(8000));
    await tester.tap(_start);
    await tester.pumpAndSettle();
    expect(c.state.isComplete, isTrue);
    expect(c.state.goal, 8000);
  });

  testWidgets('a signed-in start sends the latest goal once and locks', (
    tester,
  ) async {
    final server = Profiles();
    final c = await atGoal(server: server);
    addTearDown(c.dispose);
    await show(tester, c);
    server.mutationStarted = Completer<void>();
    server.mutationRelease = Completer<void>();
    await tester.tap(_preset(10000));
    await tester.tap(_start);
    // A second tap in the same frame queues nothing.
    await tester.tap(_start, warnIfMissed: false);
    await server.mutationStarted!.future.timeout(const Duration(seconds: 5));
    await tester.pump();
    // While the request is open nothing can change or resend the goal.
    expect(c.isBusy, isTrue);
    expect(start(tester), isNull);
    expect(plus(tester), isNull);
    expect(minus(tester), isNull);
    expect(card(tester, 3000).onTap, isNull);
    expect(_back, findsNothing);
    server.mutationRelease!.complete();
    await tester.pumpAndSettle();
    expect(server.ids, hasLength(1));
    expect(server.payloads.single, '보리/10000');
    expect(c.state.isComplete, isTrue);
    expect(c.state.goal, 10000);
  });

  testWidgets('a second tap during a start that is refused sends nothing', (
    tester,
  ) async {
    // The server refuses the create, which clears the request; a second
    // completion queued behind it would otherwise send a new one.
    final server = Profiles()..conflict = true;
    final c = await atGoal(server: server);
    addTearDown(c.dispose);
    await show(tester, c);
    server.mutationStarted = Completer<void>();
    server.mutationRelease = Completer<void>();
    await tester.tap(_start);
    await server.mutationStarted!.future.timeout(const Duration(seconds: 5));
    // No frame has run, so the button has not turned disabled yet.
    await tester.tap(_start, warnIfMissed: false);
    server.mutationRelease!.complete();
    await tester.pumpAndSettle();
    expect(server.ids, hasLength(1));
    expect(c.profileError, 'staleRevision');
    expect(c.state.isComplete, isFalse);
    // The goal is kept and the start can be tried again.
    expect(shown(tester), formatCount(5000));
    expect(start(tester), isNotNull);
  });

  testWidgets('a lost answer keeps the goal and retries the same request', (
    tester,
  ) async {
    final server = Profiles()..loseResponse = true;
    final c = await atGoal(server: server);
    addTearDown(c.dispose);
    await show(tester, c);
    await tester.tap(_preset(8000));
    await tester.pumpAndSettle();
    await tester.tap(_start);
    await tester.pumpAndSettle();
    // The goal stays chosen and only the existing retry can resolve it.
    expect(c.hasPendingMutation, isTrue);
    expect(c.state.isComplete, isFalse);
    expect(shown(tester), formatCount(8000));
    expect(card(tester, 8000).selected, isTrue);
    expect(start(tester), isNull);
    expect(plus(tester), isNull);
    final retry = find.byType(OutlinedButton);
    expect(retry, findsOneWidget);
    expect(
      tester.getRect(retry).bottom,
      lessThanOrEqualTo(tester.getRect(_value).top),
    );
    server.loseResponse = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(server.ids, hasLength(2));
    expect(server.ids.toSet(), hasLength(1));
    expect(c.state.isComplete, isTrue);
    expect(c.state.goal, 8000);
  });

  testWidgets('back, return and restart keep the chosen goal', (tester) async {
    final storage = MemoryStorage();
    final c = await atGoal(storage: storage);
    addTearDown(c.dispose);
    await show(tester, c);
    await tester.tap(_preset(3000));
    await tester.pumpAndSettle();
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.name);
    await c.submitName();
    await tester.pumpAndSettle();
    expect(shown(tester), formatCount(3000));
    expect(card(tester, 3000).selected, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    final restored = FirstMeetingController(storage: storage);
    addTearDown(restored.dispose);
    await tester.pumpWidget(duoHost(FirstMeetingScreen(controller: restored)));
    await tester.pumpAndSettle();
    expect(restored.state.step, FirstMeetingStep.goal);
    expect(shown(tester), formatCount(3000));
    expect(card(tester, 3000).selected, isTrue);
  });

  testWidgets('a draft outside the range cannot start until it is fixed', (
    tester,
  ) async {
    final c = await atGoal();
    addTearDown(c.dispose);
    // A draft saved before the range existed.
    await c.updateGoal('40000');
    await show(tester, c);
    expect(shown(tester), formatCount(40000));
    expect(_range, findsOneWidget);
    expect(_estimate, findsNothing);
    expect(start(tester), isNull);
    expect(plus(tester), isNull);
    for (final value in _presets) {
      expect(card(tester, value).selected, isFalse);
    }
    await tester.tap(_minus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '30000');
    expect(_range, findsNothing);
    expect(start(tester), isNotNull);
    // A draft that is no number starts from the recommended goal.
    await c.updateGoal('');
    await tester.pumpAndSettle();
    expect(start(tester), isNull);
    await tester.tap(_plus);
    await tester.pumpAndSettle();
    expect(c.state.goalInput, '5500');
  });

  for (final (size, scale) in const [
    (Size(402, 874), 1.0),
    (Size(402, 874), 1.15),
    (Size(320, 568), 1.15),
    (Size(320, 568), 2.0),
  ]) {
    testWidgets('cards, companion and start never overlap at $size x$scale', (
      tester,
    ) async {
      final c = await atGoal();
      addTearDown(c.dispose);
      await show(tester, c, size: size, scale: scale);
      Rect rect(Finder finder) => tester.getRect(finder);
      final order = [
        rect(find.byType(OnboardingStepNav)),
        rect(find.byType(GoalStepper)),
        rect(_estimate),
        rect(find.byType(GoalPresetGrid)),
        rect(find.byType(DogSpeechPreview)),
        rect(find.byKey(const ValueKey('meeting_goal_no_penalty'))),
        rect(_start),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(order[i].top, greaterThanOrEqualTo(order[i - 1].bottom));
      }
      for (final value in _presets) {
        expect(rect(_preset(value)).bottom, lessThanOrEqualTo(order[4].top));
      }
      if (size == const Size(402, 874) && scale == 1) {
        // An iPhone 17 shows the start at the bottom without scrolling.
        expect(rect(_start).bottom, lessThanOrEqualTo(874 - 34));
        expect(_start.hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(_start);
      await tester.pumpAndSettle();
      expect(_start.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
