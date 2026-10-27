import 'dart:async';

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ads_fakes.dart';

Future<void> start(AdsController c) => c.start(
  purpose: 'dailyReward',
  targetDate: '2026-10-19',
  targetRevision: 2,
);

Future<void> untilStatus(AdsController c, AdsStatus status) {
  final done = Completer<void>();
  void changed() {
    if (c.status == status) {
      c.removeListener(changed);
      done.complete();
    }
  }

  c.addListener(changed);
  return done.future.timeout(const Duration(seconds: 5));
}

void main() {
  late List<String> events;
  late FakeAdsServer server;
  late FakeAdsSdk sdk;
  late AdsController controller;
  setUp(() {
    events = [];
    server = FakeAdsServer(events);
    sdk = FakeAdsSdk(events);
    controller = AdsController(server: server, sdk: sdk);
  });
  tearDown(() => controller.dispose());

  test('missing server placement configuration is distinct', () async {
    server.createError = AdException(code: 'configurationMissing');
    await start(controller);
    expect(controller.status, AdsStatus.missingConfiguration);
    expect(events.where((e) => e.startsWith('load')), isEmpty);
  });

  test(
    'orders create load SSV show; client reward never grants or verifies',
    () async {
      await start(controller);
      expect(events, [
        'prepare',
        'create:dailyReward:2026-10-19:2',
        'load:server-unit',
        'ssv:server-user:server-custom',
        'show',
      ]);
      sdk.ad.reward();
      expect(controller.clientRewardObserved, isTrue);
      expect(controller.status, AdsStatus.showing);
      expect(server.gets, 0);
      final pending = untilStatus(controller, AdsStatus.pending);
      sdk.ad.dismiss();
      sdk.ad.dismiss();
      sdk.ad.fail();
      await pending;
      expect(server.gets, 1);
      expect(sdk.ad.disposals, 1);
      controller.dispose();
      controller.dispose();
      expect(sdk.ad.disposals, 1);
      expect(server.closes, 1);
    },
  );

  test('manual refresh verifies pending; no replay or polling', () async {
    await start(controller);
    final pending = untilStatus(controller, AdsStatus.pending);
    sdk.ad.dismiss();
    await pending;
    server.status = 'verified';
    await controller.refresh();
    expect(controller.status, AdsStatus.verified);
    expect(server.gets, 2);
    await controller.refresh();
    expect(server.gets, 2);
  });

  test('missing config and consent failure never create an intent', () async {
    sdk.setup = AdsSetup.missingConfiguration;
    await start(controller);
    expect(controller.status, AdsStatus.missingConfiguration);
    sdk.setup = AdsSetup.consentRequired;
    await start(controller);
    expect(controller.status, AdsStatus.consentRequired);
    expect(events, ['prepare', 'prepare']);
  });

  test(
    'failed load remains failure, retry reconciles original intent',
    () async {
      sdk.failLoad = true;
      await start(controller);
      expect(controller.status, AdsStatus.failed);
      expect(sdk.ad.disposals, 0);
      server.status = 'verified';
      await controller.retry(
        purpose: 'dailyReward',
        targetDate: '2026-10-19',
        targetRevision: 2,
      );
      expect(controller.status, AdsStatus.verified);
      expect(server.gets, 1);
    },
  );

  test('show failure disposes once without status request', () async {
    await start(controller);
    sdk.ad.fail();
    sdk.ad.dismiss();
    expect(controller.status, AdsStatus.failed);
    expect(sdk.ad.disposals, 1);
    expect(server.gets, 0);
  });

  test('stale session during create never loads', () async {
    server.creating = Completer();
    final creating = untilStatus(controller, AdsStatus.creating);
    final operation = start(controller);
    await creating;
    server.isCurrent = false;
    server.creating!.complete(adIntent());
    await operation;
    expect(controller.status, AdsStatus.cancelled);
    expect(events.where((s) => s.startsWith('load')), isEmpty);
  });

  test('cancel during load disposes late ad without SSV or show', () async {
    sdk.loading = Completer();
    final loading = untilStatus(controller, AdsStatus.loading);
    final operation = start(controller);
    await loading;
    controller.cancel();
    sdk.loading!.complete(sdk.ad);
    await operation;
    expect(controller.status, AdsStatus.cancelled);
    expect(sdk.ad.disposals, 1);
    expect(events.where((s) => s.startsWith('ssv') || s == 'show'), isEmpty);
  });

  test('account change ignores late reward and server response', () async {
    await start(controller);
    server.getting = Completer();
    final checking = untilStatus(controller, AdsStatus.checking);
    sdk.ad.dismiss();
    await checking;
    server.isCurrent = false;
    sdk.ad.reward();
    server.getting!.complete(adIntent('verified'));
    expect(controller.status, AdsStatus.cancelled);
    expect(controller.clientRewardObserved, isFalse);
  });

  for (final state in ['verified', 'consumed', 'expired']) {
    test('server $state is terminal and does not load', () async {
      server.status = state;
      await start(controller);
      expect(controller.status.name, state);
      expect(events.where((s) => s.startsWith('load')), isEmpty);
    });
  }
}
