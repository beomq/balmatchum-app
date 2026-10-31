import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/scoped_client.dart';
import 'package:balmatchum_app/features/quiz/quiz_repository.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../ads/ads_session_test.dart' show auth;

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async {
    value = data;
  }
}

class _CountingClient extends Client {
  _CountingClient(super.host, {super.connectionTimeout});
  int closeCalls = 0;

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

class _Http extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consecutive requests create one pooled client, close retires it', () {
    return HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<Object>[]));
        await request.response.close();
      });
      final client = Client('http://127.0.0.1:${server.port}/')
        ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
      addTearDown(client.close);
      await client.auth.updateSignedInUser(auth('1'));

      final created = <_CountingClient>[];
      final repository = QuizRepository(
        client,
        client.auth.authInfo!.authUserId.toString(),
        pool: ScopedClientPool(
          host: client.host,
          connectionTimeout: client.connectionTimeout,
          factory: (host, timeout) {
            final scoped = _CountingClient(host, connectionTimeout: timeout);
            created.add(scoped);
            return scoped;
          },
        ),
      );

      await repository.history(null);
      await repository.history(null);
      await repository.history(null);

      expect(created, hasLength(1));
      expect(created.single.closeCalls, 0);

      repository.close();
      expect(created.single.closeCalls, 1);
    }, _Http());
  });
}
