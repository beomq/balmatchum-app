import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/home_bootstrap.dart';
import 'package:balmatchum_app/features/daily_activity/step_streak.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';
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

/// Marks the reads a fake home snapshot is made of; they are one `home` call.
const _homeParts = #homeSnapshotParts;

/// The server calls in order, without the reads inside a fake snapshot.
class ServerCalls extends ListBase<String> {
  final _calls = <String>[];
  @override
  int get length => _calls.length;
  @override
  set length(int value) => _calls.length = value;
  @override
  String operator [](int index) => _calls[index];
  @override
  void operator []=(int index, String value) => _calls[index] = value;
  @override
  void add(String element) {
    if (Zone.current[_homeParts] != true) _calls.add(element);
  }
}

class AccountRepository extends ProductRepository {
  AccountRepository({super.billing, Client? client})
    : super(client ?? Client('http://localhost/'));
  Completer<DailyRecord>? pending;

  /// Snapshot dates answered before the device's KST date, in order.
  final snapshotDates = <String>[];
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
  final calls = ServerCalls();

  /// One snapshot of what this server's reads answer; any failing part fails
  /// it, as the server answers all or nothing.
  @override
  Future<HomeSnapshot> home() async {
    calls.add('home');
    return runZoned(zoneValues: {_homeParts: true}, () async {
      final today = ProductRepository.today;
      return HomeSnapshot(
        date: snapshotDates.isEmpty
            ? ProductRepository.dateKey(today)
            : snapshotDates.removeAt(0),
        day: await day(today),
        wallet: await wallet(),
        themes: await themes(),
        outfits: await outfits(),
        recentDays: recentDays ?? const [],
      );
    });
  }

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

String _todayKey() => ProductRepository.dateKey(ProductRepository.today);

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async => value = data;
}

class _RealHttp extends HttpOverrides {}

/// Today's record as the snapshot holds it, before the upload.
class _TodayRepository extends AccountRepository {
  _TodayRepository(Client client) : super(client: client);
  @override
  Future<DailyRecord> day(DateTime date) async {
    calls.add('day');
    return record().copyWith(date: _todayKey(), steps: 4000);
  }
}

class _UploadRig {
  _UploadRig(this.repository, this.controller, this.bootstrap);
  final AccountRepository repository;
  final ProductController controller;
  final HomeBootstrap bootstrap;
}

