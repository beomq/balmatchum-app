import 'dart:async';
import 'dart:io';

import 'package:balmatchum_app/features/auth/auth_adapters.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/auth/social_auth_adapters.dart';
import 'package:balmatchum_app/features/auth/social_auth_service.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_app/features/watch_sync/watch_sync_server.dart';
import 'package:balmatchum_app/features/watch_sync/watch_sync_service.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final _auth = AuthSuccess(
  authStrategy: 'session',
  token: 'test-only-token',
  authUserId: UuidValue.fromString('00000000-0000-4000-8000-000000000001'),
  scopeNames: {},
);

class _Sdk implements SocialLoginSdk {
  final calls = <SignInProvider>[];
  Exception? error;
  Future<SocialCredential>? pending;

  @override
  Future<SocialCredential> authenticate(SignInProvider provider) async {
    calls.add(provider);
    if (error != null) throw error!;
    return pending ??
        const SocialCredential(idToken: 'identity', authorizationCode: 'code');
  }
}

class _Server implements SocialLoginServer {
  final calls = <SignInProvider>[];
  Exception? error;
  bool configured = true;

  @override
  Future<bool> isConfigured(SignInProvider provider) async => configured;

  @override
  Future<AuthSuccess> login(
    SignInProvider provider,
    SocialCredential credential,
  ) async {
    calls.add(provider);
    if (error != null) throw error!;
    return _auth;
  }
}

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  bool fail = false;
  final calls = <String>[];
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? auth) async {
    calls.add('persist');
    if (fail) throw Exception('storage');
    value = auth;
  }
}

class _WatchServer implements WatchSyncServer {
  _WatchServer(this.manager);
  final FlutterAuthSessionManager manager;
  @override
  String? get accountId => manager.authInfo?.authUserId.toString();
  @override
  Future<bool> validateAuthentication() async => manager.isAuthenticated;
  @override
  Future<RecordReceipt> saveConfirmed(String accountId, GpsRecordInput input) =>
      throw StateError('No records expected');
}

