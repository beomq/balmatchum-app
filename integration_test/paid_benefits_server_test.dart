import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/quiz/authenticated_quiz_screen.dart';
import 'package:balmatchum_app/features/quiz/quiz_controller.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../test/features/billing/billing_http_harness.dart'
    show BillingMemoryAuth;

// Lose only the response after the real server commits. Retries still cross
// generated HTTP and must replay the real DB request, even during store outage.
class _LostRewardResponse extends ProductRepository {
  _LostRewardResponse(super.client, {super.accountId, super.billing});
  bool lose = true;
  @override
  Future<RewardGrant> claimWithPremium(
    String date,
    String id,
    int revision,
  ) async {
    final result = await super.claimWithPremium(date, id, revision);
    if (lose) {
      lose = false;
      throw const SocketException('QA response lost after commit');
    }
    return result;
  }
}

class _LostQuizResponse extends QuizRepository {
  _LostQuizResponse(super.client, super.accountId, {super.billing});
  bool lose = true;
  @override
  Future<QuizQuestion> unlockExtraWithPremium(
    String date,
    int revision,
    String id,
  ) async {
    final result = await super.unlockExtraWithPremium(date, revision, id);
    if (lose) {
      lose = false;
      throw const SocketException('QA response lost after commit');
    }
    return result;
  }
}

