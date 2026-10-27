import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/auth/auth_adapters.dart';
import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_app/features/watch_sync/watch_contract.dart'
    as watch;
import 'package:balmatchum_app/features/watch_sync/watch_sync_server.dart';
import 'package:balmatchum_app/features/watch_sync/watch_sync_service.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../first_meeting/domain/authenticated_profile_test.dart'
    show Profiles, view;
import '../first_meeting/domain/first_meeting_test.dart' show MemoryStorage;

const _methods = MethodChannel('com.beomq.balmatchum/watch');
const _events = MethodChannel('com.beomq.balmatchum/watch/events');
const _id = '12345678-1234-4234-8234-123456789abc';
const _serverId = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';

class _RealHttpOverrides extends HttpOverrides {}

Map<String, Object?> _record([String context = 'context-a']) => {
  'schemaVersion': 1,
  'contextId': context,
  'kind': 'gpsRecord',
  'recordId': _id,
  'startedAt': '2026-10-09T01:00:00Z',
  'endedAt': '2026-10-09T01:02:00Z',
  'payload': {
    'points': [
      {
        'latitude': 37.5,
        'longitude': 127.0,
        'horizontalAccuracyMeters': 5,
        'recordedAt': '2026-10-09T01:01:00Z',
      },
      {
        'latitude': 37.6,
        'longitude': 127.1,
        'horizontalAccuracyMeters': 6,
        'recordedAt': '2026-10-09T01:01:30Z',
      },
    ],
  },
};

RecordReceipt _receipt() => RecordReceipt(
  clientRecordId: UuidValue.fromString(_id),
  recordId: UuidValue.fromString(_serverId),
  persistedAt: DateTime.utc(2026, 10, 9, 2),
  schemaVersion: 1,
);

class _Server implements WatchSyncServer {
  @override
  String? accountId = 'account-a';
  int validations = 0;
  bool valid = true;
  Future<bool> Function()? validate;
  Future<RecordReceipt> Function()? save;
  final inputs = <GpsRecordInput>[];
  final accounts = <String>[];

  @override
  Future<bool> validateAuthentication() async {
    validations++;
    return validate == null ? valid : await validate!();
  }

  @override
  Future<RecordReceipt> saveConfirmed(
    String accountId,
    GpsRecordInput input,
  ) async {
    accounts.add(accountId);
    inputs.add(input);
    return save == null ? _receipt() : await save!();
  }
}

class _Native {
  final calls = <MethodCall>[];
  List<String> records = [jsonEncode(_record())];
  Object activation = {
    'contextId': 'context-a',
    'boundaryRevision': 3,
    'latestDisplayRevision': 7,
  };
  Object steps = {'status': 'unavailable', 'dailySteps': null};
  String? failMethod;
  Completer<void>? listed;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == failMethod) {
      throw PlatformException(code: 'failure', message: 'sensitive');
    }
    switch (call.method) {
      case 'activateContext':
        return activation;
      case 'listPendingRecords':
        if (listed != null && !listed!.isCompleted) listed!.complete();
        return records.toList();
      case 'acknowledgeServerReceipt':
        records.clear();
        return null;
      case 'requestDailySteps':
        return steps;
      default:
        return null;
    }
  }

  List<MethodCall> named(String name) =>
      calls.where((call) => call.method == name).toList();
}

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  bool fail = false;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async {
    if (fail) throw Exception('storage');
    value = data;
  }
}