/// An account 'A' whose step uploads reach a local server that records each
/// endpoint into the repository's calls and confirms 9000 steps for today.
/// The snapshot holds the three days before today, so the run ends yesterday.
Future<void> _uploadRig(
  Future<void> Function(_UploadRig rig) body, {
  bool registered = true,
}) => HttpOverrides.runWithHttpOverrides(() async {
  final dir = await Directory.systemTemp.createTemp('home-sync-');
  addTearDown(() => dir.delete(recursive: true));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  late final AccountRepository repository;
  final subscription = server.listen((request) async {
    final name = request.uri.pathSegments.last;
    await request.drain<void>();
    repository.calls.add(name);
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      name == 'registerStepStream'
          ? '1'
          : jsonEncode(
              record().copyWith(date: _todayKey(), steps: 9000).toJson(),
            ),
    );
    await request.response.close();
  });
  addTearDown(subscription.cancel);
  final auth = AuthSuccess(
    authStrategy: 'session',
    token: 'token-a',
    authUserId: UuidValue.fromString('00000000-0000-4000-8000-00000000000a'),
    scopeNames: {},
  );
  final client = Client('http://127.0.0.1:${server.port}/')
    ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
  await client.auth.updateSignedInUser(auth);
  if (registered) {
    await File('${dir.path}/steps-${auth.authUserId}.json')
        .writeAsString(jsonEncode({'generation': 1, 'revision': 0}));
  }
  final today = ProductRepository.today;
  repository = _TodayRepository(client)
    ..recentDays = [
      for (var i = 1; i <= 3; i++)
        record().copyWith(
          date: ProductRepository.dateKey(today.subtract(Duration(days: i))),
        ),
    ];
  final steps = DailyStepsController(
    readSteps: () async => DailyStepsResult(DailyStepsStatus.available, {
      'count': 9000,
      'date': _todayKey(),
      'observedAt': DateTime.now().toUtc().toIso8601String(),
    }),
  );
  final bootstrap = HomeBootstrap();
  final controller = ProductController(
    repository,
    steps,
    null,
    account: 'A',
    bootstrap: bootstrap,
    stepDirectory: () async => dir,
  );
  addTearDown(() {
    controller.dispose();
    steps.dispose();
    client.close();
  });
  await body(_UploadRig(repository, controller, bootstrap));
}, _RealHttp());

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
      // Each refresh (connect, sync, after the claim and the delete) is one
      // home snapshot.
      expect(repository.calls, [
        'home',
        'home',
        'month',
        'day',
        'claim',
        'home',
        'themes',
        'outfits',
        'delete',
        'home',
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

  test('refresh reads one home snapshot', () async {
    final repository = AccountRepository()
      ..wardrobeOutfits = outfitStore(owned: true, equipped: 'vest-low-v');
    final controller = accountController(repository);
    await controller.refresh();
    debugPrint('refresh calls: ${repository.calls}');
    expect(repository.calls, ['home']);
    expect(controller.today, isNotNull);
    expect(controller.wallet!.balance, 42);
    expect(controller.store!.equippedTheme, 'sunny');
    expect(
      controller.wornLayer('shih-tzu'),
      'assets/wardrobe/vest/shih-tzu.png',
    );
    expect(controller.streak, isNotNull);
  });

  test(
    'a failed snapshot keeps the last themes and outfits and sets an error',
    () async {
      final repository = AccountRepository();
      final controller = accountController(repository);
      await controller.connect();
      final store = controller.store;
      final outfits = controller.outfits;
      repository.failThemes = true;
      await controller.deleteDay(DateTime(2026, 10, 15));
      expect(controller.error, isNotNull);
      expect(controller.store, same(store));
      expect(controller.outfits, same(outfits));
      expect(repository.calls, ['home', 'delete', 'home']);
    },
  );

  for (final failing in ['theme', 'outfit']) {
    test('a failed $failing read during sync keeps the last home, sets an '
        'error and uploads no steps', () async {
      await _uploadRig((rig) async {
        final repository = rig.repository
          ..wardrobeOutfits = outfitStore(owned: true, equipped: 'vest-low-v');
        final controller = rig.controller;
        await controller.sync();
        final store = controller.store;
        final outfits = controller.outfits;
        final today = controller.today;
        final wallet = controller.wallet;
        final streak = controller.streak;
        expect(store, isNotNull);
        expect(controller.error, isNull);
        expect(repository.calls, ['home', 'submitSteps']);
        if (failing == 'theme') {
          repository.failThemes = true;
        } else {
          repository.failOutfits = true;
        }
        await controller.sync();
        debugPrint('failed $failing sync calls: ${repository.calls}');
        debugPrint(
          'survived: theme=${controller.store?.equippedTheme} '
          'outfit=${controller.outfits?.equippedOutfit} '
          'steps=${controller.today?.steps} '
          'balance=${controller.wallet?.balance} '
          'streak=${controller.streak?.days}',
        );
        // The failed snapshot is the only call: no step upload follows.
        expect(repository.calls, ['home', 'submitSteps', 'home']);
        expect(controller.error, isNotNull);
        expect(controller.connected, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.store, same(store));
        expect(controller.outfits, same(outfits));
        expect(controller.today, same(today));
        expect(controller.wallet, same(wallet));
        expect(controller.streak, same(streak));
        expect(
          controller.wornLayer('shih-tzu'),
          'assets/wardrobe/vest/shih-tzu.png',
        );
        repository
          ..failThemes = false
          ..failOutfits = false;
        await controller.sync();
        debugPrint('recovered $failing sync calls: ${repository.calls}');
        expect(repository.calls, [
          'home',
          'submitSteps',
          'home',
          'home',
          'submitSteps',
        ]);
        expect(controller.error, isNull);
        expect(controller.busy, isFalse);
        expect(controller.connected, isTrue);
        expect(controller.store, isNotNull);
        expect(controller.today!.steps, 9000);
      });
    });
  }

  test('a failed first snapshot during sync has nothing to keep', () async {
    final repository = AccountRepository()..failRead = true;
    final controller = accountController(repository);
    await controller.sync();
    expect(repository.calls, ['home']);
    expect(controller.error, isNotNull);
    expect(controller.connected, isFalse);
    expect(controller.store, isNull);
    expect(controller.today, isNull);
  });

  test('a snapshot of another day is read once more, then accepted', () async {
    final repository = AccountRepository()..snapshotDates.add('2000-01-01');
    final controller = accountController(repository);
    await controller.refresh();
    expect(repository.calls, ['home', 'home']);
    expect(controller.error, isNull);
    // The server still disagrees: its date is today, not an error.
    repository.snapshotDates.addAll(['2000-01-01', '2000-01-02']);
    await controller.refresh();
    debugPrint('date mismatch calls: ${repository.calls}');
    expect(repository.calls, ['home', 'home', 'home', 'home']);
    expect(controller.error, isNull);
    expect(controller.today, isNotNull);
    expect(controller.streak, isNotNull);
  });

  group('streak from the snapshot equals the 31-day read', () {
    DailyRecord recorded(int ago) => record().copyWith(
      date: ProductRepository.dateKey(
        ProductRepository.today.subtract(Duration(days: ago)),
      ),
      steps: 5000,
    );
    final fixtures = <String, List<int>>{
      'a run of ten days': [for (var i = 0; i < 10; i++) i],
      'all 31 days': [for (var i = 0; i < StepStreak.window; i++) i],
      'no record today, a run to yesterday': [for (var i = 1; i < 10; i++) i],
      'a week with gaps': [0, 2, 3, 5, 6, 9],
    };
    for (final MapEntry(key: name, value: ago) in fixtures.entries) {
      test(name, () async {
        final repository = AccountRepository()
          ..recentDays = [for (final i in ago) recorded(i)];
        final controller = accountController(repository);
        await controller.refresh();
        final snapshot = controller.streak!;
        await controller.loadStreak();
        final read = controller.streak!;
        debugPrint(
          '$name: snapshot ${snapshot.days}/${snapshot.atLeast}/'
          '${snapshot.thisWeek} read ${read.days}/${read.atLeast}/'
          '${read.thisWeek}',
        );
        expect(snapshot.days, read.days);
        expect(snapshot.atLeast, read.atLeast);
        expect(snapshot.thisWeek, read.thisWeek);
        if (name == 'all 31 days') expect(snapshot.atLeast, isTrue);
        if (name == 'a run of ten days') expect(snapshot.days, 10);
        if (name.startsWith('no record today')) expect(snapshot.days, 9);
      });
    }
  });

  group('sync', () {
    test('takes the started bootstrap, then uploads once', () async {
      await _uploadRig((rig) async {
        rig.bootstrap.start('A', rig.repository.home);
        await rig.controller.sync();
        debugPrint('bootstrap sync calls: ${rig.repository.calls}');
        expect(rig.repository.calls, ['home', 'submitSteps']);
        expect(rig.bootstrap.take('A'), isNull);
        // A taken snapshot is never used again.
        await rig.controller.sync();
        debugPrint('second sync calls: ${rig.repository.calls}');
        expect(rig.repository.calls, [
          'home',
          'submitSteps',
          'home',
          'submitSteps',
        ]);
      });
    });

    test('without a bootstrap reads one snapshot and patches today from the '
        'upload', () async {
      await _uploadRig((rig) async {
        final before = StepStreak.of(
          rig.repository.recentDays!,
          ProductRepository.today,
        );
        await rig.controller.sync();
        debugPrint('sync calls: ${rig.repository.calls}');
        expect(rig.repository.calls, ['home', 'submitSteps']);
        expect(rig.controller.error, isNull);
        expect(rig.controller.today!.date, _todayKey());
        expect(rig.controller.today!.steps, 9000);
        // Today's upload joins the run that ended yesterday.
        expect(before.days, 3);
        expect(rig.controller.streak!.days, 4);
        expect(rig.controller.streak!.thisWeek, before.thisWeek + 1);
      });
    });

    test('a first registration adds only the stream registration', () async {
      await _uploadRig(registered: false, (rig) async {
        await rig.controller.sync();
        debugPrint('first registration calls: ${rig.repository.calls}');
        expect(rig.repository.calls, [
          'home',
          'registerStepStream',
          'submitSteps',
        ]);
      });
    });

    test('another account\'s bootstrap is never taken', () async {
      await _uploadRig((rig) async {
        rig.bootstrap.start('B', () async => throw StateError('B only'));
        await rig.controller.sync();
        expect(rig.repository.calls, ['home', 'submitSteps']);
        expect(rig.controller.error, isNull);
      });
    });

    test('a discarded bootstrap leaves the refresh to the server', () async {
      await _uploadRig((rig) async {
        rig.bootstrap
          ..start('A', () async => throw StateError('discarded'))
          ..discard();
        await rig.controller.sync();
        expect(rig.repository.calls, ['home', 'submitSteps']);
        expect(rig.controller.error, isNull);
      });
    });
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
    expect(repository.calls, ['delete', 'home']);
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
      expect(repository.calls, ['home', 'day']);
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
