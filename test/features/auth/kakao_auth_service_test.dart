import 'dart:async';

import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

final _challenge = LoginChallenge(
  attemptId: UuidValue.fromString('00000000-0000-0000-0000-000000000001'),
  nonce: 'server-nonce',
  expiresAt: DateTime.utc(2030),
);
final _auth = AuthSuccess(
  authStrategy: 'session',
  token: 'test-session',
  authUserId: UuidValue.fromString('00000000-0000-0000-0000-000000000002'),
  scopeNames: {},
);

class _Server implements KakaoLoginServer {
  final events = <String>[];
  Exception? beginError;
  Exception? loginError;
  LoginChallenge? receivedChallenge;
  String? receivedToken;

  @override
  Future<LoginChallenge> beginLogin() async {
    events.add('begin');
    if (beginError != null) throw beginError!;
    return _challenge;
  }

  @override
  Future<AuthSuccess> loginKakao(
    LoginChallenge challenge,
    String idToken,
  ) async {
    events.add('login');
    receivedChallenge = challenge;
    receivedToken = idToken;
    if (loginError != null) throw loginError!;
    return _auth;
  }
}

class _Sdk implements KakaoLoginSdk {
  String? token = 'oidc-token';
  String? nonce;
  Exception? error;
  bool logoutFails = false;

  @override
  Future<String?> login(String nonce) async {
    this.nonce = nonce;
    if (error != null) throw error!;
    return token;
  }

  @override
  Future<void> logout() async {
    if (logoutFails) throw Exception('sdk logout');
  }
}

class _Session implements AuthSession {
  AuthSuccess? saved;
  bool saveFails = false;

  @override
  Future<void> save(AuthSuccess auth) async {
    if (saveFails) throw Exception('storage');
    saved = auth;
  }

  @override
  Future<SessionLogoutOutcome> logout() async =>
      const SessionLogoutOutcome(serverRevoked: false, localCleared: true);
}

void main() {
  late _Server server;
  late _Sdk sdk;
  late _Session session;
  late KakaoAuthService service;
  setUp(() {
    server = _Server();
    sdk = _Sdk();
    session = _Session();
    service = KakaoAuthService(server: server, sdk: sdk, session: session);
  });

  test(
    'passes challenge nonce and OIDC token and stores server success',
    () async {
      expect(await service.start(SignInProvider.kakao), SignInOutcome.signedIn);
      expect(server.events, ['begin', 'login']);
      expect(sdk.nonce, _challenge.nonce);
      expect(server.receivedChallenge, same(_challenge));
      expect(server.receivedToken, 'oidc-token');
      expect(session.saved, same(_auth));
    },
  );

  test(
    'other providers remain disconnected without invoking dependencies',
    () async {
      for (final provider in [
        SignInProvider.google,
        SignInProvider.apple,
        SignInProvider.naver,
      ]) {
        expect(await service.start(provider), SignInOutcome.notConnected);
      }
      expect(server.events, isEmpty);
      expect(sdk.nonce, isNull);
    },
  );

  test('SDK cancellation does not exchange or save a token', () async {
    sdk.error = const KakaoLoginCancelled();
    expect(await service.start(SignInProvider.kakao), SignInOutcome.cancelled);
    expect(server.events, ['begin']);
    expect(session.saved, isNull);
  });

  for (final token in [null, '']) {
    test('missing OIDC token $token is not sent to server', () async {
      sdk.token = token;
      expect(
        await service.start(SignInProvider.kakao),
        const SignInOutcome.failed('missingIdToken'),
      );
      expect(server.events, ['begin']);
      expect(session.saved, isNull);
    });
  }

  for (final code in [
    'configurationMissing',
    'unsupportedProvider',
    'invalidAttempt',
    'invalidToken',
  ]) {
    test(
      'preserves server error $code without saving authentication',
      () async {
        server.loginError = LoginException(code: code);
        expect(
          await service.start(SignInProvider.kakao),
          SignInOutcome.failed(code),
        );
        expect(session.saved, isNull);
      },
    );
  }

  test('begin failure does not invoke SDK', () async {
    server.beginError = LoginException(code: 'configurationMissing');
    expect(
      await service.start(SignInProvider.kakao),
      const SignInOutcome.failed('configurationMissing'),
    );
    expect(sdk.nonce, isNull);
  });

  test('network timeout differs from SDK failure', () async {
    server.beginError = TimeoutException('test');
    expect(
      await service.start(SignInProvider.kakao),
      const SignInOutcome.failed('networkError'),
    );
    server.beginError = null;
    sdk.error = Exception('sdk');
    expect(
      await service.start(SignInProvider.kakao),
      const SignInOutcome.failed('sdkError'),
    );
  });

  test('failed persistence never reports signed in', () async {
    session.saveFails = true;
    expect(
      await service.start(SignInProvider.kakao),
      const SignInOutcome.failed('sessionStorageError'),
    );
    expect(session.saved, isNull);
  });

  test('logout preserves independent server local and SDK results', () async {
    sdk.logoutFails = true;
    final result = await service.logout();
    expect(result.session.serverRevoked, isFalse);
    expect(result.session.localCleared, isTrue);
    expect(result.sdkLoggedOut, isFalse);
  });
}
