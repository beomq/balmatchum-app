import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/record_mapping.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../daily_activity/paid_reward_test.dart';
import '../quiz/paid_quiz_test.dart';
import '../quiz/authenticated_quiz_test.dart' show question;
import 'billing_http_harness.dart' show presentBilling;

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('premium surfaces $width dark $dark', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await (FontLoader('Pretendard')..addFont(
                rootBundle.load('assets/fonts/PretendardVariable.ttf'),
              ))
              .load();
        });
        final billing = presentBilling();
        final rewardRepo = PaidRewards(billing: billing);
        final quizRepo = PaidQuizzes(billing: billing);
        quizRepo.current = quizRepo.current.copyWith(
          free: question(1, answered: true),
          extraStatus: 'adRequired',
          extraRevision: 1,
        );
        final steps = DailyStepsController(
          readSteps: () async =>
              const DailyStepsResult(DailyStepsStatus.empty, null),
        );
        final product = ProductController(
          rewardRepo,
          steps,
          null,
          account: 'A',
        );
        final quiz = QuizController(quizRepo, isCurrentAccount: () => true);
        addTearDown(() {
          product.dispose();
          quiz.dispose();
          steps.dispose();
          rewardRepo.client.close();
          quizRepo.client.close();
          billing.client.close();
        });
        final theme = dark
            ? ThemeData(brightness: Brightness.dark, fontFamily: 'Pretendard')
            : meetingTheme();
        for (final surface in ['reward', 'quiz']) {
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: theme,
                home: surface == 'reward'
                    ? Scaffold(
                        body: SingleChildScrollView(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: RewardPanel(
                                  controller: product,
                                  day: recordDay(rewardRepo.current),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : AuthenticatedQuizScreen(
                        controller: quiz,
                        onBack: () {},
                        onHome: () {},
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Entry observes the benefit by itself (guide 3.1).
          expect(
            find.byKey(ValueKey('${surface}_check_premium')),
            findsNothing,
          );
          expect(
            find.byKey(
              ValueKey(
                surface == 'reward'
                    ? 'reward_premium_claim'
                    : 'quiz_premium_unlock',
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('PAID_RENDER')) {
            for (final position in ['top', 'end']) {
              if (position == 'end') {
                await tester.drag(
                  find.byType(SingleChildScrollView),
                  const Offset(0, -1600),
                );
                await tester.pumpAndSettle();
              }
              await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${Platform.environment['RUN_TMP']}/paid-$surface-$width-$dark-$position.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
      });
    }
  }
}
