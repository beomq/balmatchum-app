import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/auth/account_deletion.dart';
import 'package:balmatchum_app/features/billing/billing_providers.dart';
import 'package:balmatchum_app/features/billing/billing_repository.dart';
import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/home_bootstrap.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/scoped_client.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../daily_activity/home_bootstrap_test.dart' show snapshot;

class _CountingClient extends Client {
  _CountingClient(super.host, {super.connectionTimeout});
  int closeCalls = 0;

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async => value = data;
}

class _Header implements ClientAuthKeyProvider {
  _Header(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}

/// Billing that still sees the signed-in account, as it does when the
/// sign-out after the deletion never ran.
class _CurrentBilling extends ServerpodBillingRepository {
  _CurrentBilling(Client client) : super(client, 'A', BillingRequestQueue());
  @override
  bool get isCurrent => true;
}

const _host = 'http://localhost:1/';

String get _today => ProductRepository.dateKey(ProductRepository.today);

void main() {
  late List<_CountingClient> created;
  late ScopedClientPool pool;
  late Client client;

  setUp(() {
    created = [];
    client = Client(_host)
      ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
    pool = ScopedClientPool(
      host: _host,
      factory: (host, timeout) {
        final scoped = _CountingClient(host, connectionTimeout: timeout);
        created.add(scoped);
        return scoped;
      },
    );
  });

  tearDown(() {
    pool.close();
    client.close();
  });

  /// Account A signed in, with the app's own deletion wiring.
  ProviderContainer signedIn(HomeBootstrap bootstrap) {
    final container = ProviderContainer(
      overrides: [
        authenticatedAccountProvider.overrideWithValue('A'),
        clientProvider.overrideWithValue(client),
        accountClientPoolProvider.overrideWithValue(pool),
        homeBootstrapProvider.overrideWithValue(bootstrap),
        billingRepositoryProvider.overrideWithValue(_CurrentBilling(client)),
        dailyStepsControllerProvider.overrideWithValue(
          DailyStepsController(
            readSteps: () async => throw UnimplementedError(),
          ),
        ),
        logoutProvider.overrideWithValue(
          () async => throw StateError('sign-out is not reached'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The server deletes the account, then saving the deletion marker fails.
  Future<List<String>> deleteWithFailingMarker(
    ProviderContainer container,
  ) async {
    final events = <String>[];
    final deletion = AccountDeletion(
      forgetAccount: container.read(accountDeletionProvider)!.forgetAccount,
      markPending: () async {},
      clearPending: () async {},
      wasRemoteDeleted: () async => false,
      markRemoteDeleted: () async =>
          throw const FileSystemException('disk full'),
      deleteRemote: () async => events.add('remote'),
      revokeProviders: () async => events.add('revoke'),
      clearLocal: () async => events.add('clear'),
      signOut: () async => events.add('logout'),
    );
    await expectLater(deletion.delete(), throwsA(isA<FileSystemException>()));
    return events;
  }

  test(
    'marker failure after remote deletion still discards the home snapshot',
    () async {
      final bootstrap = HomeBootstrap()
        ..start('A', () async => snapshot(_today));
      final container = signedIn(bootstrap);
      expect(bootstrap.peek('A'), isNotNull);

      final events = await deleteWithFailingMarker(container);

      final peeked = bootstrap.peek('A');
      final taken = bootstrap.take('A');
      debugPrint('(a) events=$events peek=$peeked take=$taken');
      expect(events, ['remote']);
      expect(peeked, isNull);
      expect(taken, isNull);
    },
  );

  test(
    'marker failure retires the pooled client without aborting a request',
    () async {
      final container = signedIn(HomeBootstrap());
      final started = Completer<void>();
      final gate = Completer<String>();
      final inFlight = pool.run('h', _Header.new, (_) async {
        started.complete();
        return gate.future;
      });
      await started.future;
      expect(created, hasLength(1));

      await deleteWithFailingMarker(container);
      final closedWhileInFlight = created.single.closeCalls;
      await pool.run('h', _Header.new, (_) async {});
      final afterNext = created.length;
      gate.complete('late answer');
      final answer = await inFlight;

      debugPrint(
        '(b) clients=$afterNext closedWhileInFlight=$closedWhileInFlight '
        'answer=$answer closeCalls=${[for (final c in created) c.closeCalls]}',
      );
      expect(closedWhileInFlight, 0);
      expect(afterNext, 2);
      expect(answer, 'late answer');
      expect(created[0].closeCalls, 1);
      expect(created[1].closeCalls, 0);
    },
  );

  test('a late home answer after remote deletion is not shown', () async {
    final read = Completer<HomeSnapshot>();
    final bootstrap = HomeBootstrap()..start('A', () => read.future);
    final container = signedIn(bootstrap);
    final controller = container.read(authenticatedProductControllerProvider)!;
    expect(controller.isActive, isTrue);
    // The refresh takes the started snapshot before it answers.
    final refresh = controller.refresh();
    expect(bootstrap.peek('A'), isNull);

    await deleteWithFailingMarker(container);
    read.complete(snapshot(_today));

    await expectLater(refresh, throwsFormatException);
    debugPrint(
      '(c) active=${controller.isActive} today=${controller.today} '
      'wallet=${controller.wallet} streak=${controller.streak}',
    );
    expect(controller.isActive, isFalse);
    expect(controller.today, isNull);
    expect(controller.wallet, isNull);
    expect(controller.streak, isNull);
  });

  test('without a deletion the same late home answer is shown', () async {
    final read = Completer<HomeSnapshot>();
    final bootstrap = HomeBootstrap()..start('A', () => read.future);
    final controller = signedIn(bootstrap)
        .read(authenticatedProductControllerProvider)!;

    final refresh = controller.refresh();
    read.complete(snapshot(_today));
    await refresh;

    expect(controller.today, isNotNull);
    expect(controller.wallet, isNotNull);
  });
}
