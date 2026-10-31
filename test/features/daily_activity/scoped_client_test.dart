import 'dart:async';

import 'package:balmatchum_app/features/daily_activity/scoped_client.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingClient extends Client {
  _CountingClient(super.host, {super.connectionTimeout});
  int closeCalls = 0;

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

class _Header implements ClientAuthKeyProvider {
  _Header(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}

void main() {
  late List<_CountingClient> created;
  late ScopedClientPool pool;

  setUp(() {
    created = [];
    pool = ScopedClientPool(
      host: 'http://localhost:1/',
      connectionTimeout: const Duration(seconds: 3),
      factory: (host, timeout) {
        final client = _CountingClient(host, connectionTimeout: timeout);
        created.add(client);
        return client;
      },
    );
  });

  tearDown(() => pool.close());

  test('same header reuses one client instance', () async {
    final seen = <Client>[];
    await pool.run('a', _Header.new, (c) async => seen.add(c));
    await pool.run('a', _Header.new, (c) async => seen.add(c));

    expect(created, hasLength(1));
    expect(identical(seen[0], seen[1]), isTrue);
    expect(created.single.closeCalls, 0);
    expect(created.single.connectionTimeout, const Duration(seconds: 3));
  });

  test('close on header change', () async {
    await pool.run('a', _Header.new, (_) async {});
    await pool.run('b', _Header.new, (_) async {});

    expect(created, hasLength(2));
    expect(created[0].closeCalls, 1);
    expect(created[1].closeCalls, 0);
  });

  test('retired client closes only after in-flight request finishes', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final inFlight = pool.run('a', _Header.new, (_) async {
      started.complete();
      await gate.future;
    });
    await started.future;

    await pool.run('b', _Header.new, (_) async {});
    expect(created[0].closeCalls, 0);

    gate.complete();
    await inFlight;
    expect(created[0].closeCalls, 1);
  });

  test('close retires the current client once', () async {
    await pool.run('a', _Header.new, (_) async {});
    pool.close();
    pool.close();

    expect(created.single.closeCalls, 1);
  });
}
