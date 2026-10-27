import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/ads/ads_controller.dart';
import 'package:balmatchum_app/features/ads/ads_session.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'ads_fakes.dart';

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async {
    value = data;
  }
}

class _Http extends HttpOverrides {}

AuthSuccess auth(String suffix) => AuthSuccess(
  authStrategy: 'session',
  token: 'test-token-$suffix',
  authUserId: UuidValue.fromString(
    '00000000-0000-4000-8000-00000000000$suffix',
  ),
  scopeNames: {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final refresh in [false, true]) {
    test(
      'fixed credential ${refresh ? 'get' : 'create'} rejects next account',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          final arrived = Completer<HttpRequest>();
          server.listen(arrived.complete);
          final client = Client('http://127.0.0.1:${server.port}/')
            ..authSessionManager = FlutterAuthSessionManager(
              storage: _Storage(),
            );
          addTearDown(client.close);
          await client.auth.updateSignedInUser(auth('1'));
          final controller = (await createAdsController(
            client,
            sdk: FakeAdsSdk([]),
          ))!;
          addTearDown(controller.dispose);
          if (refresh) {
            controller.intent = adIntent();
            controller.status = AdsStatus.pending;
          }
          final operation = refresh
              ? controller.refresh()
              : controller.start(
                  purpose: 'dailyReward',
                  targetDate: '2026-10-19',
                  targetRevision: 2,
                );
          final request = await arrived.future.timeout(
            const Duration(seconds: 5),
          );
          await client.auth.updateSignedInUser(auth('2'));
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer test-token-1',
          );
          expect(
            request.uri.path,
            refresh ? '/ads/getIntent' : '/ads/createIntent',
          );
          expect(controller.status, AdsStatus.cancelled);
          request.response.statusCode = 500;
          await request.response.close();
          await operation;
          expect(controller.status, AdsStatus.cancelled);
          await controller.start(
            purpose: 'dailyReward',
            targetDate: '2026-10-19',
            targetRevision: 2,
          );
          expect(controller.status, AdsStatus.cancelled);
        }, _Http());
      },
    );
  }
}