class _Kakao implements SignInStarter {
  int calls = 0;
  @override
  Future<SignInOutcome> start(SignInProvider provider) async {
    calls++;
    expect(provider, SignInProvider.kakao);
    return SignInOutcome.cancelled;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.beomq.balmatchum/watch');
  late _Sdk sdk;
  late _Server server;
  late _Storage storage;
  late FlutterAuthSessionManager manager;
  late WatchSyncService watch;
  late SocialAuthService service;
  late _Kakao kakao;
  late List<String> native;
  setUp(() {
    sdk = _Sdk();
    server = _Server();
    storage = _Storage();
    manager = FlutterAuthSessionManager(storage: storage);
    watch = WatchSyncService(
      bridge: WatchBridge(),
      server: _WatchServer(manager),
    );
    kakao = _Kakao();
    service = SocialAuthService(
      isConfigured: (_) => true,
      sdk: sdk,
      server: server,
      session: ServerpodAuthSession(manager, watchSync: watch),
      kakao: kakao,
    );
    native = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      native.add(call.method);
      if (call.method == 'clearContext') {
        expect(manager.isAuthenticated, isFalse);
        expect(storage.calls, isEmpty);
      }
      if (call.method == 'activateContext') {
        expect(storage.value, same(_auth));
        expect(manager.isAuthenticated, isTrue);
        return {
          'contextId': 'explicit-login',
          'boundaryRevision': 1,
          'latestDisplayRevision': 0,
        };
      }
      if (call.method == 'listPendingRecords') return <String>[];
      return null;
    });
  });
  tearDown(() async {
    await watch.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final provider in [SignInProvider.google, SignInProvider.apple]) {
    test(
      '${provider.name} success uses real session adapter Watch boundary',
      () async {
        expect(native, isEmpty);
        expect(await service.start(provider), SignInOutcome.signedIn);
        expect(sdk.calls, [provider]);
        expect(server.calls, [provider]);
        expect(native.first, 'clearContext');
        expect(native, contains('activateContext'));
        expect(watch.isActive, isTrue);
        expect(storage.calls, ['persist']);
      },
    );

    test(
      '${provider.name} storage failure never activates Watch or auth state',
      () async {
        storage.fail = true;
        expect(
          await service.start(provider),
          const SignInOutcome.failed('sessionStorageError'),
        );
        expect(native, ['clearContext']);
        expect(manager.isAuthenticated, isFalse);
        expect(watch.isActive, isFalse);
      },
    );

    test(
      '${provider.name} cancellation never calls server or storage',
      () async {
        sdk.error = const SocialLoginFailure('cancelled');
        expect(await service.start(provider), SignInOutcome.cancelled);
        expect(server.calls, isEmpty);
        expect(storage.calls, isEmpty);
        expect(native, isEmpty);
      },
    );

    test(
      '${provider.name} server rejection is distinct from network failure',
      () async {
        server.error = Exception('server rejected token');
        expect(
          await service.start(provider),
          const SignInOutcome.failed('serverError'),
        );
        server.error = const SocketException('offline');
        expect(
          await service.start(provider),
          const SignInOutcome.failed('networkError'),
        );
        expect(storage.calls, isEmpty);
        expect(native, isEmpty);
      },
    );
  }

  test('missing configuration and Naver never invoke an SDK', () async {
    service = SocialAuthService(
      isConfigured: (_) => false,
      sdk: sdk,
      server: server,
      session: ServerpodAuthSession(manager),
      kakao: kakao,
    );
    for (final provider in [
      SignInProvider.google,
      SignInProvider.apple,
      SignInProvider.naver,
    ]) {
      expect(
        await service.start(provider),
        const SignInOutcome.failed('configurationMissing'),
      );
    }
    expect(sdk.calls, isEmpty);
    expect(server.calls, isEmpty);
    expect(await service.start(SignInProvider.kakao), SignInOutcome.cancelled);
    expect(kakao.calls, 1);
  });

  test('duplicate presses do not acquire another credential', () async {
    final credentials = Completer<SocialCredential>();
    sdk.pending = credentials.future;
    final first = service.start(SignInProvider.google);
    expect(
      await service.start(SignInProvider.apple),
      const SignInOutcome.failed('signInInProgress'),
    );
    credentials.complete(const SocialCredential(idToken: 'identity'));
    expect(await first, SignInOutcome.signedIn);
    expect(sdk.calls, [SignInProvider.google]);
  });

  test('missing server credentials never invokes the provider SDK', () async {
    server.configured = false;
    expect(
      await service.start(SignInProvider.google),
      const SignInOutcome.failed('configurationMissing'),
    );
    expect(sdk.calls, isEmpty);
    expect(server.calls, isEmpty);
    expect(storage.calls, isEmpty);
  });

  test(
    'server config loss after preflight remains an unconfigured result',
    () async {
      server.error = LoginException(code: 'configurationMissing');
      expect(
        await service.start(SignInProvider.google),
        const SignInOutcome.failed('configurationMissing'),
      );
      expect(storage.calls, isEmpty);
      expect(native, isEmpty);
    },
  );

  test(
    'Google awaits the same initialization future before authenticate',
    () async {
      final initialized = Completer<void>();
      final entered = Completer<void>();
      var initializations = 0;
      var authentications = 0;
      final nativeSdk = NativeSocialLoginSdk(
        configuration: const SocialAuthConfiguration(
          serverUrl: 'https://api.test/',
          platform: TargetPlatform.android,
          googleServerClientId: 'test-client',
        ),
        initializeGoogle: () {
          initializations++;
          entered.complete();
          return initialized.future;
        },
        authenticateGoogle: () async {
          authentications++;
          return 'identity';
        },
      );
      final first = nativeSdk.authenticate(SignInProvider.google);
      await entered.future;
      final second = nativeSdk.authenticate(SignInProvider.google);
      expect(initializations, 1);
      expect(authentications, 0);
      initialized.complete();
      await Future.wait([first, second]);
      expect(authentications, 2);
    },
  );

  test('missing iOS callback prevents Google initialization', () async {
    final nativeSdk = NativeSocialLoginSdk(
      configuration: const SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: TargetPlatform.iOS,
        googleClientId: 'ios-client',
        googleServerClientId: 'server-client',
      ),
      googleCallbackConfigured: () async => false,
      initializeGoogle: () async => fail('SDK must not initialize'),
    );
    await expectLater(
      nativeSdk.authenticate(SignInProvider.google),
      throwsA(
        isA<SocialLoginFailure>().having(
          (e) => e.code,
          'code',
          'configurationMissing',
        ),
      ),
    );
  });

  test('native cancellation codes normalize without logging tokens', () async {
    final nativeSdk = NativeSocialLoginSdk(
      configuration: const SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: TargetPlatform.android,
        googleServerClientId: 'test-client',
        appleEnabled: true,
        appleServiceIdentifier: 'test-service',
        appleRedirectUri: 'https://api.test/callback',
      ),
      initializeGoogle: () async {},
      authenticateGoogle: () async => throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      ),
      authenticateApple: () async =>
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'cancel',
          ),
    );
    for (final provider in [SignInProvider.google, SignInProvider.apple]) {
      await expectLater(
        nativeSdk.authenticate(provider),
        throwsA(
          isA<SocialLoginFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
    }
  });

  test('platform and configuration matrix fails closed', () {
    for (final platform in TargetPlatform.values) {
      final config = SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: platform,
      );
      expect(config.isConfigured(SignInProvider.google), isFalse);
      expect(config.isConfigured(SignInProvider.apple), isFalse);
    }
    const appleAndroid = SocialAuthConfiguration(
      serverUrl: 'https://api.test/',
      platform: TargetPlatform.android,
      appleEnabled: true,
      appleServiceIdentifier: 'service',
      appleRedirectUri: 'http://api.test/callback',
    );
    expect(appleAndroid.isConfigured(SignInProvider.apple), isFalse);
    const web = SocialAuthConfiguration(
      serverUrl: 'https://api.test/',
      platform: TargetPlatform.iOS,
      isWeb: true,
      googleClientId: 'ios',
      googleServerClientId: 'server',
      appleEnabled: true,
    );
    expect(web.isConfigured(SignInProvider.google), isFalse);
    expect(web.isConfigured(SignInProvider.apple), isFalse);
  });
}
