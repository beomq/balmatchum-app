import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:balmatchum_app/features/ads/ads_sheet.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/record_mapping.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ads/ads_fakes.dart' show FakeAdsSdk;
import 'product_controller_test.dart';

class RewardRepository extends AccountRepository {
  RewardRepository({super.billing});
  DailyRecord current = record().copyWith(
    claimablePoints: 20,
    adClaimablePoints: 180,
  );
  final ids = <String>[];
  final intents = <String>[];
  Completer<RewardGrant>? pendingGrant;
  Object? failure;
  @override
  Future<DailyRecord> day(DateTime date) async => current;
  @override
  Future<RewardGrant> claim(String date, String requestId, int revision) async {
    ids.add(requestId);
    if (failure != null) throw failure!;
    if (pendingGrant != null) return pendingGrant!.future;
    current = current.copyWith(
      revision: revision + 1,
      rewardStatus: 'adRequired',
      claimablePoints: 0,
      adClaimablePoints: 140,
      grantedPoints: 20,
    );
    return grant(20);
  }

  @override
  Future<RewardGrant> claimWithAd(
    String date,
    String requestId,
    int revision,
    String intentId,
  ) async {
    ids.add(requestId);
    intents.add(intentId);
    if (failure != null) throw failure!;
    current = current.copyWith(
      revision: revision + 1,
      rewardStatus: 'settled',
      claimablePoints: 0,
      adClaimablePoints: 0,
      grantedPoints: 160,
    );
    return grant(140);
  }
}

RewardGrant grant(int amount) => RewardGrant(
  ledgerId: 1,
  date: '2026-10-15',
  amount: amount,
  fromUnits: 0,
  throughUnits: 70,
  grantedAt: DateTime.utc(2026, 10, 19),
);

class TestAdsServer implements AdsServer {
  bool current = true;
  String status = 'verified';
  @override
  bool get isCurrent => current;
  @override
  void close() {}
  @override
  Future<AdIntent> create(String purpose, String date, int revision) async =>
      AdIntent(
        id: 'verified-id',
        purpose: purpose,
        targetDate: date,
        targetRevision: revision,
        adUnit: 'test',
        userId: 'A',
        customData: 'verified-id',
        status: status,
        createdAt: DateTime.utc(2026),
        eventExpiresAt: DateTime.utc(2027),
        acceptUntil: DateTime.utc(2027),
      );
  @override
  Future<AdIntent> get(String id) => create('dailyReward', '2026-10-15', 1);
}

/// The claim lands, then every later read fails until [failDays] clears.
class FailingReload extends RewardRepository {
  bool failDays = false;
  @override
  Future<DailyRecord> day(DateTime date) async {
    if (failDays) throw const SocketException('offline');
    return super.day(date);
  }

  @override
  Future<RewardGrant> claim(String date, String requestId, int revision) async {
    final granted = await super.claim(date, requestId, revision);
    failDays = true;
    return granted;
  }
}

/// Echoes the requested target like the server. [status] is what the SSV
/// callback has made of the intent so far.
class EchoAdsServer implements AdsServer {
  EchoAdsServer(this.events);
  final List<String> events;
  String status = 'pending';
  String date = '';
  int revision = 0;
  @override
  bool isCurrent = true;
  @override
  void close() {}
  AdIntent get intent => AdIntent(
    id: 'intent-1',
    purpose: 'dailyReward',
    targetDate: date,
    targetRevision: revision,
    adUnit: 'unit',
    userId: 'A',
    customData: 'intent-1',
    status: status,
    createdAt: DateTime.utc(2026),
    eventExpiresAt: DateTime.utc(2027),
    acceptUntil: DateTime.utc(2027),
  );
  @override
  Future<AdIntent> create(String purpose, String date, int revision) async {
    events.add('create');
    this.date = date;
    this.revision = revision;
    return intent;
  }

  @override
  Future<AdIntent> get(String id) async {
    events.add('get');
    return intent;
  }
}

/// Keeps each request's answer like the server's request ledger: the same
/// request id returns the kept grant and never grants again.
class LedgerRepository extends RewardRepository {
  final answers = <String, RewardGrant>{};
  int grants = 0;

