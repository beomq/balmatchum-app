import 'dart:async';
import 'dart:convert';

import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/auth/naver_auth_service.dart';
import 'package:balmatchum_app/features/auth/naver_login_browser.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

class _Session implements AuthSession {
  AuthSuccess? saved;
  bool fail = false;

  @override
  Future<void> save(AuthSuccess auth) async {
    if (fail) throw Exception('storage failure');
    saved = auth;
  }

  @override
  Future<SessionLogoutOutcome> logout() => throw UnimplementedError();
}

void main() {
  final now = DateTime.utc(2026, 10, 21);
  final redirect = Uri.parse('com.beomq.balmatchum.dev://naver/callback');
  final id = UuidValue.fromString('00000000-0000-4000-8000-000000000001');
  final auth = AuthSuccess(
    authStrategy: 'session',
    token: 'test-only-token',
    authUserId: id,
    scopeNames: {},
  );
  late _Session session;
  late NaverAuthService service;
  late String challenge;
  late bool configured;
  late DateTime expires;
  late Object? authentication;
  late bool alive;
  late int completes;
  Completer<String>? browserPending;
  Completer<AuthSuccess>? serverPending;
  late Completer<void> browserOpened;
  late Completer<void> serverEntered;

  setUp(() {
    session = _Session();
    configured = true;
    expires = now.add(const Duration(minutes: 5));
    authentication = null;
    alive = true;
    completes = 0;
    browserPending = null;
    serverPending = null;
    browserOpened = Completer<void>();
    serverEntered = Completer<void>();
    service = NaverAuthService(
      isConfigured: () async => configured,
      beginLogin: (value) async {
        challenge = value;
        return NaverLoginChallenge(
          attemptId: id,
          authorizationUrl: Uri.https('nid.naver.com', '/oauth2/authorize', {
            'response_type': 'code',
            'redirect_uri': redirect.toString(),
            'state': 'state',
            'code_challenge': value,
            'code_challenge_method': 'S256',
          }).toString(),
          redirectUri: redirect.toString(),
          state: 'state',
          expiresAt: expires,
        );
      },
      completeLogin: (attempt, code, verifier) async {
        completes++;
        serverEntered.complete();
        expect(attempt.attemptId, id);
        expect(code, 'code');
        expect(
          base64Url
              .encode(sha256.convert(ascii.encode(verifier)).bytes)
              .replaceAll('=', ''),
          challenge,
        );
        return serverPending?.future ?? auth;
      },
      redirectUri: redirect,
      browser: NaverLoginBrowser(
        authenticate: (url, scheme) async {
          browserOpened.complete();
          return browserPending?.future ?? '$redirect?state=state&code=code';
        },
      ),
      session: session,
      authentication: () => authentication,
      isAlive: () => alive,
      now: () => now,
    );
  });

  test('verified login saves through the existing session boundary', () async {
    expect(await service.start(SignInProvider.naver), SignInOutcome.signedIn);
    expect(session.saved, same(auth));
    expect(completes, 1);
  });

  test('unconfigured server never opens browser', () async {
    configured = false;
    expect(
      await service.start(SignInProvider.naver),
      const SignInOutcome.failed('configurationMissing'),
    );
    expect(browserOpened.isCompleted, isFalse);
    expect(session.saved, isNull);
  });

  test('expired attempt never opens browser', () async {
    expires = now;
    expect(
      await service.start(SignInProvider.naver),
      const SignInOutcome.failed('invalidAttempt'),
    );
    expect(browserOpened.isCompleted, isFalse);
  });

  test('concurrent login cannot replace the pending verifier', () async {
    browserPending = Completer<String>();
    final first = service.start(SignInProvider.naver);
    await browserOpened.future.timeout(const Duration(seconds: 5));
    expect(
      await service.start(SignInProvider.naver),
      const SignInOutcome.failed('signInInProgress'),
    );
    browserPending!.complete('$redirect?state=state&code=code');
    expect(await first, SignInOutcome.signedIn);
    expect(completes, 1);
  });

  test('account change during browser discards authorization code', () async {
    browserPending = Completer<String>();
    final result = service.start(SignInProvider.naver);
    await browserOpened.future.timeout(const Duration(seconds: 5));
    authentication = Object();
    browserPending!.complete('$redirect?state=state&code=code');
    expect(await result, SignInOutcome.cancelled);
    expect(completes, 0);
    expect(session.saved, isNull);
  });

  test('disposed provider discards pending browser result', () async {
    browserPending = Completer<String>();
    final result = service.start(SignInProvider.naver);
    await browserOpened.future.timeout(const Duration(seconds: 5));
    alive = false;
    browserPending!.complete('$redirect?state=state&code=code');
    expect(await result, SignInOutcome.cancelled);
    expect(session.saved, isNull);
  });

  test('session storage failure is not reported as login success', () async {
    session.fail = true;
    expect(
      await service.start(SignInProvider.naver),
      const SignInOutcome.failed('sessionStorageError'),
    );
    expect(session.saved, isNull);
  });

  test(
    'account change during server verification does not save session',
    () async {
      serverPending = Completer<AuthSuccess>();
      final result = service.start(SignInProvider.naver);
      await serverEntered.future.timeout(const Duration(seconds: 5));
      authentication = Object();
      serverPending!.complete(auth);
      expect(await result, SignInOutcome.cancelled);
      expect(session.saved, isNull);
    },
  );
}
