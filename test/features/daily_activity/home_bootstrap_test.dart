import 'package:balmatchum_app/features/daily_activity/home_bootstrap.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'product_controller_test.dart' show outfitStore, record, themeStore;

HomeSnapshot snapshot(String date) => HomeSnapshot(
  date: date,
  day: record(),
  wallet: WalletView(
    balance: 0,
    streamGeneration: 0,
    policyVersion: 'steps-v1-20261019',
  ),
  themes: themeStore(),
  outfits: outfitStore(),
  recentDays: const [],
);

void main() {
  test('starts once per account and is taken once', () async {
    final bootstrap = HomeBootstrap();
    var reads = 0;
    Future<HomeSnapshot> read() async {
      reads++;
      return snapshot('2026-10-31');
    }

    bootstrap
      ..start('A', read)
      ..start('A', read);
    expect(reads, 1);
    expect(bootstrap.take('B'), isNull);
    expect((await bootstrap.take('A'))!.date, '2026-10-31');
    expect(bootstrap.take('A'), isNull);
    // A taken snapshot is not started again for the same account.
    bootstrap.start('A', read);
    expect(reads, 1);
    expect(bootstrap.take('A'), isNull);
  });

  test('another account discards the earlier snapshot', () async {
    final bootstrap = HomeBootstrap()
      ..start('A', () async => snapshot('a'))
      ..start('B', () async => snapshot('b'));
    expect(bootstrap.take('A'), isNull);
    expect((await bootstrap.take('B'))!.date, 'b');
  });

  test('discard on sign-out or deletion drops an untaken snapshot', () async {
    final bootstrap = HomeBootstrap()
      // A failure nobody takes is not reported as unhandled.
      ..start('A', () async => throw StateError('deleted account'))
      ..discard();
    expect(bootstrap.take('A'), isNull);
    // After the discard the same account may start a fresh one.
    bootstrap.start('A', () async => snapshot('again'));
    expect((await bootstrap.take('A'))!.date, 'again');
  });

  test('a taken failure still reaches the refresh', () async {
    final bootstrap = HomeBootstrap()
      ..start('A', () async => throw StateError('offline'));
    await expectLater(bootstrap.take('A'), throwsStateError);
  });
}
