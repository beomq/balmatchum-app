import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/first_meeting/data/first_meeting_file_storage.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local native first meeting click and disk restart', (
    tester,
  ) async {
    final store = FirstMeetingFileStorage.device();
    // This test owns only the separate Dev experience file, never real auth.
    final c = FirstMeetingController(storage: store);
    await c.initialize();
    await c.reset();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    if (c.isBusy) {
      final idle = Completer<void>();
      void changed() {
        if (!c.isBusy && !idle.isCompleted) idle.complete();
      }

      c.addListener(changed);
      try {
        changed();
        await idle.future.timeout(const Duration(seconds: 10));
      } finally {
        c.removeListener(changed);
      }
    }
    await tester.pumpAndSettle();
    final imageContext = tester.element(find.byType(FirstMeetingScreen));
    await Future.wait([
      for (final asset in [
        'assets/first_meeting/brand.png',
        'assets/social/kakao.png',
        'assets/social/naver.png',
        'assets/social/apple.png',
        'assets/social/google.png',
      ])
        precacheImage(
          AssetImage(asset),
          imageContext,
          onError: (error, stack) =>
              Error.throwWithStackTrace(error, stack ?? StackTrace.current),
        ),
    ]).timeout(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(c.isBusy, isFalse);
    expect(c.isRestored, isTrue);
    await binding.takeScreenshot('meeting-native-login');
    await tester.tap(find.textContaining('카카오').first);
    await tester.pumpAndSettle();
    expect(c.state.step, FirstMeetingStep.method);
    await binding.takeScreenshot('meeting-native-method');
    await tester.tap(find.text('성향으로 추천받기'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-question');
    await tester.tap(find.text('여유롭게'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('익숙한 길'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자기 페이스로 나란히 걷는 친구'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-recommendation');
    await tester.ensureVisible(find.byKey(const ValueKey('meeting_back')));
    await tester.tap(find.byKey(const ValueKey('meeting_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30종에서 직접 고르기'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-catalog');
    final shih = find.byKey(const ValueKey('breed_shih-tzu'));
    await tester.ensureVisible(shih);
    await tester.tap(shih);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-confirm');
    await tester.ensureVisible(find.text('이 친구로 결정'));
    await tester.tap(find.text('이 친구로 결정'));
    await tester.pumpAndSettle();
    final keyboard = Completer<void>();
    final observer = _KeyboardObserver(() {
      if (binding.platformDispatcher.views.first.viewInsets.bottom > 0 &&
          !keyboard.isCompleted) {
        keyboard.complete();
      }
    });
    binding.addObserver(observer);
    try {
      await tester.tap(find.byKey(const ValueKey('meeting_name')));
      await tester.pump();
      observer.didChangeMetrics();
      await keyboard.future.timeout(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('meeting_name')), '몽글');
      await tester.pumpAndSettle();
      await binding.takeScreenshot('meeting-native-os-keyboard');
      if (const bool.fromEnvironment('CAPTURE_OS_KEYBOARD')) {
        final gate = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        debugPrint('KEYBOARD_CAPTURE_READY:${gate.port}');
        try {
          final request = await gate.first.timeout(const Duration(minutes: 2));
          request.response.write('captured');
          await request.response.close();
        } finally {
          await gate.close(force: true);
        }
      }
    } finally {
      binding.removeObserver(observer);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('암컷'));
    await tester.tap(find.text('암컷'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-name');
    await tester.ensureVisible(find.text('이름과 성별 저장'));
    await tester.tap(find.text('이름과 성별 저장'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-goal');
    await tester.tap(find.text('목표 저장하고 홈 보기'));
    await tester.pumpAndSettle();
    expect(c.state.isComplete, isTrue);
    await binding.takeScreenshot('meeting-native-home');
    final met = c.state.firstMetAtUTC;
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    final restored = FirstMeetingController(
      storage: FirstMeetingFileStorage.device(),
    );
    await restored.initialize();
    expect(restored.state.firstMetAtUTC, met);
    expect(restored.state.name, '몽글');
    expect(restored.state.breedId, 'shih-tzu');
    expect(restored.state.sex, DogSex.female);
    expect(restored.state.goal, 5000);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meetingTheme(),
        home: FirstMeetingScreen(controller: restored),
      ),
    );
    await tester.pumpAndSettle();
    await binding.takeScreenshot('meeting-native-restored-home');
    expect(find.text('— 걸음'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    restored.dispose();
  });
}

class _KeyboardObserver extends WidgetsBindingObserver {
  _KeyboardObserver(this.onMetrics);
  final VoidCallback onMetrics;
  @override
  void didChangeMetrics() => onMetrics();
}
