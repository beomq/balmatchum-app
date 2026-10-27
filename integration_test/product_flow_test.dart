import 'dart:async';

import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> changedTo(
  Listenable source,
  bool Function() predicate,
  Future<void> Function() action,
) async {
  final signal = Completer<void>();
  void changed() {
    if (predicate() && !signal.isCompleted) signal.complete();
  }

  source.addListener(changed);
  try {
    await action();
    changed();
    await signal.future.timeout(const Duration(seconds: 20));
  } finally {
    source.removeListener(changed);
  }
}

/// Renders real frames until [finder] matches. The home screen re-reads disk
/// storage asynchronously, which pumpAndSettle does not wait for.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (elapsed.elapsed > timeout) {
      throw TimeoutException('Not found: $finder', timeout);
    }
    await tester.pump();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('dev user sync claim purchase equip and disk restore', (
    tester,
  ) async {
    ProviderContainer createContainer() => ProviderContainer(
      overrides: [
        // Only the physical sensor is a fixture. Auth, HTTP, disk and UI are real.
        dailyStepsControllerProvider.overrideWith((ref) {
          final steps = DailyStepsController(
            readSteps: () async =>
                DailyStepsResult(DailyStepsStatus.available, {
                  'count': 5000,
                  'date': ProductRepository.dateKey(ProductRepository.today),
                  'observedAt': DateTime.now().toUtc().toIso8601String(),
                }),
          );
          ref.onDispose(steps.dispose);
          return steps;
        }),
      ],
    );
    var container = createContainer();
    final meeting = container.read(firstMeetingControllerProvider);
    await meeting.initialize();
    if (!meeting.state.isComplete) {
      await meeting.enter();
      await meeting.chooseCatalog();
      await meeting.selectBreed('pug');
      await meeting.confirmCandidate();
      await meeting.updateName('검증친구');
      await meeting.updateSex(DogSex.female);
      await meeting.submitName();
      await meeting.commit();
    }
    expect(meeting.state.isComplete, isTrue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tapText(String text) async {
      final finder = find.text(text);
      await pumpUntilFound(tester, finder);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }

    final product = container.read(productControllerProvider);
    await changedTo(
      product,
      () => !product.busy,
      () => tapText('개발 테스트 사용자 연결'),
    );
    expect(product.connected, isTrue, reason: product.error);
    expect(product.store?.balance, 10);
    expect(product.wallet?.balance, 0);
    await tester.pumpAndSettle();
    await changedTo(product, () => !product.busy, () => tapText('서버 동기화'));
    expect(product.error, isNull);
    expect(product.today?.steps, 5000);
    await tester.pumpAndSettle();
    await tapText('포인트 받기');
    await tester.pumpAndSettle();
    // steps-v1-20261019: 5,000 steps = 50 base points, free claim only.
    await changedTo(
      product,
      () => product.wallet?.balance == 50,
      () => tapText('무료 50 P 받기'),
    );
    await tester.pumpAndSettle();
    // The reward sheet stays open after a claim; dismiss it via its barrier.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('오늘 포인트'), findsNothing);
    await tapText('꾸미기');
    await tester.pumpAndSettle();
    await tapText('상점');
    await tester.pumpAndSettle();
    final cloudy = find.byKey(const ValueKey('wardrobe_theme_cloudy'));
    await tester.ensureVisible(cloudy);
    await tester.tap(cloudy);
    await tester.pumpAndSettle();
    final themeAction = find.byKey(const ValueKey('wardrobe_action'));
    await pumpUntilFound(tester, themeAction);
    await tester.ensureVisible(themeAction);
    await tester.tap(themeAction);
    await tester.pump();
    await tester.pumpAndSettle();
    await changedTo(
      product,
      () => product.store?.balance == 7,
      () => tapText('구매 확인'),
    );
    await tester.pumpAndSettle();
    await changedTo(
      product,
      () => product.store?.equippedTheme == 'cloudy',
      () => tapText('착용하기'),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-equipped-native');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    container = createContainer();
    await container.read(firstMeetingControllerProvider).initialize();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    final restored = container.read(productControllerProvider);
    await changedTo(
      restored,
      () => !restored.busy,
      () => tapText('개발 테스트 사용자 연결'),
    );
    expect(restored.connected, isTrue, reason: restored.error);
    expect(restored.store?.equippedTheme, 'cloudy');
    expect(restored.store?.balance, 7);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-restored-native');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
