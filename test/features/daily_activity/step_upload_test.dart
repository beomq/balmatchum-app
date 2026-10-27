import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/step_upload.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async => value = data;
}

class _RealHttp extends HttpOverrides {}

AuthSuccess _auth(String suffix) => AuthSuccess(
  authStrategy: 'session',
  token: 'token-$suffix',
  authUserId: UuidValue.fromString(
    '00000000-0000-4000-8000-00000000000$suffix',
  ),
  scopeNames: {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in ['getWallet', 'claimDay', 'claimDayWithAd']) {
    test(
      '$operation fixes header and rejects successful late result after account switch',
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
          await client.auth.updateSignedInUser(_auth('1'));
          final repository = ProductRepository(
            client,
            accountId: _auth('1').authUserId.toString(),
          );
          final Future<Object> result = switch (operation) {
            'getWallet' => repository.wallet(),
            'claimDay' => repository.claim('2026-10-19', 'claim-a', 2),
            _ => repository.claimWithAd(
              '2026-10-19',
              'adclaim-a',
              2,
              'intent-a',
            ),
          };
          final rejected = expectLater(result, throwsStateError);
          final request = await arrived.future.timeout(
            const Duration(seconds: 5),
          );
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer token-1',
          );
          expect(request.uri.path, '/product/$operation');
          await client.auth.updateSignedInUser(_auth('2'));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              operation == 'getWallet'
                  ? WalletView(
                      balance: 20,
                      streamGeneration: 0,
                      policyVersion: 'steps-v1-20261019',
                    ).toJson()
                  : RewardGrant(
                      ledgerId: 1,
                      date: '2026-10-19',
                      amount: 20,
                      fromUnits: 0,
                      throughUnits: 20,
                      grantedAt: DateTime.utc(2026, 10, 19),
                    ).toJson(),
            ),
          );
          await request.response.close();
          await rejected;
          await expectLater(repository.wallet(), throwsStateError);
        }, _RealHttp());
      },
    );
  }
  test(
    'record deletion keeps captured account and rejects stale follow-up',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final arrived = Completer<HttpRequest>();
        server.listen(arrived.complete);
        final client = Client('http://127.0.0.1:${server.port}/')
          ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
        addTearDown(client.close);
        await client.auth.updateSignedInUser(_auth('1'));
        final repository = ProductRepository(
          client,
          accountId: _auth('1').authUserId.toString(),
        );
        final deletion = repository.deleteDay(
          DateTime(2026, 10, 19),
          'delete-a',
        );
        final rejected = expectLater(
          deletion,
          throwsA(isA<ServerpodClientException>()),
        );
        final request = await arrived.future.timeout(
          const Duration(seconds: 5),
        );
        await client.auth.updateSignedInUser(_auth('2'));
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer token-1',
        );
        expect(request.uri.path, '/product/deleteDay');
        request.response.statusCode = 500;
        await request.response.close();
        await rejected;
        await expectLater(
          repository.day(DateTime(2026, 10, 19)),
          throwsStateError,
        );
      }, _RealHttp());
    },
  );
  test(
    'failed submission replays its durable payload with the same account',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final dir = await Directory.systemTemp.createTemp('step-replay-');
        addTearDown(() => dir.delete(recursive: true));
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final payloads = <Map<String, dynamic>>[];
        final headers = <String?>[];
        final day = DailyRecord(
          date: '2026-10-19',
          revision: 1,
          deleted: false,
          deletionVersion: 0,
          steps: 5000,
          availability: 'confirmed',
          streamGeneration: 1,
          stepRevision: 1,
          rewardStatus: 'unconfigured',
          gracePolicyStatus: 'active',
          dailyBaseCap: 100,
          stepsPerPoint: 100,
          grantedPoints: 0,
          routes: [],
        );
        final subscription = server.listen((request) async {
          headers.add(request.headers.value(HttpHeaders.authorizationHeader));
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          request.response.headers.contentType = ContentType.json;
          switch (request.uri.path) {
            case '/product/getWallet':
              request.response.write(
                jsonEncode(
                  WalletView(
                    balance: 0,
                    streamGeneration: 0,
                    policyVersion: 'steps-v1-20261019',
                  ).toJson(),
                ),
              );
            case '/product/registerStepStream':
              request.response.write('1');
            case '/product/getDay':
              request.response.write(jsonEncode(day.toJson()));
            case '/product/submitSteps':
              payloads.add(body as Map<String, dynamic>);
              if (payloads.length == 1) {
                request.response.statusCode = 500;
                request.response.write('response unavailable');
              } else {
                request.response.write(jsonEncode(day.toJson()));
              }
            default:
              request.response.statusCode = 404;
          }
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        final client = Client('http://127.0.0.1:${server.port}/')
          ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
        addTearDown(client.close);
        await client.auth.updateSignedInUser(_auth('1'));
        final uploader = StepUpload(
          client,
          _auth('1').authUserId.toString(),
          directory: () async => dir,
        );
        await expectLater(
          uploader.submit(
            DailyStepsResult(DailyStepsStatus.available, {
              'count': 5000,
              'date': '2026-10-19',
              'observedAt': '2026-10-19T01:00:00Z',
            }),
          ),
          throwsA(isA<ServerpodClientException>()),
        );
        await uploader.submit(
          const DailyStepsResult(DailyStepsStatus.empty, null),
        );
        expect(payloads, hasLength(2));
        expect(payloads[1], payloads[0]);
        expect(headers, everyElement('Bearer token-1'));
        final file = File('${dir.path}/steps-${_auth('1').authUserId}.json');
        expect(
          (jsonDecode(await file.readAsString()) as Map)['pending'],
          isNull,
        );
      }, _RealHttp());
    },
  );

  test(
    'account switch during wallet request never registers or uploads for B',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final dir = await Directory.systemTemp.createTemp('step-account-');
        addTearDown(() => dir.delete(recursive: true));
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final arrived = Completer<HttpRequest>();
        final paths = <String>[];
        server.listen((request) {
          paths.add(request.uri.path);
          if (!arrived.isCompleted) arrived.complete(request);
        });
        final client = Client('http://127.0.0.1:${server.port}/')
          ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
        addTearDown(client.close);
        await client.auth.updateSignedInUser(_auth('1'));
        final upload =
            StepUpload(
              client,
              _auth('1').authUserId.toString(),
              directory: () async => dir,
            ).submit(
              DailyStepsResult(DailyStepsStatus.available, {
                'count': 5000,
                'date': '2026-10-19',
                'observedAt': '2026-10-19T01:00:00Z',
              }),
            );
        final rejected = expectLater(upload, throwsStateError);
        final request = await arrived.future.timeout(
          const Duration(seconds: 5),
        );
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer token-1',
        );
        await client.auth.updateSignedInUser(_auth('2'));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            WalletView(
              balance: 0,
              streamGeneration: 0,
              policyVersion: 'steps-v1-20261019',
            ).toJson(),
          ),
        );
        await request.response.close();
        await rejected;
        expect(paths, ['/product/getWallet']);
        expect(await dir.list().toList(), isEmpty);
      }, _RealHttp());
    },
  );
}