  /// The next grant commits, then its answer is lost on the way back.
  bool loseNextAnswer = false;

  /// Holds every answer until completed.
  Completer<void>? hold;
  @override
  Future<RewardGrant> claimWithAd(
    String date,
    String requestId,
    int revision,
    String intentId,
  ) async {
    ids.add(requestId);
    intents.add(intentId);
    if (hold case final gate?) await gate.future;
    if (answers[requestId] case final kept?) return kept;
    grants++;
    current = current.copyWith(
      revision: revision + 1,
      rewardStatus: 'settled',
      claimablePoints: 0,
      adClaimablePoints: 0,
      grantedPoints: current.grantedPoints + 140,
    );
    final answer = answers[requestId] = grant(140);
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw const SocketException('lost response');
    }
    return answer;
  }
}

class ReadySdk implements AdsSdk {
  @override
  Future<AdsSetup> prepare() async => AdsSetup.ready;
  @override
  Future<RewardedPlacement> load(String adUnit) async =>
      throw StateError('Verified intent needs no ad');
  @override
  Future<void> privacyOptions() async {}
  @override
  bool get privacyOptionsRequired => false;
}

void main() {
  late RewardRepository repository;
  late DailyStepsController steps;
  late ProductController product;
  setUp(() {
    repository = RewardRepository();
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

  test('mapping preserves operational states and legacy fixture labels', () {
    for (final entry in {
      'adRequired': DayRewardStatus.adRequired,
      'futureDate': DayRewardStatus.futureDate,
      'legacyPolicyExcluded': DayRewardStatus.legacyPolicyExcluded,
    }.entries) {
      final day = recordDay(
        record().copyWith(
          rewardStatus: entry.key,
          fixtureLabel: 'development-fixture-v1-not-production',
        ),
      );
      expect(day.rewardStatus, entry.value);
      expect(day.fixtureLabel, 'development-fixture-v1-not-production');
    }
  });

  test('response loss reuses original request, stale projection permits new action', () async {
    final day = recordDay(repository.current);
    repository.failure = const SocketException('lost response');
    await expectLater(product.claim(day), throwsA(isA<SocketException>()));
    repository.failure = null;
    expect(await product.claim(day), 20);
    expect(repository.ids[0], repository.ids[1]);
    repository.failure = ProductException(code: 'staleProjection');
    await expectLater(product.claim(day), throwsA(isA<ProductException>()));
    repository.failure = null;
    await product.claim(day);
    expect(repository.ids[2], isNot(repository.ids[3]));
  });

  test(
    'late claim after account switch never updates wallet or home',
    () async {
      var active = true;
      product.dispose();
      product = ProductController(
        repository,
        steps,
        null,
        account: 'A',
        isCurrentAccount: () => active,
      );
      repository.pendingGrant = Completer<RewardGrant>();
      final claim = product.claim(recordDay(repository.current));
      final rejected = expectLater(claim, throwsFormatException);
      active = false;
      repository.pendingGrant!.complete(grant(20));
      await rejected;
      expect(product.wallet, isNull);
      expect(product.today, isNull);
    },
  );

  Future<void> mount(
    WidgetTester tester, {
    Future<AdsController?> Function()? ads,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RewardPanel(
            controller: product,
            day: recordDay(repository.current),
            createAds: ads,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'partial free leaves expired units, a verified ad needs no second tap',
    (tester) async {
      final ads = AdsController(server: TestAdsServer(), sdk: ReadySdk());
      await mount(tester, ads: () async => ads);
      await tester.tap(find.byKey(const ValueKey('reward_free_claim')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reward_free_claim')), findsNothing);
      expect(find.byKey(const ValueKey('reward_watch_ad')), findsOneWidget);
      expect(repository.current.rewardStatus, 'adRequired');
      // Owner decision ⑤: the ad button is the one tap. The server's
      // verification closes the ad sheet and claims with it.
      await tester.tap(find.byKey(const ValueKey('reward_watch_ad')));
      await tester.pumpAndSettle();
      expect(find.byType(AdsSheet), findsNothing);
      expect(repository.intents, ['verified-id']);
      expect(repository.ids, hasLength(2));
      expect(repository.current.rewardStatus, 'settled');
      expect(find.byKey(const ValueKey('reward_ad_claim')), findsNothing);
      expect(find.byKey(const ValueKey('reward_watch_ad')), findsNothing);
    },
  );

  /// Swaps in a server ledger that remembers each request's answer.
  LedgerRepository useLedger() {
    final ledger = LedgerRepository();
    product.dispose();
    repository.client.close();
    repository = ledger;
    product = ProductController(ledger, steps, null, account: 'A');
    return ledger;
  }

  /// A day past its free window, with an ad the test plays by hand.
  Future<(EchoAdsServer, FakeAdsSdk, List<String>)> adDay(
    WidgetTester tester,
  ) async {
    repository.current = repository.current.copyWith(
      rewardStatus: 'adRequired',
      claimablePoints: 0,
      adClaimablePoints: 140,
    );
    final events = <String>[];
    final server = EchoAdsServer(events);
    final sdk = FakeAdsSdk(events);
    await mount(
      tester,
      ads: () async => AdsController(server: server, sdk: sdk),
    );
    return (server, sdk, events);
  }

  Future<void> startAd(WidgetTester tester, List<String> events) async {
    await tester.tap(find.byKey(const ValueKey('reward_watch_ad')));
    // The sheet starts the ad itself; there is no 'ads_start' tap.
    await tester.pump();
    await tester.pump();
    expect(events, containsAllInOrder(['prepare', 'create', 'show']));
    expect(find.byKey(const ValueKey('ads_start')), findsNothing);
  }

  testWidgets('a completed ad is claimed once, with no second tap', (
    tester,
  ) async {
    final (server, sdk, events) = await adDay(tester);
    await startAd(tester, events);
    // The SSV callback verifies the view, then the ad closes.
    server.status = 'verified';
    sdk.ad.reward();
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(find.byType(AdsSheet), findsNothing);
    expect(repository.intents, ['intent-1']);
    expect(repository.ids, hasLength(1));
    expect(repository.current.rewardStatus, 'settled');
    expect(find.byKey(const ValueKey('reward_ad_claim')), findsNothing);
  });

  testWidgets('an ad closed before the server verifies it grants nothing', (
    tester,
  ) async {
    final (server, sdk, events) = await adDay(tester);
    await startAd(tester, events);
    // Closed early: no SSV callback, so the intent stays pending.
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ads_status_pending')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    // A verification arriving after the close changes nothing.
    server.status = 'verified';
    await tester.pumpAndSettle();
    expect(repository.ids, isEmpty);
    expect(repository.intents, isEmpty);
    expect(find.byKey(const ValueKey('reward_ad_claim')), findsNothing);
    expect(find.byKey(const ValueKey('reward_watch_ad')), findsOneWidget);
  });

  testWidgets(
    'a lost answer is re-checked with the same request and grants at most once',
    (tester) async {
      final ledger = useLedger()..loseNextAnswer = true;
      final (server, sdk, events) = await adDay(tester);
      await startAd(tester, events);
      server.status = 'verified';
      sdk.ad.reward();
      sdk.ad.dismiss();
      await tester.pumpAndSettle();
      // The grant committed and its answer was lost. The claim stays pending
      // and nothing sends it again by itself.
      expect(ledger.grants, 1);
      expect(ledger.ids, hasLength(1));
      expect(product.hasPendingClaim, isTrue);
      expect(find.byKey(const ValueKey('reward_ad_claim')), findsNothing);
      await tester.pumpAndSettle();
      expect(ledger.ids, hasLength(1));
      final recheck = find.byKey(const ValueKey('reward_retry_claim'));
      await tester.ensureVisible(recheck);
      await tester.tap(recheck);
      await tester.pumpAndSettle();
      // The same request returns the kept grant; no second grant exists.
      expect(ledger.ids, hasLength(2));
      expect(ledger.ids.toSet(), hasLength(1));
      expect(ledger.intents, ['intent-1', 'intent-1']);
      expect(ledger.grants, 1);
      expect(product.hasPendingClaim, isFalse);
    },
  );

  testWidgets('a double tap and repeated ad events run one ad and one claim', (
    tester,
  ) async {
    final ledger = useLedger();
    final (server, sdk, events) = await adDay(tester);
    final watch = find.byKey(const ValueKey('reward_watch_ad'));
    await tester.tap(watch);
    await tester.tap(watch, warnIfMissed: false);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AdsSheet), findsOneWidget);
    expect(events.where((e) => e == 'create'), hasLength(1));
    // Hold the claim's answer to look at the panel while it is in flight.
    final answer = ledger.hold = Completer<void>();
    // An SDK that reports each event twice.
    server.status = 'verified';
    sdk.ad.reward();
    sdk.ad.reward();
    sdk.ad.dismiss();
    sdk.ad.dismiss();
    await tester.pumpAndSettle();
    expect(events.where((e) => e == 'get'), hasLength(1));
    expect(ledger.ids, hasLength(1));
    // No second way to claim while the first one is in flight.
    expect(find.byKey(const ValueKey('reward_ad_claim')), findsNothing);
    expect(tester.widget<ButtonStyleButton>(watch).onPressed, isNull);
    answer.complete();
    await tester.pumpAndSettle();
    expect(ledger.ids, hasLength(1));
    expect(ledger.grants, 1);
  });

  testWidgets('production hides the fixture marker and groups points', (
    tester,
  ) async {
    repository.current = repository.current.copyWith(
      fixtureLabel: 'development-fixture-v1-not-production',
      grantedPoints: 12345,
    );
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('개발 검증용'), findsNothing);
    expect(find.textContaining('12,345P'), findsOneWidget);
    debugFixtureLabelsVisible = true;
    addTearDown(() => debugFixtureLabelsVisible = null);
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('개발 검증용'), findsOneWidget);
  });

  testWidgets('the reload retry shows only after an automatic reload fails', (
    tester,
  ) async {
    final flaky = FailingReload();
    final reloading = ProductController(flaky, steps, null, account: 'A');
    addTearDown(() {
      reloading.dispose();
      flaky.client.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RewardPanel(
              controller: reloading,
              day: recordDay(flaky.current),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reload = find.byKey(const ValueKey('reward_reload'));
    expect(reload, findsNothing);
    await tester.tap(find.byKey(const ValueKey('reward_free_claim')));
    await tester.pumpAndSettle();
    expect(reload, findsOneWidget);
    flaky.failDays = false;
    await tester.ensureVisible(reload);
    await tester.tap(reload);
    await tester.pumpAndSettle();
    expect(reload, findsNothing);
    expect(find.byKey(const ValueKey('reward_watch_ad')), findsOneWidget);
  });

  testWidgets('closing an unverified ad never enables a reward claim', (
    tester,
  ) async {
    // Not verified at creation; the stub ad then fails to load.
    final server = TestAdsServer()..status = 'pending';
    final ads = AdsController(server: server, sdk: ReadySdk());
    await mount(tester, ads: () async => ads);
    await tester.tap(find.byKey(const ValueKey('reward_watch_ad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ads_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reward_ad_claim')), findsNothing);
    expect(repository.intents, isEmpty);
  });

  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('reward states render at $width dark $dark', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await (FontLoader('Pretendard')..addFont(
                rootBundle.load('assets/fonts/PretendardVariable.ttf'),
              ))
              .load();
        });
        for (final status in [
          'eligible',
          'adRequired',
          'settled',
          'legacyPolicyExcluded',
          'pending',
          'futureDate',
        ]) {
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: dark
                    ? ThemeData(
                        brightness: Brightness.dark,
                        fontFamily: 'Pretendard',
                      )
                    : meetingTheme(),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: RewardPanel(
                        key: ValueKey(status),
                        controller: product,
                        day: recordDay(
                          repository.current.copyWith(rewardStatus: status),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('REWARD_RENDER')) {
            await tester.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${Platform.environment['RUN_TMP']}/reward-$status-$width-$dark.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      });
    }
  }
}
