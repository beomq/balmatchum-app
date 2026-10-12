import 'dart:async';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'sign_in_starter.dart';

abstract interface class KakaoLoginServer {
  Future<LoginChallenge> beginLogin();
  Future<AuthSuccess> loginKakao(LoginChallenge challenge, String idToken);
}

abstract interface class KakaoLoginSdk {
  Future<String?> login(String nonce);
  Future<void> logout();
}

class KakaoLoginCancelled implements Exception {
  const KakaoLoginCancelled();
}

abstract interface class AuthSession {
  Future<void> save(AuthSuccess auth);
  Future<SessionLogoutOutcome> logout();
}

final class SessionLogoutOutcome {
  const SessionLogoutOutcome({
    required this.serverRevoked,
    required this.localCleared,
  });

  // null means local cleanup threw before the manager returned server status.
  final bool? serverRevoked;
  final bool localCleared;
}

final class LogoutOutcome {
  const LogoutOutcome({required this.session, required this.sdkLoggedOut});

  final SessionLogoutOutcome session;
  final bool sdkLoggedOut;
}

class KakaoAuthService implements SignInStarter {
  KakaoAuthService({
    required this.server,
    required this.sdk,
    required this.session,
  });

  final KakaoLoginServer server;
  final KakaoLoginSdk sdk;
  final AuthSession session;

  @override
  Future<SignInOutcome> start(SignInProvider provider) async {
    if (provider != SignInProvider.kakao) return SignInOutcome.notConnected;
    late AuthSuccess auth;
    try {
      final challenge = await server.beginLogin();
      final idToken = await sdk.login(challenge.nonce);
      if (idToken == null || idToken.isEmpty) {
        return const SignInOutcome.failed('missingIdToken');
      }
      auth = await server.loginKakao(challenge, idToken);
    } on KakaoLoginCancelled {
      return SignInOutcome.cancelled;
    } on LoginException catch (error) {
      return SignInOutcome.failed(error.code);
    } on ServerpodClientNetworkException {
      return const SignInOutcome.failed('networkError');
    } on SocketException {
      return const SignInOutcome.failed('networkError');
    } on TimeoutException {
      return const SignInOutcome.failed('networkError');
    } on ServerpodClientException {
      return const SignInOutcome.failed('serverError');
    } on Exception {
      return const SignInOutcome.failed('sdkError');
    }
    try {
      await session.save(auth);
      return SignInOutcome.signedIn;
    } on Exception {
      return const SignInOutcome.failed('sessionStorageError');
    }
  }

  Future<LogoutOutcome> logout() async {
    final result = await session.logout();
    var sdkLoggedOut = false;
    try {
      await sdk.logout();
      sdkLoggedOut = true;
    } on Exception {
      // Kakao logout is independent of the application's server session.
    }
    return LogoutOutcome(session: result, sdkLoggedOut: sdkLoggedOut);
  }
}
