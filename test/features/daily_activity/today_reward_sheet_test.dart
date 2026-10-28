import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/record_mapping.dart';
import 'package:balmatchum_app/features/daily_activity/today_reward_sheet.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reward_panel_test.dart' show RewardRepository;

const dog = 'assets/first_meeting/dogs/pug.png';

/// The balance after a grant is the server's own answer; the sheet must show
/// it, never the old balance plus the grant.
class WalletRepository extends RewardRepository {
  int balance = 359;
  bool failWallet = false;

  /// The grant settles the whole day instead of leaving the ad part.
  bool settleAll = false;
  @override
  Future<WalletView> wallet() async {
    calls.add('wallet');
    if (failWallet) throw Exception('Wallet offline');
    return WalletView(
      balance: balance,
      streamGeneration: 0,
      policyVersion: 'steps-v1-20261019',
    );
  }

  @override
  Future<RewardGrant> claim(String date, String requestId, int revision) async {
    final granted = await super.claim(date, requestId, revision);
    balance = 400;
    if (settleAll) {
      current = current.copyWith(rewardStatus: 'settled', adClaimablePoints: 0);
    }
    return granted;
  }
}

void main() {
  late WalletRepository repository;
  late DailyStepsController steps;
  late ProductController product;
  setUp(() {
    repository = WalletRepository();
    steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    product = ProductController(repository, steps, null, account: 'A');
  });
  tearDown(() {
    product.dispose();
    steps.dispose();
    repository.client.close();
  });

  /// Opens the sheet over a page; completes with what the sheet answers.
  Future<Future<bool>> open(WidgetTester tester) async {
    await product.connect();
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showTodayRewardSheet(
                context,
                product: product,
                day: recordDay(repository.current),
                dogAsset: dog,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  String text(WidgetTester tester, String value) =>
      tester.widget<Text>(key(value)).data!;

  testWidgets('the amount leads and a normal sheet has no operator controls', (
    tester,
  ) async {
    await open(tester);
    expect(text(tester, 'reward_amount'), '+20P');
    expect(
      tester.getTopLeft(key('reward_amount')).dy,
      lessThan(tester.getTopLeft(key('reward_free_claim')).dy),
    );
    expect(key('reward_reload'), findsNothing);
    expect(key('reward_check_premium'), findsNothing);
    expect(key('reward_rules'), findsNothing);
    await tester.tap(key('reward_info'));
    await tester.pump();
    expect(key('reward_rules'), findsOneWidget);
  });

  testWidgets(
    'a confirmed grant shows its amount, the server balance and the dog',
    (tester) async {
      await open(tester);
      expect(key('reward_granted_title'), findsNothing);
      await tester.tap(key('reward_free_claim'));
      await tester.pumpAndSettle();
      expect(text(tester, 'reward_granted_title'), startsWith('20P'));
      // 359 + 20 would be 379; only the server's 400 is shown.
      expect(text(tester, 'reward_granted_balance'), contains('400P'));
      expect(
        tester.widget<Image>(key('reward_granted_dog')).image,
        const AssetImage(dog),
      );
      // The free part was received; the ad part is still there to take.
      expect(key('reward_granted_left'), findsOneWidget);
      expect(repository.ids, hasLength(1));
    },
  );

  testWidgets('a refused claim celebrates nothing', (tester) async {
    repository.failure = ProductException(code: 'nothingToClaim');
    await open(tester);
    await tester.tap(key('reward_free_claim'));
    await tester.pumpAndSettle();
    expect(key('reward_granted_title'), findsNothing);
    expect(key('reward_notice'), findsOneWidget);
  });

  testWidgets(
    'a balance that cannot be re-read keeps the grant and retries reads only',
    (tester) async {
      await open(tester);
      repository.failWallet = true;
      await tester.tap(key('reward_free_claim'));
      await tester.pumpAndSettle();
      expect(key('reward_granted_title'), findsOneWidget);
      expect(key('reward_granted_balance'), findsNothing);
      repository.failWallet = false;
      await tester.tap(key('reward_balance_retry'));
      await tester.pumpAndSettle();
      expect(text(tester, 'reward_granted_balance'), contains('400P'));
      // Only reads ran again; the claim was sent once.
      expect(repository.ids, hasLength(1));
    },
  );

  testWidgets('done only closes; reopening celebrates nothing again', (
    tester,
  ) async {
    final first = await open(tester);
    await tester.tap(key('reward_free_claim'));
    await tester.pumpAndSettle();
    await tester.tap(key('reward_done'));
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(find.byType(TodayRewardSheet), findsNothing);
    final second = await open(tester);
    expect(key('reward_granted_title'), findsNothing);
    expect(key('reward_watch_ad'), findsOneWidget);
    await tester.tap(key('reward_close'));
    await tester.pumpAndSettle();
    expect(await second, isFalse);
    expect(repository.ids, hasLength(1));
  });

  testWidgets('the wardrobe choice closes the sheet and answers true', (
    tester,
  ) async {
    final result = await open(tester);
    await tester.tap(key('reward_free_claim'));
    await tester.pumpAndSettle();
    await tester.tap(key('reward_open_wardrobe'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(find.byType(TodayRewardSheet), findsNothing);
  });

  testWidgets('a settled day says so and offers no claim', (tester) async {
    repository.settleAll = true;
    await open(tester);
    await tester.tap(key('reward_free_claim'));
    await tester.pumpAndSettle();
    expect(key('reward_granted_done'), findsOneWidget);
    await tester.tap(key('reward_close'));
    await tester.pumpAndSettle();
    await open(tester);
    expect(key('reward_granted_title'), findsNothing);
    expect(key('reward_free_claim'), findsNothing);
    expect(key('reward_watch_ad'), findsNothing);
  });

  testWidgets('large text keeps the close and the claims reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    for (final value in [
      'reward_close',
      'reward_free_claim',
      'reward_watch_ad',
    ]) {
      await tester.ensureVisible(key(value));
      await tester.pumpAndSettle();
      expect(key(value).hitTestable(), findsOneWidget, reason: value);
    }
    expect(tester.takeException(), isNull);
  });
}
