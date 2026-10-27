import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/record_mapping.dart';
import 'package:balmatchum_app/features/daily_activity/reward_panel.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'product_controller_test.dart';

class RewardRepository extends AccountRepository {
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
    'partial free leaves expired units, verified close requires explicit ad claim',
    (tester) async {
      final ads = AdsController(server: TestAdsServer(), sdk: ReadySdk());
      await mount(tester, ads: () async => ads);
      await tester.tap(find.byKey(const ValueKey('reward_free_claim')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reward_free_claim')), findsNothing);
      expect(find.byKey(const ValueKey('reward_watch_ad')), findsOneWidget);
      expect(repository.current.rewardStatus, 'adRequired');
      await tester.tap(find.byKey(const ValueKey('reward_watch_ad')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ads_start')));
      await tester.pumpAndSettle();
      expect(ads.status, AdsStatus.verified);
      expect(repository.intents, isEmpty);
      await tester.tap(find.byKey(const ValueKey('ads_close')));
      await tester.pumpAndSettle();
      expect(repository.intents, isEmpty);
      await tester.tap(find.byKey(const ValueKey('reward_ad_claim')));
      await tester.pumpAndSettle();
      expect(repository.intents, ['verified-id']);
      expect(repository.current.rewardStatus, 'settled');
      expect(find.byKey(const ValueKey('reward_watch_ad')), findsNothing);
    },
  );

  testWidgets('closing an unverified ad never enables a reward claim', (
    tester,
  ) async {
    final ads = AdsController(server: TestAdsServer(), sdk: ReadySdk());
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
