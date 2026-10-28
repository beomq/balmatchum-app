import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';

import '../daily_activity/product_controller_test.dart'
    show AccountRepository, outfitStore;

class MemoryStore implements FirstMeetingStorage {
  String? value;
  bool failRead = false;
  @override
  Future<String?> read() async {
    if (failRead) throw Exception('read unavailable');
    return value;
  }

  @override
  Future<void> write(String payload) async {
    value = payload;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  testWidgets('catalog pager reopens at the chosen breed', (tester) async {
    // Given the catalog step of a fresh local meeting.
    final c = FirstMeetingController(storage: MemoryStore());
    await c.initialize();
    await c.enter();
    await c.chooseCatalog();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final position = find.byKey(const ValueKey('breed_pager_position'));
    expect(tester.widget<Text>(position).data, '1 / 30');
    // When G5's first breed is selected from its tab.
    final breed = FirstMeetingCatalog.groups[4].breeds.first;
    await tester.tap(find.byKey(const ValueKey('breed_group_G5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('breed_${breed.id}')));
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.confirm);
    expect(c.state.candidate!.id, breed.id);
    // Then going back, and a restart, show that breed's card again.
    await tester.ensureVisible(find.text('다시 고르기'));
    await tester.tap(find.text('다시 고르기'));
    await tester.pumpAndSettle();
    final shown = '${FirstMeetingCatalog.breeds.indexOf(breed) + 1} / 30';
    expect(tester.widget<Text>(position).data, shown);
    final restored = FirstMeetingController(storage: c.storage);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: restored),
      ),
    );
    await tester.pumpAndSettle();
    expect(restored.state.step, FirstMeetingStep.catalog);
    expect(tester.widget<Text>(position).data, shown);
    await tester.pumpWidget(const SizedBox.shrink());
    restored.dispose();
    c.dispose();
  });

  testWidgets('home unavailable action and confirmed reset are honest', (
    tester,
  ) async {
    final c = FirstMeetingController(storage: MemoryStore());
    await c.initialize();
    await c.enter();
    await c.chooseMethod(FirstMeetingMethod.catalog);
    await c.selectBreed('shih-tzu');
    await c.confirmCandidate();
    await c.updateName('몽글');
    await c.updateSex(DogSex.female);
    await c.submitName();
    await c.complete();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('home_reward')));
    await tester.tap(find.byKey(const ValueKey('home_reward')));
    await tester.pumpAndSettle();
    expect(find.textContaining('포함되지 않은 기능'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Dev 체험 초기화'));
    await tester.tap(find.byTooltip('Dev 체험 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(c.state.isComplete, isTrue);
    await tester.tap(find.byTooltip('Dev 체험 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('체험 초기화'));
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.login);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
  ]) {
    testWidgets('login controls reachable at $size double text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = FirstMeetingController(storage: MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: FirstMeetingScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['카카오', '네이버', 'Apple', 'Google']) {
        final button = find.textContaining(label).first;
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
  testWidgets('initial read failure has explicit successful retry', (
    tester,
  ) async {
    final store = MemoryStore()..failRead = true;
    final c = FirstMeetingController(storage: store);
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.isRestored, isFalse);
    expect(find.textContaining('카카오'), findsNothing);
    store.failRead = false;
    await tester.tap(find.text('체험 기록 다시 읽기'));
    await tester.pumpAndSettle();
    expect(c.isRestored, isTrue);
    await tester.tap(find.textContaining('카카오').first);
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.method);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  testWidgets('recommendation results can open full catalog', (tester) async {
    final c = FirstMeetingController(storage: MemoryStore());
    await c.initialize();
    await c.enter();
    await c.chooseMethod(FirstMeetingMethod.recommendation);
    await c.answer(false);
    await c.answer(false);
    await c.answer(false);
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('30종 직접 고르기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.catalog);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  for (final width in [
    320.0,
    390.0,
    768.0,
    824.0,
    839.0,
    840.0,
    1024.0,
    1440.0,
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('name and goal click flow width $width text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(
          width,
          width == 320
              ? 568
              : width == 390
              ? 844
              : 1024,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryStore();
        final c = FirstMeetingController(storage: store);
        await c.initialize();
        await c.enter();
        await c.chooseMethod(FirstMeetingMethod.catalog);
        await c.selectBreed('shih-tzu');
        await c.confirmCandidate();
        await tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: FirstMeetingScreen(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('meeting_name')),
          '몽글 12',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('암컷'));
        await tester.tap(find.text('암컷'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('이름과 성별 저장'));
        await tester.tap(find.text('이름과 성별 저장'));
        await tester.pumpAndSettle();
        expect(c.state.step, FirstMeetingStep.goal);
        final start = find.byKey(const ValueKey('meeting_goal_start'));
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(c.state.isComplete, isTrue);
        final count = find.byKey(const ValueKey('daily_steps_count'));
        expect(count, findsOneWidget);
        final dog = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  c.state.candidate!.spritePath,
        );
        final bubble = find.byWidgetPredicate(
          (widget) => widget is Text && widget.style?.fontFamily == 'Galmuri11',
        );
        expect(dog, findsOneWidget);
        expect(bubble, findsOneWidget);
        expect(
          tester.getRect(dog).top,
          greaterThan(tester.getRect(bubble).bottom),
        );
        final status = tester.getRect(count);
        if (width >= 840) {
          expect(status.left, greaterThan(tester.getRect(dog).right));
        } else {
          expect(status.top, greaterThan(tester.getRect(dog).bottom));
        }
        expect(tester.takeException(), isNull);
        final restored = FirstMeetingController(storage: store);
        await restored.initialize();
        expect(restored.state.name, '몽글 12');
        expect(restored.state.step, FirstMeetingStep.home);
        restored.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      });
    }
  }

  testWidgets('home draws the worn vest over the unchanged companion', (
    tester,
  ) async {
    final c = FirstMeetingController(storage: MemoryStore());
    await c.initialize();
    await c.enter();
    await c.chooseMethod(FirstMeetingMethod.catalog);
    await c.selectBreed('shih-tzu');
    await c.confirmCandidate();
    await c.updateName('몽글');
    await c.updateSex(DogSex.female);
    await c.submitName();
    await c.complete();
    final repository = AccountRepository()
      ..wardrobeOutfits = outfitStore(owned: true, equipped: 'vest-low-v');
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final product = ProductController(repository, steps, null, account: 'A');
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c, product: product),
      ),
    );
    await tester.pumpAndSettle();
    const base = AssetImage('assets/first_meeting/dogs/shih-tzu.png');
    final layer = find.byKey(const ValueKey('home_dog_outfit'));
    expect(find.image(base), findsOneWidget);
    expect(
      tester.widget<Image>(layer).image,
      const AssetImage('assets/wardrobe/vest/shih-tzu.png'),
    );
    expect(tester.getRect(layer), tester.getRect(find.image(base)));
    repository.wardrobeOutfits = outfitStore(owned: true);
    await product.refresh();
    await tester.pump();
    expect(layer, findsNothing);
    expect(find.image(base), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    product.dispose();
    steps.dispose();
    c.dispose();
    repository.client.close();
  });
}
