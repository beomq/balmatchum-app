import 'dart:async';

import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/records/records_models.dart';

DailyRecord record({bool deleted = false}) => DailyRecord(
  date: '2026-10-15',
  revision: 1,
  deleted: deleted,
  deletionVersion: deleted ? 1 : 0,
  steps: deleted ? null : 4000,
  availability: deleted ? 'deleted' : 'confirmed',
  streamGeneration: 0,
  stepRevision: 0,
  rewardStatus: deleted ? 'canceled' : 'eligible',
  claimablePoints: 10,
  adClaimablePoints: 20,
  policyVersion: 'steps-v1-20261019',
  gracePolicyStatus: 'active',
  dailyBaseCap: 100,
  stepsPerPoint: 100,
  grantedPoints: 0,
  routes: [],
);

/// Production store shape: real prices and no fixture label.
ThemeStore themeStore({bool cloudyOwned = false, int balance = 42}) =>
    ThemeStore(
      items: [
        ThemeItem(
          themeId: 'sunny',
          name: 'Sunny',
          colorValue: 0xfff5eedc,
          price: 0,
          owned: true,
        ),
        ThemeItem(
          themeId: 'cloudy',
          name: 'Cloudy',
          colorValue: 0xffe4e7e9,
          price: 3,
          owned: cloudyOwned,
        ),
      ],
      equippedTheme: 'sunny',
      balance: balance,
    );

class AccountRepository extends ProductRepository {
  AccountRepository() : super(Client('http://localhost/'));
  Completer<DailyRecord>? pending;
  bool failRead = false;
  ThemeStore store = themeStore();
  final calls = <String>[];
  @override
  Future<WalletView> wallet() async {
    calls.add('wallet');
    return WalletView(
      balance: 42,
      streamGeneration: 0,
      policyVersion: 'steps-v1-20261019',
    );
  }

  @override
  Future<RewardGrant> claim(String date, String requestId, int revision) async {
    calls.add('claim');
    return RewardGrant(
      ledgerId: 1,
      date: date,
      amount: 10,
      fromUnits: 0,
      throughUnits: 10,
      grantedAt: DateTime.utc(2026, 10, 15),
    );
  }

  @override
  Future<void> connectDevelopmentUser() async {
    calls.add('dev');
    throw Exception('Development import must not run');
  }

  @override
  Future<DailyRecord> day(DateTime date) async {
    calls.add('day');
    if (failRead) throw Exception('Offline');
    return pending == null ? record() : pending!.future;
  }

  @override
  Future<List<DailyRecord>> month(DateTime month) async {
    calls.add('month');
    return [record()];
  }

  @override
  Future<DailyRecord> deleteDay(DateTime date, String requestId) async {
    calls.add('delete');
    return record(deleted: true);
  }

  @override
  Future<ThemeStore> themes() async {
    calls.add('themes');
    return store;
  }

  @override
  Future<ThemeStore> purchase(String themeId, String requestId) async {
    calls.add('purchase:$themeId');
    return store = themeStore(cloudyOwned: true, balance: 39);
  }

  @override
  Future<DailyQuiz> quiz(DateTime date) async {
    calls.add('quiz');
    throw Exception('Fixture unavailable');
  }
}

class MissingSessionRepository extends ProductRepository {
  MissingSessionRepository() : super(Client('http://localhost/'));
  @override
  Future<void> connectDevelopmentUser() async =>
      throw const FormatException('No session');
}

class PendingSessionRepository extends MissingSessionRepository {
  final session = Completer<void>();
  @override
  Future<void> connectDevelopmentUser() => session.future;
}

