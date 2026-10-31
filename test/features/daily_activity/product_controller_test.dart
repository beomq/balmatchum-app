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
import 'package:balmatchum_app/features/wardrobe/wardrobe_models.dart';

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

/// Production outfit shape for a profile whose breed may wear the vest.
OutfitStore outfitStore({
  bool owned = false,
  String? equipped,
  int balance = 42,
  String? breed = 'shih-tzu',
}) => OutfitStore(
  items: [
    OutfitItem(
      outfitId: 'vest-low-v',
      name: 'Vest',
      price: 3,
      compatibleBreeds: ['shih-tzu', 'dachshund'],
      compatible: true,
      owned: owned,
    ),
  ],
  equippedOutfit: equipped,
  breedId: breed,
  balance: balance,
);

class AccountRepository extends ProductRepository {
  AccountRepository({super.billing}) : super(Client('http://localhost/'));
  Completer<DailyRecord>? pending;
  bool failRead = false;
  bool failThemes = false;
  ThemeStore store = themeStore();
  OutfitStore wardrobeOutfits = outfitStore();
  bool failOutfits = false;

  /// Thrown once by the next outfit change instead of its answer.
  Exception? outfitFailure;
  final outfitRequests = <String>[];
  Exception? themeFailure;
  final themeRequests = <String>[];
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

  /// The streak read's answer; null fails it.
  List<DailyRecord>? recentDays = const [];
  final dayRanges = <(DateTime, DateTime)>[];
  @override
  Future<List<DailyRecord>> days(DateTime from, DateTime to) async {
    calls.add('days');
    dayRanges.add((from, to));
    final value = recentDays;
    if (value == null) throw Exception('Days offline');
    return value;
  }

  @override
  Future<DailyRecord> deleteDay(DateTime date, String requestId) async {
    calls.add('delete');
    return record(deleted: true);
  }

  @override
  Future<ThemeStore> themes() async {
    calls.add('themes');
    if (failThemes) throw Exception('Themes offline');
    return store;
  }

  @override
  Future<ThemeStore> purchase(String themeId, String requestId) async {
    calls.add('purchase:$themeId');
    themeRequests.add(requestId);
    final failure = themeFailure;
    themeFailure = null;
    if (failure != null) throw failure;
    return store = themeStore(cloudyOwned: true, balance: 39);
  }

  @override
  Future<OutfitStore> outfits() async {
    calls.add('outfits');
    if (failOutfits) throw Exception('Outfits offline');
    return wardrobeOutfits;
  }

  Future<OutfitStore> changeOutfit(
    String call,
    String requestId,
    OutfitStore next,
  ) async {
    calls.add(call);
    outfitRequests.add(requestId);
    final failure = outfitFailure;
    outfitFailure = null;
    if (failure != null) throw failure;
    return wardrobeOutfits = next;
  }

  @override
  Future<OutfitStore> purchaseOutfit(String outfitId, String requestId) =>
      changeOutfit(
        'purchaseOutfit:$outfitId',
        requestId,
        outfitStore(owned: true, balance: 39),
      );

  @override
  Future<OutfitStore> equipOutfit(String outfitId, String requestId) =>
      changeOutfit(
        'equipOutfit:$outfitId',
        requestId,
        outfitStore(owned: true, equipped: outfitId, balance: 39),
      );

