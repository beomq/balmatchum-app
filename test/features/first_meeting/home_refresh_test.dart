import 'dart:async';

import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../billing/billing_http_harness.dart' show presentBilling;
import '../daily_activity/product_controller_test.dart' show AccountRepository;
import 'domain/authenticated_profile_test.dart' show Profiles, view;
import 'domain/first_meeting_test.dart' show MemoryStorage;

/// An account wallet that still carries a development fixture label, as a
/// staging server can send it.
class FixtureWallet extends AccountRepository {
  @override
  Future<WalletView> wallet() async => (await super.wallet()).copyWith(
    balance: 12345,
    fixtureLabel: 'development-fixture-v1-not-production',
  );
}

/// A real account's repository: billing is connected and nothing is bought.
class BilledAccount extends AccountRepository {
  BilledAccount() : super(billing: presentBilling());
  @override
  Future<DailyRecord> day(DateTime date) async {
    final value = await super.day(date);
    // The reward sheet opens only for today's record.
    return value.copyWith(
      date: ProductRepository.dateKey(ProductRepository.today),
    );
  }

  @override
  Future<EntitlementView> entitlement() async =>
      EntitlementView(active: false, purchases: []);
}

const _empty = DailyStepsResult(DailyStepsStatus.empty, null);

void main() {
  late int reads;
  Completer<DailyStepsResult>? gate;
  late DailyStepsController steps;
  setUp(() {
    reads = 0;
    gate = null;
    steps = DailyStepsController(
      readSteps: () async {
        reads++;
        return gate?.future ?? _empty;
      },
    );
  });
  tearDown(() => steps.dispose());

  FirstMeetingController account() {
    final c = FirstMeetingController(
      storage: MemoryStorage(),
      profileRepository: Profiles()..current = view(),
    );
    addTearDown(c.dispose);
    return c;
  }

  ProductController productFor(
    AccountRepository repository, {
    String? account = 'A',
  }) {
    final product = ProductController(
      repository,
      steps,
      null,
      account: account,
    );
    addTearDown(() {
      product.dispose();
      repository.client.close();
    });
    return product;
  }

  Widget home(FirstMeetingController c, ProductController? product) =>
      MaterialApp(
        theme: meetingTheme(),
        home: FirstMeetingScreen(
          controller: c,
          dailySteps: steps,
          product: product,
        ),
      );

  int calls(AccountRepository repository, String call) =>
      repository.calls.where((c) => c == call).length;

  void returnToApp(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('an account home syncs on entry and has no sync control', (
    tester,
  ) async {
    final repository = AccountRepository();
    final product = productFor(repository);
    await tester.pumpWidget(home(account(), product));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(calls(repository, 'day'), 1);
    expect(product.today, isNotNull);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byKey(const ValueKey('home_sync_retry')), findsNothing);
    expect(find.byKey(const ValueKey('daily_steps_retry')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pull and app return rerun one sync, never two at once', (
    tester,
  ) async {
    final repository = AccountRepository();
    await tester.pumpWidget(home(account(), productFor(repository)));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(calls(repository, 'day'), 2);
    returnToApp(tester);
    await tester.pumpAndSettle();
    expect(reads, 3);
    // A sync in flight absorbs the next trigger instead of uploading twice.
    gate = Completer<DailyStepsResult>();
    returnToApp(tester);
    await tester.pump();
    expect(reads, 4);
    returnToApp(tester);
    await tester.pump();
    expect(reads, 4);
    gate!.complete(_empty);
    await tester.pumpAndSettle();
    expect(reads, 4);
    expect(calls(repository, 'day'), 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed sync offers one retry that recovers', (tester) async {
    final repository = AccountRepository()..failRead = true;
    final product = productFor(repository);
    await tester.pumpWidget(home(account(), product));
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('home_sync_retry'));
    expect(product.connected, isFalse);
    expect(retry, findsOneWidget);
    repository.failRead = false;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(product.connected, isTrue);
    expect(product.error, isNull);
    expect(retry, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an account build shows no development text', (tester) async {
    final product = productFor(FixtureWallet());
    await tester.pumpWidget(home(account(), product));
    await tester.pumpAndSettle();
    final wallet = find.byKey(const ValueKey('reward_wallet'));
    expect(tester.widget<Text>(wallet).data, '12,345P');
    expect(find.textContaining('Dev 체험'), findsNothing);
    // Before today's record arrives the fallback is an account message.
    product.today = null;
    final reward = find.byKey(const ValueKey('home_reward'));
    await tester.ensureVisible(reward);
    await tester.tap(reward);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Dev 체험'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only the dev build marks a fixture wallet', (tester) async {
    debugFixtureLabelsVisible = true;
    addTearDown(() => debugFixtureLabelsVisible = null);
    await tester.pumpWidget(home(account(), productFor(FixtureWallet())));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('reward_wallet'))).data,
      contains('개발 검증용'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the reward sheet observes the benefit without rebuilding the home',
    (tester) async {
      final repository = BilledAccount();
      addTearDown(() => repository.billing!.client.close());
      final product = productFor(repository);
      await tester.pumpWidget(home(account(), product));
      await tester.pumpAndSettle();
      final reward = find.byKey(const ValueKey('home_reward'));
      await tester.ensureVisible(reward);
      await tester.tap(reward);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RewardPanel), findsOneWidget);
      expect(product.premiumActive, isFalse);
      expect(find.byKey(const ValueKey('reward_check_premium')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the dev test user still connects by hand', (tester) async {
    final c = FirstMeetingController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.enter();
    await c.chooseMethod(FirstMeetingMethod.catalog);
    await c.selectBreed('shih-tzu');
    await c.confirmCandidate();
    await c.updateName('몽글');
    await c.updateSex(DogSex.female);
    await c.submitName();
    await c.complete();
    final repository = AccountRepository();
    await tester.pumpWidget(home(c, productFor(repository, account: null)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home_dev_connect')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_sync_retry')), findsNothing);
    // Entry reads the device; the dev server waits for the explicit tap.
    expect(reads, 1);
    expect(repository.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a product handed over at completion syncs once', (tester) async {
    final c = account();
    final repository = AccountRepository();
    await tester.pumpWidget(home(c, null));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(repository.calls, isEmpty);
    await tester.pumpWidget(home(c, productFor(repository)));
    await tester.pumpAndSettle();
    expect(calls(repository, 'day'), 1);
    expect(reads, 2);
    expect(find.byKey(const ValueKey('reward_wallet')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