void main() {
  test(
    'authenticated provider replaces controller for account changes and logout',
    () async {
      final client = Client('http://localhost/');
      final container = ProviderContainer(
        overrides: [
          authenticatedAccountProvider.overrideWithValue('A'),
          clientProvider.overrideWithValue(client),
          watchSyncServiceProvider.overrideWithValue(null),
        ],
      );
      final a = container.read(authenticatedProductControllerProvider)!;
      expect(a.account, 'A');
      container.updateOverrides([
        authenticatedAccountProvider.overrideWithValue('B'),
        clientProvider.overrideWithValue(client),
        watchSyncServiceProvider.overrideWithValue(null),
      ]);
      final b = container.read(authenticatedProductControllerProvider)!;
      expect(b.account, 'B');
      expect(b, isNot(same(a)));
      expect(() => a.addListener(() {}), throwsFlutterError);
      container.updateOverrides([
        authenticatedAccountProvider.overrideWithValue(null),
        clientProvider.overrideWithValue(client),
        watchSyncServiceProvider.overrideWithValue(null),
      ]);
      expect(container.read(authenticatedProductControllerProvider), isNull);
      expect(() => b.addListener(() {}), throwsFlutterError);
      container.dispose();
      client.close();
    },
  );

  test(
    'real account records and sync never import dev or call fixtures',
    () async {
      final repository = AccountRepository();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final controller = ProductController(
        repository,
        steps,
        null,
        account: 'A',
      );
      addTearDown(() {
        controller.dispose();
        steps.dispose();
        repository.client.close();
      });
      await controller.connect();
      await controller.sync();
      final month = await controller.loadMonth(DateTime(2026, 10));
      final day = await controller.loadDay(DateTime(2026, 10, 15));
      expect(month.day(15)!.rewardStatus, DayRewardStatus.claimable);
      expect(day.rewardStatus, DayRewardStatus.claimable);
      expect(day.claimablePoints, 10);
      expect(controller.wallet!.balance, 42);
      expect(await controller.claim(day), 10);
      await expectLater(controller.loadQuiz(), throwsFormatException);
      expect((await controller.loadWardrobe()).fixtureLabel, isNull);
      expect((await controller.deleteDay(day.date)).isDeleted, isTrue);
      expect(repository.calls, [
        'day',
        'wallet',
        'themes',
        'day',
        'wallet',
        'themes',
        'month',
        'day',
        'claim',
        'day',
        'wallet',
        'themes',
        'themes',
        'delete',
        'day',
        'wallet',
        'themes',
      ]);
      expect(controller.store?.equippedTheme, 'sunny');
      expect(controller.quiz, isNull);
    },
  );

  test('real account buys a theme from the server store', () async {
    final repository = AccountRepository();
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final controller = ProductController(repository, steps, null, account: 'A');
    addTearDown(() {
      controller.dispose();
      steps.dispose();
      repository.client.close();
    });
    final cloudy = (await controller.loadWardrobe()).themes.singleWhere(
      (theme) => theme.id == 'cloudy',
    );
    final bought = await controller.themeAction(cloudy, equip: false);
    expect(
      bought.themes.singleWhere((theme) => theme.id == 'cloudy').owned,
      isTrue,
    );
    expect(bought.balance, 39);
    expect(repository.calls, ['themes', 'purchase:cloudy', 'themes']);
  });

  test('confirmed delete succeeds even when refresh fails', () async {
    final repository = AccountRepository()..failRead = true;
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final controller = ProductController(repository, steps, null, account: 'A');
    final result = await controller.deleteDay(DateTime(2026, 10, 15));
    expect(result.isDeleted, isTrue);
    expect(repository.calls, ['delete', 'day']);
    expect(controller.error, isNotNull);
    controller.dispose();
    steps.dispose();
    repository.client.close();
  });

  for (final dispose in [false, true]) {
    test('late account response is isolated with disposal $dispose', () async {
      var account = 'A';
      final repository = AccountRepository()
        ..pending = Completer<DailyRecord>();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final a = ProductController(
        repository,
        steps,
        null,
        account: 'A',
        isCurrentAccount: () => account == 'A',
      );
      final b = ProductController(
        repository,
        steps,
        null,
        account: 'B',
        isCurrentAccount: () => account == 'B',
      );
      var notifications = 0;
      a.addListener(() => notifications++);
      final refreshing = a.refresh();
      final loading = a.loadDay(DateTime(2026, 10, 15));
      final refreshRejected = expectLater(refreshing, throwsFormatException);
      final loadRejected = expectLater(loading, throwsFormatException);
      account = 'B';
      if (dispose) a.dispose();
      repository.pending!.complete(record());
      await refreshRejected;
      await loadRejected;
      expect(a.today, isNull);
      expect(b.today, isNull);
      expect(notifications, 0);
      await expectLater(
        a.deleteDay(DateTime(2026, 10, 15)),
        throwsFormatException,
      );
      expect(repository.calls, ['day', 'day']);
      if (!dispose) a.dispose();
      b.dispose();
      steps.dispose();
      repository.client.close();
    });
  }

  test('mutation is rejected while sync owns the busy state', () async {
    final repository = PendingSessionRepository();
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final controller = ProductController(repository, steps, null)
      ..connected = true;
    final sync = controller.sync();
    expect(controller.busy, isTrue);
    await expectLater(
      controller.deleteDay(DateTime(2026, 10, 15)),
      throwsFormatException,
    );
    expect(controller.busy, isTrue);
    repository.session.completeError(const FormatException('Session revoked'));
    await sync;
    expect(controller.connected, isFalse);
    expect(controller.today, isNull);
    expect(controller.store, isNull);
    expect(controller.busy, isFalse);
    controller.dispose();
    steps.dispose();
    repository.client.close();
  });

  test(
    'missing and revoked sessions enable reconnect without throwing',
    () async {
      final repository = MissingSessionRepository();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final controller = ProductController(repository, steps, null);
      addTearDown(() {
        controller.dispose();
        steps.dispose();
        repository.client.close();
      });
      await controller.connect();
      expect(controller.connected, isFalse);
      expect(controller.error, isNotNull);
      controller.connected = true;
      controller.store = ThemeStore(
        items: [],
        equippedTheme: 'cloudy',
        balance: 5,
      );
      await controller.sync();
      expect(controller.connected, isFalse);
      expect(controller.store, isNull);
      expect(controller.today, isNull);
      expect(controller.quiz, isNull);
      expect(controller.busy, isFalse);
      expect(controller.error, isNotNull);
    },
  );
}
