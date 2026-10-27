import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_sdk.dart';

AdIntent adIntent([String status = 'pending']) => AdIntent(
  id: 'intent',
  purpose: 'dailyReward',
  targetDate: '2026-10-19',
  targetRevision: 2,
  adUnit: 'server-unit',
  userId: 'server-user',
  customData: 'server-custom',
  status: status,
  createdAt: DateTime.utc(2026, 10, 19),
  eventExpiresAt: DateTime.utc(2026, 10, 19, 1),
  acceptUntil: DateTime.utc(2026, 10, 26, 1),
);

class FakeAdsServer implements AdsServer {
  FakeAdsServer(this.events);
  final List<String> events;
  @override
  bool isCurrent = true;
  String status = 'pending';
  Completer<AdIntent>? creating;
  Completer<AdIntent>? getting;
  Object? createError;
  int gets = 0;
  int closes = 0;
  @override
  Future<AdIntent> create(String purpose, String date, int revision) async {
    events.add('create:$purpose:$date:$revision');
    if (createError != null) throw createError!;
    return creating?.future ?? adIntent(status);
  }

  @override
  Future<AdIntent> get(String id) async {
    events.add('get:$id');
    gets++;
    return getting?.future ?? adIntent(status);
  }

  @override
  void close() {
    closes++;
  }
}

class FakeAdsSdk implements AdsSdk {
  FakeAdsSdk(this.events) : ad = FakePlacement(events);
  final List<String> events;
  final FakePlacement ad;
  AdsSetup setup = AdsSetup.ready;
  bool failLoad = false;
  Completer<RewardedPlacement>? loading;
  @override
  bool privacyOptionsRequired = false;
  @override
  Future<void> privacyOptions() async {}
  @override
  Future<AdsSetup> prepare() async {
    events.add('prepare');
    return setup;
  }

  @override
  Future<RewardedPlacement> load(String unit) async {
    events.add('load:$unit');
    if (failLoad) throw StateError('load failed');
    return loading?.future ?? ad;
  }
}

class FakePlacement implements RewardedPlacement {
  FakePlacement(this.events);
  final List<String> events;
  late void Function() reward;
  late void Function() dismiss;
  late void Function() fail;
  int disposals = 0;
  @override
  Future<void> setVerification(String user, String data) async {
    events.add('ssv:$user:$data');
  }

  @override
  Future<void> show({
    required void Function() onReward,
    required void Function() onDismiss,
    required void Function() onFailure,
  }) async {
    events.add('show');
    reward = onReward;
    dismiss = onDismiss;
    fail = onFailure;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    events.add('dispose');
  }
}