Future<String> seam(String path, {List<int>? bytes}) async {
  final http = HttpClient();
  try {
    final request = await http.openUrl(
      bytes == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:18111$path'),
    );
    if (bytes != null) request.add(bytes);
    final response = await request.close();
    expect(response.statusCode, 200);
    return await utf8.decoder.bind(response).join();
  } finally {
    http.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native paid UI actual Serverpod DB and real store parser fixture',
    (tester) async {
      final bootstrap =
          jsonDecode(await seam('/session')) as Map<String, dynamic>;
      final client = Client('http://127.0.0.1:18110/')
        ..authSessionManager = FlutterAuthSessionManager(
          storage: BillingMemoryAuth(),
        );
      await client.auth.updateSignedInUser(
        AuthSuccess.fromJson(bootstrap['auth'] as Map<String, dynamic>),
      );
      final account = client.auth.authInfo!.authUserId.toString();
      final billing = ServerpodBillingRepository(
        client,
        account,
        BillingRequestQueue(),
      );
      final repository = _LostRewardResponse(
        client,
        accountId: account,
        billing: billing,
      );
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final product = ProductController(
        repository,
        steps,
        null,
        account: account,
        isCurrentAccount: () => billing.isCurrent,
      );
      final quiz = QuizController(
        _LostQuizResponse(client, account, billing: billing),
        isCurrentAccount: () => billing.isCurrent,
      );
      addTearDown(() {
        quiz.dispose();
        product.dispose();
        steps.dispose();
        client.close();
      });
      Future<void> act(
        ChangeNotifier c,
        bool Function() busy,
        Future<void> Function() trigger,
      ) async {
        final completed = Completer<void>();
        var started = false;
        void changed() {
          if (busy()) started = true;
          if (started && !busy() && !completed.isCompleted) {
            completed.complete();
          }
        }

        c.addListener(changed);
        try {
          await trigger();
          await tester.runAsync(
            () => completed.future.timeout(const Duration(seconds: 20)),
          );
          await tester.pumpAndSettle();
        } finally {
          c.removeListener(changed);
        }
      }

      final config = await billing.configuration('google');
      await seam(
        '/binding?value=${Uri.encodeQueryComponent(config.accountBinding)}',
      );
      expect(
        (await billing.verify(
          PurchaseInput(
            store: 'google',
            productId: 'lifetime',
            purchaseReference: 'paid-native-store-fixture',
          ),
        )).active,
        isTrue,
      );
      await product.connect();
      final date = DateTime.parse(bootstrap['pastDate'] as String);
      final day = await product.loadDay(date);
      expect(day.claimablePoints, 20);
      expect(day.adClaimablePoints, 180);
      Future<void> shot(String name) async => seam(
        '/capture?name=$name',
        bytes: await binding.takeScreenshot(name),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: RewardPanel(controller: product, day: day),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await act(
        product,
        () => product.busy,
        () => tester.tap(find.byKey(const ValueKey('reward_check_premium'))),
      );
      expect(product.premiumActive, isTrue);
      expect((await repository.wallet()).balance, 0);
      await shot('paid-reward-confirmed');
      await act(
        product,
        () => product.busy,
        () => tester.tap(find.byKey(const ValueKey('reward_premium_claim'))),
      );
      expect(product.hasPendingClaim, isTrue);
      expect((await repository.wallet()).balance, 180);
      await seam('/unavailable?value=true');
      await act(
        product,
        () => product.busy,
        () => tester.tap(find.byKey(const ValueKey('reward_retry_claim'))),
      );
      expect(product.hasPendingClaim, isFalse);
      await seam('/unavailable?value=false');
      expect((await repository.wallet()).balance, 180);
      expect((await repository.day(date)).adClaimablePoints, 0);
      await shot('paid-reward-settled');

      await act(
        quiz,
        () => quiz.busy,
        () => tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme(),
            home: AuthenticatedQuizScreen(
              controller: quiz,
              onBack: () {},
              onHome: () {},
            ),
          ),
        ),
      );
      expect(quiz.today!.premiumStatus, 'notChecked');
      final free = quiz.today!.free!;
      await tester.ensureVisible(
        find.byKey(ValueKey('quiz_${free.assignmentId}_choice_1')),
      );
      await tester.tap(
        find.byKey(ValueKey('quiz_${free.assignmentId}_choice_1')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(ValueKey('quiz_${free.assignmentId}_submit')),
      );
      await act(
        quiz,
        () => quiz.busy,
        () => tester.tap(
          find.byKey(ValueKey('quiz_${free.assignmentId}_submit')),
        ),
      );
      expect(quiz.today!.free!.awardedPoints, 2);
      await tester.ensureVisible(
        find.byKey(const ValueKey('quiz_check_premium')),
      );
      await act(
        quiz,
        () => quiz.busy,
        () => tester.tap(find.byKey(const ValueKey('quiz_check_premium'))),
      );
      expect(quiz.today!.premiumStatus, 'active');
      expect(quiz.today!.extraStatus, 'premiumAvailable');
      expect(quiz.today!.extra, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('quiz_premium_unlock')),
      );
      await shot('paid-quiz-confirmed');
      await act(
        quiz,
        () => quiz.busy,
        () => tester.tap(find.byKey(const ValueKey('quiz_premium_unlock'))),
      );
      expect(quiz.hasPending, isTrue);
      await seam('/unavailable?value=true');
      await tester.ensureVisible(
        find.byKey(const ValueKey('quiz_retry_request')),
      );
      await act(
        quiz,
        () => quiz.busy,
        () => tester.tap(find.byKey(const ValueKey('quiz_retry_request'))),
      );
      expect(quiz.hasPending, isFalse);
      final extra = quiz.today!.extra!;
      // Issued questions submit without another entitlement observation.
      await quiz.answer(extra, 1);
      await tester.pumpAndSettle();
      expect(quiz.today!.extra!.awardedPoints, 2);
      // Synthetic quiz points remain isolated from the operational step wallet.
      expect((await repository.wallet()).balance, 180);
      await tester.ensureVisible(
        find.byKey(ValueKey('quiz_${extra.assignmentId}_past_points')),
      );
      await shot('paid-quiz-submitted');
      await quiz.checkPremium();
      expect(quiz.premiumError, 'temporarilyUnavailable');
      expect(quiz.premiumReady, isFalse);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('quiz_premium_status')),
      );
      await shot('paid-store-error');
      await seam('/unavailable?value=false');
      await seam('/refund');
      await quiz.checkPremium();
      expect(quiz.today!.premiumStatus, 'inactive');
      expect(quiz.premiumError, isNull);
      await tester.pumpAndSettle();
      await shot('paid-refunded');
      final evidence =
          jsonDecode(await seam('/evidence')) as Map<String, dynamic>;
      expect(evidence['ledgerRows'], 3);
      expect(evidence['storeQueries'], greaterThanOrEqualTo(5));
      expect(tester.takeException(), isNull);
    },
  );
}