AuthSuccess _auth(String suffix) => AuthSuccess(
  authStrategy: 'session',
  token: 'token-$suffix',
  authUserId: UuidValue.fromString(
    '00000000-0000-4000-8000-00000000000$suffix',
  ),
  scopeNames: {},
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Native native;
  late _Server server;
  late WatchSyncService service;

  setUp(() {
    native = _Native();
    server = _Server();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _methods,
      native.handle,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _events,
      (_) async => null,
    );
    service = WatchSyncService(bridge: WatchBridge(), server: server);
  });
  tearDown(() async {
    await service.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_methods, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_events, null);
  });

  test(
    'startup clears persisted boundary without validating or uploading',
    () async {
      await service.initialize();
      expect(native.calls.map((call) => call.method), ['clearContext']);
      expect(server.validations, 0);
      expect(server.inputs, isEmpty);
      expect(service.isActive, isFalse);
    },
  );

  test(
    'server profile restoration and rename publish stable owner identity',
    () async {
      native.records = [];
      await service.initialize();
      final profiles = Profiles()..current = view();
      final controller = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: profiles,
      );
      final stop = service.observeProfile('account-a', controller);
      addTearDown(() {
        stop();
        controller.dispose();
      });
      await controller.initialize();
      // A server profile is display data, not permission to activate or upload.
      await service.requestDailySteps();
      expect(native.named('publishDisplaySnapshot'), isEmpty);
      expect(server.validations, 0);
      expect(server.inputs, isEmpty);
      await service.resumeAndSync();
      Map dog() =>
          (jsonDecode(
                native.named('publishDisplaySnapshot').last.arguments as String,
              ) as Map)['selectedDog']
              as Map;
      expect(dog(), {
        'dogId': 'owner:account-a',
        'displayName': '보리',
        'assetKey': 'dog.preview.pug',
      });
      await controller.renameDog('새이름');
      await service.requestDailySteps();
      expect(dog()['displayName'], '새이름');
      expect(dog()['dogId'], 'owner:account-a');
      profiles.current = view(name: '오래된이름', revision: 1);
      await controller.restore();
      await service.requestDailySteps();
      expect(dog()['displayName'], '새이름');
    },
  );

  test(
    'switch and logout clear dogs and reject late old epoch profiles',
    () async {
      native.records = [];
      await service.resumeAndSync();
      final profiles = Profiles()..current = view();
      final old = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: profiles,
      );
      final stopOld = service.observeProfile('account-a', old);
      addTearDown(() {
        stopOld();
        old.dispose();
      });
      await old.initialize();
      await service.requestDailySteps();
      profiles.reading = Completer<ProfileView?>();
      // Drain the controller queue until the exact request is in flight.
      final reached = Completer<void>();
      old.addListener(() {
        if (old.isBusy && !reached.isCompleted) reached.complete();
      });
      final restoring = old.restore();
      await reached.future.timeout(const Duration(seconds: 2));
      final clear = service.clearContext();
      server.accountId = 'account-b';
      await clear;
      await service.resumeAndSync();
      Map snapshot() => jsonDecode(
        native.named('publishDisplaySnapshot').last.arguments as String,
      ) as Map;
      expect(snapshot()['selectedDog'], isNull);
      final bProfiles = Profiles()..current = view(name: '다른계정');
      final b = FirstMeetingController(
        storage: MemoryStorage(),
        profileRepository: bProfiles,
      );
      final stopB = service.observeProfile('account-b', b);
      addTearDown(() {
        stopB();
        b.dispose();
      });
      await b.initialize();
      await service.requestDailySteps();
      expect((snapshot()['selectedDog'] as Map)['dogId'], 'owner:account-b');
      profiles.reading!.complete(view(name: '늦은응답', revision: 9));
      await restoring;
      await service.requestDailySteps();
      expect((snapshot()['selectedDog'] as Map)['displayName'], '다른계정');
      await service.clearContext();
      server.accountId = 'account-a';
      await service.resumeAndSync();
      await old.restore();
      await service.requestDailySteps();
      expect(snapshot()['selectedDog'], isNull);
      await service.logoutSession(() async {
        server.accountId = null;
        return const SessionLogoutOutcome(
          serverRevoked: true,
          localCleared: true,
        );
      });
      expect(service.isActive, isFalse);
      expect(native.calls.last.method, 'clearContext');
    },
  );

  test('every approved breed resolves to its own shipped Watch sprite', () {
    expect(FirstMeetingCatalog.breeds, hasLength(30));
    for (final breed in FirstMeetingCatalog.breeds) {
      expect(watchDogAssetKey(breed.id), 'dog.preview.${breed.id}');
      final asset =
          'SelectedDog${breed.id.split('-').map((part) => '${part[0].toUpperCase()}${part.substring(1)}').join()}';
      final directory = 'ios/Watch/Assets.xcassets/$asset.imageset';
      final contents = jsonDecode(
        File('$directory/Contents.json').readAsStringSync(),
      ) as Map;
      expect((contents['images'] as List).single['filename'], 'dog.png');
      expect(
        File('$directory/dog.png').readAsBytesSync(),
        File(breed.spritePath).readAsBytesSync(),
      );
    }
    expect(watchDogAssetKey('unknown'), 'dog.unsupported');
    expect(watchDogAssetKey(''), 'dog.unsupported');
    expect(watchDogAssetKey('../pug'), 'dog.unsupported');
  });

  test('explicit resume maps original IDs and ordered points then validates receipt', () async {
    await service.resumeAndSync();
    expect(server.validations, 1);
    expect(native.calls.map((call) => call.method), [
      'activateContext',
      'publishDisplaySnapshot',
      'listPendingRecords',
      'acknowledgeServerReceipt',
    ]);
    expect(native.named('activateContext').single.arguments, {
      'accountId': 'account-a',
    });
    final display = jsonDecode(
      native.named('publishDisplaySnapshot').single.arguments as String,
    ) as Map;
    expect(display['revision'], 8);
    expect(display['selectedDog'], isNull);
    expect(display['dailySteps'], isNull);
    expect(native.named('requestDailySteps'), isEmpty);
    final input = server.inputs.single;
    expect(input.clientRecordId.toString(), _id);
    expect(input.source, 'watch');
    expect(input.schemaVersion, 1);
    expect(input.startedAt, DateTime.utc(2026, 10, 9, 1));
    expect(input.routePoints.map((p) => p.latitude), [37.5, 37.6]);
    expect(input.routePoints.map((p) => p.horizontalAccuracyMeters), [5, 6]);
    expect(native.named('acknowledgeServerReceipt').single.arguments, {
      'contextId': 'context-a',
      'clientRecordId': _id,
      'recordId': _serverId,
      'persistedAt': '2026-10-09T02:00:00.000Z',
      'schemaVersion': 1,
    });
    expect(service.isActive, isTrue);
  });

  test(
    'unauthenticated and rejected resume never activate or report success',
    () async {
      server.accountId = null;
      await expectLater(service.resumeAndSync(), throwsStateError);
      expect(server.validations, 0);
      server.accountId = 'account-a';
      server.valid = false;
      await expectLater(service.resumeAndSync(), throwsStateError);
      expect(native.named('activateContext'), isEmpty);
      expect(native.named('acknowledgeServerReceipt'), isEmpty);
    },
  );

  test('validation network failure clears native boundary', () async {
    server.validate = () async => throw Exception('private token');
    await expectLater(service.resumeAndSync(), throwsException);
    expect(native.named('clearContext'), hasLength(1));
    expect(service.lastError, 'syncFailed');
    expect(native.named('activateContext'), isEmpty);
  });

  for (final receipt in [
    _receipt().copyWith(clientRecordId: UuidValue.fromString(_serverId)),
    _receipt().copyWith(schemaVersion: 2),
    _receipt().copyWith(persistedAt: DateTime(2026, 10, 9)),
    _receipt().copyWith(
      recordId: UuidValue.fromString('00000000-0000-0000-0000-000000000000'),
    ),
  ]) {
    test('invalid receipt ${receipt.toJson()} never acknowledges', () async {
      server.save = () async => receipt;
      await expectLater(service.resumeAndSync(), throwsFormatException);
      expect(native.named('acknowledgeServerReceipt'), isEmpty);
      expect(native.records, hasLength(1));
    });
  }

  test('foreign context and malformed inbox never reach server', () async {
    native.records = [jsonEncode(_record('other-context'))];
    await expectLater(service.resumeAndSync(), throwsFormatException);
    native.records = ['{"schemaVersion":2}'];
    await expectLater(service.resumeAndSync(), throwsFormatException);
    expect(server.inputs, isEmpty);
  });

  test(
    'failed native ACK retains record and explicit retry uses same ID',
    () async {
      native.failMethod = 'acknowledgeServerReceipt';
      await expectLater(
        service.resumeAndSync(),
        throwsA(isA<PlatformException>()),
      );
      expect(native.records, hasLength(1));
      native.failMethod = null;
      await service.resumeAndSync();
      expect(server.inputs.map((input) => input.clientRecordId.toString()), [
        _id,
        _id,
      ]);
      expect(native.records, isEmpty);
    },
  );

  test(
    'in-flight clear invalidates immediately and queues before next account',
    () async {
      final started = Completer<void>();
      final response = Completer<RecordReceipt>();
      server.save = () {
        started.complete();
        return response.future;
      };
      final sync = service.resumeAndSync();
      final syncError = expectLater(sync, throwsStateError);
      await started.future;
      final clear = service.clearContext();
      expect(service.isActive, isFalse);
      expect(native.named('clearContext'), isEmpty);
      server.accountId = 'account-b';
      response.complete(_receipt());
      await syncError;
      await clear;
      expect(native.named('acknowledgeServerReceipt'), isEmpty);
      expect(server.accounts, ['account-a']);
      expect(native.named('publishDisplaySnapshot'), hasLength(1));
      native.activation = {
        'contextId': 'context-b',
        'boundaryRevision': 5,
        'latestDisplayRevision': 0,
      };
      native.records = [];
      await service.resumeAndSync();
      expect(native.named('activateContext').last.arguments, {
        'accountId': 'account-b',
      });
    },
  );

  test('logout during validation cannot activate stale account', () async {
    final started = Completer<void>();
    final validated = Completer<bool>();
    server.validate = () {
      started.complete();
      return validated.future;
    };
    final syncError = expectLater(service.resumeAndSync(), throwsStateError);
    await started.future;
    final logout = service.logoutSession(() async {
      server.accountId = null;
      return const SessionLogoutOutcome(
        serverRevoked: false,
        localCleared: true,
      );
    });
    validated.complete(true);
    await syncError;
    expect((await logout).localCleared, isTrue);
    expect(native.named('activateContext'), isEmpty);
  });

  test(
    'concurrent explicit sync calls serialize without duplicate upload',
    () async {
      final started = Completer<void>();
      final response = Completer<RecordReceipt>();
      server.save = () {
        started.complete();
        return response.future;
      };
      final first = service.resumeAndSync();
      await started.future;
      final second = service.resumeAndSync();
      expect(server.validations, 1);
      response.complete(_receipt());
      await Future.wait([first, second]);
      expect(server.inputs, hasLength(1));
    },
  );

  test(
    'inbox event is only a hint and does not validate a restored account',
    () async {
      await service.initialize();
      Future<void> event() async {
        final sent = Completer<void>();
        binding.defaultBinaryMessenger.handlePlatformMessage(
          _events.name,
          const StandardMethodCodec().encodeSuccessEnvelope('inboxChanged'),
          (_) => sent.complete(),
        );
        await sent.future.timeout(const Duration(seconds: 2));
      }

      await event();
      expect(server.inputs, isEmpty);
      await service.resumeAndSync();
      native.records = [jsonEncode(_record())];
      native.listed = Completer<void>();
      await event();
      await native.listed!.future.timeout(const Duration(seconds: 2));
      await service.requestDailySteps();
      expect(server.inputs, hasLength(2));
      expect(server.validations, 1);
    },
  );

  for (final status in DailyStepsStatus.values) {
    test(
      'explicit daily steps reports ${status.name} and publishes nullable data',
      () async {
        await service.resumeAndSync();
        final steps = status == DailyStepsStatus.available
            ? {
                'date': '2026-10-09',
                'timeZone': 'Asia/Seoul',
                'count': 0,
                'observedAt': '2026-10-09T01:02:03Z',
              }
            : null;
        native.steps = {'status': status.name, 'dailySteps': steps};
        final result = await service.requestDailySteps();
        expect(result.status, status);
        expect(result.dailySteps, steps);
        final display = jsonDecode(
          native.named('publishDisplaySnapshot').last.arguments as String,
        ) as Map;
        expect(display['dailySteps'], steps);
        expect(display['selectedDog'], isNull);
        expect(display['revision'], 9);
        expect(server.validations, 1);
      },
    );
  }

  test('invalid native activation watermark and steps fail closed', () async {
    native.activation = {'contextId': 'context-a', 'boundaryRevision': 1};
    await expectLater(service.resumeAndSync(), throwsFormatException);
    expect(native.named('publishDisplaySnapshot'), isEmpty);
    native.steps = {
      'status': 'available',
      'dailySteps': {'count': -1},
    };
    await expectLater(service.requestDailySteps(), throwsFormatException);
  });

  test(
    'real auth adapter saves then activates without callback deadlock',
    () async {
      final storage = _Storage();
      final client = Client('http://localhost:1/')
        ..authSessionManager = FlutterAuthSessionManager(storage: storage);
      addTearDown(client.close);
      await service.dispose();
      service = WatchSyncService(
        bridge: WatchBridge(),
        server: ServerpodWatchSyncServer(client),
      );
      client.auth.authInfoListenable.addListener(service.authenticationChanged);
      final adapter = ServerpodAuthSession(client.auth, watchSync: service);
      await adapter.save(_auth('1')).timeout(const Duration(seconds: 2));
      expect(storage.value?.authUserId, _auth('1').authUserId);
      expect(native.named('activateContext').single.arguments, {
        'accountId': _auth('1').authUserId.toString(),
      });
      expect(service.isActive, isTrue);
      storage.fail = true;
      final logout = await adapter.logout().timeout(const Duration(seconds: 2));
      expect(logout.localCleared, isFalse);
      expect(native.named('clearContext'), hasLength(2));
      expect(service.isActive, isFalse);
    },
  );

  test('native failure cannot turn successful real login into fake storage failure', () async {
    native.failMethod = 'activateContext';
    await service.saveAuthenticatedSession(() async {});
    expect(service.lastError, 'nativeError');
    expect(service.isActive, isFalse);
    expect(native.named('clearContext'), hasLength(2));
  });

  test('generated upload sends captured account header and real DTO to HTTP server', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      final requestArrived = Completer<HttpRequest>();
      final handled = Completer<void>();
      http.listen((request) {
        requestArrived.complete(request);
      });
      final client = Client('http://127.0.0.1:${http.port}/')
        ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
      addTearDown(client.close);
      await client.auth.updateSignedInUser(_auth('1'));
      final adapter = ServerpodWatchSyncServer(client);
      final upload = adapter.saveConfirmed(
        _auth('1').authUserId.toString(),
        watchRecordInput(watch.GpsRecord.fromJson(_record())),
      );
      final request = await requestArrived.future.timeout(
        const Duration(seconds: 2),
      );
      await client.auth.updateSignedInUser(_auth('2'));
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer token-1',
      );
      expect(request.uri.path, '/records/saveConfirmed');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(jsonEncode(body), contains(_id));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_receipt().toJson()));
      await request.response.close();
      handled.complete();
      final receipt = await upload;
      expect(receipt.clientRecordId.toString(), _id);
      await handled.future;
      await expectLater(
        adapter.saveConfirmed(
          _auth('1').authUserId.toString(),
          watchRecordInput(watch.GpsRecord.fromJson(_record())),
        ),
        throwsStateError,
      );
    }, _RealHttpOverrides());
  });

  test('stale real validation cannot mutate another account session', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      final arrived = Completer<HttpRequest>();
      http.listen(arrived.complete);
      final client = Client('http://127.0.0.1:${http.port}/')
        ..authSessionManager = FlutterAuthSessionManager(storage: _Storage());
      addTearDown(client.close);
      await client.auth.updateSignedInUser(_auth('1'));
      final validation = ServerpodWatchSyncServer(client)
          .validateAuthentication();
      final request = await arrived.future.timeout(const Duration(seconds: 2));
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer token-1',
      );
      expect(request.uri.path, contains('isSignedIn'));
      await client.auth.updateSignedInUser(_auth('2'));
      request.response.headers.contentType = ContentType.json;
      request.response.write('false');
      await request.response.close();
      expect(await validation, isFalse);
      expect(client.auth.authInfo?.authUserId, _auth('2').authUserId);
    }, _RealHttpOverrides());
  });
}