  @override
  Future<OutfitStore> unequipOutfit(String requestId) => changeOutfit(
    'unequipOutfit',
    requestId,
    outfitStore(owned: true, balance: 39),
  );

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

ProductController accountController(AccountRepository repository) {
  final steps = DailyStepsController(
    readSteps: () async => const DailyStepsResult(DailyStepsStatus.empty, null),
  );
  final controller = ProductController(repository, steps, null, account: 'A');
  addTearDown(() {
    controller.dispose();
    steps.dispose();
    repository.client.close();
  });
  return controller;
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
        'outfits',
        'day',
        'wallet',
        'themes',
        'outfits',
        'month',
        'day',
        'claim',
        'day',
        'wallet',
        'themes',
        'outfits',
        'themes',
        'outfits',
        'delete',
        'day',
        'wallet',
        'themes',
        'outfits',
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
    expect(cloudy.backgroundAsset, 'assets/first_meeting/cloudy.png');
    final bought = await controller.themeAction(cloudy, equip: false);
    expect(
      bought.themes.singleWhere((theme) => theme.id == 'cloudy').owned,
      isTrue,
    );
    expect(bought.balance, 39);
    // The first attempt applies the server's answer without a re-read.
    expect(repository.calls, ['themes', 'outfits', 'purchase:cloudy']);
  });

  test('real account buys, wears and removes the vest on the server', () async {
    final repository = AccountRepository();
    final controller = accountController(repository);
    final offered = (await controller.loadWardrobe()).outfits!.items.single;
    final bought = await controller.outfitAction(
      offered,
      OutfitChange.purchase,
    );
    final vest = bought.outfits!.items.single;
    expect(vest.owned, isTrue);
    expect(bought.balance, 39);
    expect(controller.wornLayer('shih-tzu'), isNull);
    await controller.outfitAction(vest, OutfitChange.wear);
    expect(
      controller.wornLayer('shih-tzu'),
      'assets/wardrobe/vest/shih-tzu.png',
    );
    final removed = await controller.outfitAction(vest, OutfitChange.remove);
    expect(removed.outfits!.equippedId, isNull);
    expect(controller.wornLayer('shih-tzu'), isNull);
    expect(repository.calls, [
      'themes',
      'outfits',
      'purchaseOutfit:vest-low-v',
      'equipOutfit:vest-low-v',
      'unequipOutfit',
    ]);
    // Each confirmed change is a new intent with its own idempotency key.
    expect(repository.outfitRequests.toSet(), hasLength(3));
  });

  test('outfit server codes become wardrobe failure reasons', () async {
    final repository = AccountRepository();
    final controller = accountController(repository);
    final vest = (await controller.loadWardrobe()).outfits!.items.single;
    const cases = {
      'insufficientPoints': WardrobeFailureReason.insufficientPoints,
      'outfitIncompatible': WardrobeFailureReason.incompatible,
      'outfitNotOwned': WardrobeFailureReason.unavailable,
      'unknownOutfit': WardrobeFailureReason.unavailable,
      'idempotencyConflict': WardrobeFailureReason.unavailable,
      'invalidRequestId': WardrobeFailureReason.unavailable,
    };
    for (final MapEntry(key: code, value: reason) in cases.entries) {
      repository.outfitFailure = ProductException(code: code);
      await expectLater(
        controller.outfitAction(vest, OutfitChange.purchase),
        throwsA(
          isA<WardrobeActionException>().having(
            (e) => e.reason,
            'reason',
            reason,
          ),
        ),
        reason: code,
      );
    }
    expect(repository.wardrobeOutfits.items.single.owned, isFalse);
  });

  test('vest retry uses a new request id after server rejection', () async {
    // Given: a purchase explicitly rejected by the server.
    final repository = AccountRepository();
    final controller = accountController(repository);
    final vest = (await controller.loadWardrobe()).outfits!.items.single;
    repository.outfitFailure = ProductException(code: 'insufficientPoints');
    await expectLater(
      controller.outfitAction(vest, OutfitChange.purchase),
      throwsA(isA<WardrobeActionException>()),
    );

    // When: the user makes a fresh purchase attempt.
    await controller.outfitAction(vest, OutfitChange.purchase);

    // Then: the confirmed rejection's request id is not reused.
    expect(repository.outfitRequests, hasLength(2));
    expect(repository.outfitRequests.toSet(), hasLength(2));
  });

  test('theme retry uses a new request id after server rejection', () async {
    // Given: a purchase explicitly rejected by the server.
    final repository = AccountRepository();
    final controller = accountController(repository);
    final cloudy = (await controller.loadWardrobe()).themes.singleWhere(
      (theme) => theme.id == 'cloudy',
    );
    repository.themeFailure = ProductException(code: 'insufficientPoints');
    await expectLater(
      controller.themeAction(cloudy, equip: false),
      throwsA(isA<WardrobeActionException>()),
    );

    // When: the user makes a fresh purchase attempt.
    await controller.themeAction(cloudy, equip: false);

    // Then: the confirmed rejection's request id is not reused.
    expect(repository.themeRequests, hasLength(2));
    expect(repository.themeRequests.toSet(), hasLength(2));
  });

  test('theme retry uses the same request id after response loss', () async {
    // Given: a purchase whose response was lost.
    final repository = AccountRepository();
    final controller = accountController(repository);
    final cloudy = (await controller.loadWardrobe()).themes.singleWhere(
      (theme) => theme.id == 'cloudy',
    );
    repository.themeFailure = Exception('response lost');
    await expectLater(
      controller.themeAction(cloudy, equip: false),
      throwsException,
    );

    // When: the user retries the ambiguous purchase.
    await controller.themeAction(cloudy, equip: false);

    // Then: the retry retains the original idempotency key and re-reads.
    expect(repository.themeRequests, hasLength(2));
    expect(repository.themeRequests.toSet(), hasLength(1));
    expect(repository.calls, [
      'themes',
      'outfits',
      'purchase:cloudy',
      'purchase:cloudy',
      'themes',
    ]);
  });

  test('lost vest response retries with the same request id', () async {
    final repository = AccountRepository();
    final controller = accountController(repository);
    final vest = (await controller.loadWardrobe()).outfits!.items.single;
    repository.outfitFailure = Exception('response lost');
    await expectLater(
      controller.outfitAction(vest, OutfitChange.purchase),
      throwsException,
    );
    final bought = await controller.outfitAction(vest, OutfitChange.purchase);
    expect(bought.outfits!.items.single.owned, isTrue);
    expect(repository.outfitRequests, hasLength(2));
    expect(repository.outfitRequests.toSet(), hasLength(1));
    expect(repository.calls, [
      'themes',
      'outfits',
      'purchaseOutfit:vest-low-v',
      'purchaseOutfit:vest-low-v',
      'outfits',
    ]);
  });

  test('wardrobe still opens with themes when outfits fail', () async {
    final repository = AccountRepository()..failOutfits = true;
    final controller = accountController(repository);
    final snapshot = await controller.loadWardrobe();
    expect(snapshot.equippedThemeId, 'sunny');
    expect(snapshot.themes, hasLength(2));
    expect(snapshot.outfits, isNull);
  });

  test('vest without a server breed is never wearable', () async {
    final repository = AccountRepository()
      ..wardrobeOutfits = outfitStore(
        owned: true,
        equipped: 'vest-low-v',
        breed: null,
      );
    final controller = accountController(repository);
    final snapshot = await controller.loadWardrobe();
    expect(snapshot.outfits!.items.single.compatible, isFalse);
    expect(controller.wornLayer('shih-tzu'), isNull);
  });

  test(
    'outfit failure keeps the worn vest and still refreshes records',
    () async {
      final repository = AccountRepository()
        ..wardrobeOutfits = outfitStore(owned: true, equipped: 'vest-low-v');
      final controller = accountController(repository);
      await controller.connect();
      repository.failOutfits = true;
      await controller.sync();
      expect(controller.error, isNull);
      expect(controller.connected, isTrue);
      expect(controller.today, isNotNull);
      expect(controller.wallet!.balance, 42);
      expect(
        controller.wornLayer('shih-tzu'),
        'assets/wardrobe/vest/shih-tzu.png',
      );
      expect(repository.calls, [
        'day',
        'wallet',
        'themes',
        'outfits',
        'day',
        'wallet',
        'themes',
        'outfits',
      ]);
    },
  );

  test('theme failure keeps last theme and still refreshes records', () async {
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
    await controller.connect();
    final previous = controller.store;
    repository.failThemes = true;
    await controller.sync();
    expect(controller.error, isNull);
    expect(controller.connected, isTrue);
    expect(controller.today, isNotNull);
    expect(controller.wallet!.balance, 42);
    expect(controller.store, same(previous));
    expect(repository.calls, [
      'day',
      'wallet',
      'themes',
      'outfits',
      'day',
      'wallet',
      'themes',
      'outfits',
    ]);
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
    // The refresh starts its four reads together; the failed day read still
    // fails it.
    expect(repository.calls, ['delete', 'day', 'wallet', 'themes', 'outfits']);
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
      // Only reads started while A was current; nothing after the switch.
      expect(repository.calls, ['day', 'wallet', 'themes', 'outfits', 'day']);
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
      controller.outfits = outfitStore(owned: true, equipped: 'vest-low-v');
      await controller.sync();
      expect(controller.connected, isFalse);
      expect(controller.store, isNull);
      expect(controller.outfits, isNull);
      expect(controller.today, isNull);
      expect(controller.quiz, isNull);
      expect(controller.busy, isFalse);
      expect(controller.error, isNotNull);
    },
  );
}
