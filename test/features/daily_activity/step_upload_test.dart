import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/scoped_client.dart';
import 'package:balmatchum_app/features/daily_activity/step_upload.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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
        final pool = ScopedClientPool(host: client.host);
        addTearDown(pool.close);
        final uploader = StepUpload(
          client,
          _auth('1').authUserId.toString(),
          pool: pool,
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
        final pool = ScopedClientPool(host: client.host);
        addTearDown(pool.close);
        final upload =
            StepUpload(
              client,
              _auth('1').authUserId.toString(),
              pool: pool,
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

  group('snapshot reuse', () {
    test('known day and generation upload with submitSteps only', () async {
      await _rig((rig) async {
        await rig.writeState({'generation': 1, 'revision': 0});
        await rig.upload.submit(
          _observation(),
          knownDay: _day(),
          knownStreamGeneration: 1,
        );
        debugPrint('known day: ${rig.calls}');
        expect(rig.calls, ['submitSteps']);
      });
    });

    test(
      'first registration skips getWallet with a known generation',
      () async {
        await _rig((rig) async {
          await rig.upload.submit(
            _observation(),
            knownDay: _day(),
            knownStreamGeneration: 0,
          );
          debugPrint('first registration: ${rig.calls}');
          expect(rig.calls, ['registerStepStream', 'submitSteps']);
        });
      },
    );

    test('without snapshot data it still reads the day first', () async {
      await _rig((rig) async {
        await rig.writeState({'generation': 1, 'revision': 0});
        await rig.upload.submit(_observation());
        debugPrint('no snapshot: ${rig.calls}');
        expect(rig.calls, ['getDay', 'submitSteps']);
      });
    });

    test('first registration without snapshot data reads the wallet', () async {
      await _rig((rig) async {
        await rig.upload.submit(_observation());
        debugPrint('no snapshot registration: ${rig.calls}');
        expect(rig.calls, [
          'getWallet',
          'registerStepStream',
          'getDay',
          'submitSteps',
        ]);
      });
    });

    test('a known day for another date is not trusted', () async {
      await _rig((rig) async {
        await rig.writeState({'generation': 1, 'revision': 0});
        await rig.upload.submit(
          _observation(),
          knownDay: _day(date: '2026-10-18', deleted: true),
        );
        expect(rig.calls, ['getDay', 'submitSteps']);
      });
    });

    test('a deleted known day makes no server call', () async {
      await _rig((rig) async {
        await rig.writeState({'generation': 1, 'revision': 0});
        final known = _day(deleted: true);
        final result = await rig.upload.submit(
          _observation(),
          knownDay: known,
          knownStreamGeneration: 1,
        );
        debugPrint('deleted known day: ${rig.calls}');
        expect(rig.calls, isEmpty);
        expect(result, same(known));
      });
    });

    test('a pending payload is still re-sent before the upload', () async {
      await _rig((rig) async {
        final pending = DailyStepInput(
          date: '2026-10-19',
          streamGeneration: 1,
          revision: 1,
          windowStart: DateTime.utc(2026, 10, 18, 15),
          windowEnd: DateTime.utc(2026, 10, 19, 15),
          observedAt: DateTime.utc(2026, 10, 19, 1),
          total: 4000,
          availability: 'confirmed',
        );
        await rig.writeState({
          'generation': 1,
          'revision': 1,
          'pending': pending.toJson(),
        });
        await rig.upload.submit(
          _observation(),
          knownDay: _day(),
          knownStreamGeneration: 1,
        );
        debugPrint('pending re-send: ${rig.calls}');
        expect(rig.calls, ['submitSteps', 'submitSteps']);
        expect(rig.state['pending'], isNull);
        expect(rig.state['revision'], 2);
      });
    });

    test('an account switch while a pending upload is paused rejects it even '
        'on a pool another caller created', () async {
      await _rig((rig) async {
        final pending = DailyStepInput(
          date: '2026-10-19',
          streamGeneration: 1,
          revision: 1,
          windowStart: DateTime.utc(2026, 10, 18, 15),
          windowEnd: DateTime.utc(2026, 10, 19, 15),
          observedAt: DateTime.utc(2026, 10, 19, 1),
          total: 4000,
          availability: 'confirmed',
        );
        await rig.writeState({
          'generation': 1,
          'revision': 1,
          'pending': pending.toJson(),
        });
        // Another caller (like the repository's reads) creates the pooled
        // client first, with a provider that never checks the account.
        final header = (await rig.client.auth.authHeaderValue)!;
        await rig.pool.run(header, _Unchecked.new, (_) async {});
        final entered = Completer<void>();
        final release = Completer<Directory>();
        rig.directoryHook = () {
          entered.complete();
          return release.future;
        };
        final upload = rig.upload.submit(
          _observation(),
          knownDay: _day(),
          knownStreamGeneration: 1,
        );
        final rejected = expectLater(upload, throwsStateError);
        await entered.future;
        await rig.client.auth.updateSignedInUser(_auth('2'));
        release.complete(rig.dir);
        await rejected;
        debugPrint('stale account: ${rig.calls} clients=${rig.created}');
        expect(rig.calls, isEmpty);
        expect(rig.created, 1);
      });
    });

    test('two uploads share one client', () async {
      await _rig((rig) async {
        await rig.writeState({'generation': 1, 'revision': 0});
        await rig.upload.submit(
          _observation(),
          knownDay: _day(),
          knownStreamGeneration: 1,
        );
        await rig.upload.submit(
          _observation(),
          knownDay: _day(),
          knownStreamGeneration: 1,
        );
        debugPrint('two uploads: ${rig.calls} clients=${rig.created}');
        expect(rig.created, 1);
        expect(rig.calls, ['submitSteps', 'submitSteps']);
      });
    });
  });
}

class _Unchecked implements ClientAuthKeyProvider {
  _Unchecked(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}

DailyRecord _day({String date = '2026-10-19', bool deleted = false}) =>
    DailyRecord(
      date: date,
      revision: 1,
      deleted: deleted,
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

DailyStepsResult _observation() => DailyStepsResult(
  DailyStepsStatus.available,
  {'count': 5000, 'date': '2026-10-19', 'observedAt': '2026-10-19T01:00:00Z'},
);

class _Rig {
  _Rig(this.dir, this.client, this.pool, this.upload);
  final Directory dir;
  final Client client;
  final ScopedClientPool pool;
  Future<Directory> Function()? directoryHook;
  final StepUpload upload;
  final calls = <String>[];
  int created = 0;

  File get _file => File('${dir.path}/steps-${_auth('1').authUserId}.json');
  Map<String, dynamic> get state =>
      jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
  Future<void> writeState(Map<String, dynamic> value) =>
      _file.writeAsString(jsonEncode(value));
}

/// Records each endpoint name the server receives, in order.
Future<void> _rig(Future<void> Function(_Rig rig) body) =>
    HttpOverrides.runWithHttpOverrides(() async {
      final dir = await Directory.systemTemp.createTemp('step-snapshot-');
      addTearDown(() => dir.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      late final _Rig rig;
      final subscription = server.listen((request) async {
        final name = request.uri.pathSegments.last;
        await request.drain<void>();
        rig.calls.add(name);
        request.response.headers.contentType = ContentType.json;
        switch (name) {
          case 'getWallet':
            request.response.write(
              jsonEncode(
                WalletView(
                  balance: 0,
                  streamGeneration: 0,
                  policyVersion: 'steps-v1-20261019',
                ).toJson(),
              ),
            );
          case 'registerStepStream':
            request.response.write('1');
          default:
            request.response.write(jsonEncode(_day().toJson()));
        }
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = Client('http://127.0.0.1:${server.port}/')
        ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
      addTearDown(client.close);
      await client.auth.updateSignedInUser(_auth('1'));
      final pool = ScopedClientPool(
        host: client.host,
        factory: (host, timeout) {
          rig.created++;
          return Client(host, connectionTimeout: timeout);
        },
      );
      addTearDown(pool.close);
      rig = _Rig(
        dir,
        client,
        pool,
        StepUpload(
          client,
          _auth('1').authUserId.toString(),
          pool: pool,
          directory: () => rig.directoryHook?.call() ?? Future.value(dir),
        ),
      );
      await body(rig);
    }, _RealHttp());
