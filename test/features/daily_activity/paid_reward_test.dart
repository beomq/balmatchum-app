import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/record_mapping.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../billing/billing_fakes.dart';
import 'reward_panel_test.dart';

class PaidRewards extends RewardRepository {
  bool active = true;
  Object? entitlementFailure;
  Completer<EntitlementView>? observation;
  final paidRequests = <(String, String, int)>[];
  @override
  Future<EntitlementView> entitlement() async {
    if (entitlementFailure != null) throw entitlementFailure!;
    return observation == null ? view(active: active) : observation!.future;
  }

  @override
  Future<RewardGrant> claimWithPremium(
    String date,
    String id,
    int revision,
  ) async {
    paidRequests.add((date, id, revision));
    if (failure != null) throw failure!;
    final amount = current.adClaimablePoints!;
    current = current.copyWith(
      revision: revision + 1,
      rewardStatus: 'settled',
      claimablePoints: 0,
      adClaimablePoints: 0,
      grantedPoints: amount,
    );
    return grant(amount);
  }
}

void main() {
  late PaidRewards repo;
  late ProductController c;
  late DailyStepsController steps;
  setUp(() {
    repo = PaidRewards();
    steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    c = ProductController(repo, steps, null, account: 'A');
  });
  tearDown(() {
    c.dispose();
    steps.dispose();
    repo.client.close();
  });

  test('fresh observation required, no automatic or topup claim', () async {
    final day = recordDay(repo.current);
    expect(() => c.claimWithPremium(day), throwsFormatException);
    await c.checkPremium();
    expect(repo.paidRequests, isEmpty);
    expect(await c.claimWithPremium(day), 180);
    expect(c.premiumActive, isNull);
    expect(repo.current.adClaimablePoints, 0);
  });

  test(
    'ambiguous claim locks original date revision method and id across refresh',
    () async {
      await c.checkPremium();
      final original = recordDay(repo.current);
      repo.failure = const SocketException('response lost');
      await expectLater(
        c.claimWithPremium(original),
        throwsA(isA<SocketException>()),
      );
      repo.current = repo.current.copyWith(revision: 99);
      await c.refresh();
      expect(() => c.claim(recordDay(repo.current)), throwsFormatException);
      expect(() => c.claimWithAd(original, 'ad'), throwsFormatException);
      expect(c.beginAd(), isFalse);
      repo.failure = BillingException(code: 'temporarilyUnavailable');
      await expectLater(c.retryClaim(), throwsA(isA<BillingException>()));
      expect(c.hasPendingClaim, isTrue);
      repo.failure = null;
      await c.retryClaim();
      expect(repo.paidRequests, everyElement(repo.paidRequests.first));
      expect(c.hasPendingClaim, isFalse);
    },
  );

  test(
    'definitive inactive permits free, error never means false entitlement',
    () async {
      await c.checkPremium();
      repo.failure = BillingException(code: 'entitlementInactive');
      await expectLater(
        c.claimWithPremium(recordDay(repo.current)),
        throwsA(isA<BillingException>()),
      );
      expect(c.hasPendingClaim, isFalse);
      expect(c.premiumActive, isNull);
      repo.failure = null;
      expect(await c.claim(recordDay(repo.current)), 20);
      repo.entitlementFailure = BillingException(
        code: 'temporarilyUnavailable',
      );
      await expectLater(c.checkPremium(), throwsA(isA<BillingException>()));
      expect(c.premiumActive, isNull);
    },
  );

  test('shared ad and observation gates reject concurrent mutations', () async {
    expect(c.beginAd(), isTrue);
    await expectLater(c.checkPremium(), throwsFormatException);
    expect(() => c.claim(recordDay(repo.current)), throwsFormatException);
    c.endAd();
    repo.observation = Completer<EntitlementView>();
    final check = c.checkPremium();
    expect(c.beginAd(), isFalse);
    expect(
      () => c.claimWithPremium(recordDay(repo.current)),
      throwsFormatException,
    );
    repo.observation!.complete(view(active: true));
    await check;
  });

  testWidgets(
    'expired reward uses ad total only after explicit premium selection',
    (tester) async {
      repo.current = repo.current.copyWith(
        rewardStatus: 'adRequired',
        claimablePoints: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RewardPanel(controller: c, day: recordDay(repo.current)),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('reward_premium_claim')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reward_check_premium')));
      await tester.pumpAndSettle();
      expect(repo.paidRequests, isEmpty);
      expect(
        find.byKey(const ValueKey('reward_premium_claim')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('reward_premium_claim')));
      await tester.pumpAndSettle();
      expect(repo.paidRequests, hasLength(1));
      expect(repo.current.grantedPoints, 180);
      expect(find.byKey(const ValueKey('reward_premium_claim')), findsNothing);
    },
  );
}
