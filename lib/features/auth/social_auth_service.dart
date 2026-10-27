import 'dart:async';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'kakao_auth_service.dart';
import 'sign_in_starter.dart';

final class SocialCredential {
  const SocialCredential({required this.idToken, this.authorizationCode});

  final String idToken;
  final String? authorizationCode;
}

final class SocialLoginFailure implements Exception {
  const SocialLoginFailure(this.code);

  final String code;
}

abstract interface class SocialLoginSdk {
  Future<SocialCredential> authenticate(SignInProvider provider);
}

abstract interface class SocialLoginServer {
  Future<bool> isConfigured(SignInProvider provider);
  Future<AuthSuccess> login(
    SignInProvider provider,
    SocialCredential credential,
  );
}

/// Only an explicit button press reaches this service. Credential acquisition,
/// server verification and local persistence are separate failure boundaries.
class SocialAuthService implements SignInStarter {
  SocialAuthService({
    required this.isConfigured,
    required this.sdk,
    required this.server,
    required this.session,
    this.kakao,
    this.naver,
    this.onGoogleSignedIn,
  });

  final bool Function(SignInProvider) isConfigured;
  final SocialLoginSdk sdk;
  final SocialLoginServer server;
  final AuthSession session;
  final SignInStarter? kakao;
  final SignInStarter? naver;
  final Future<void> Function(UuidValue authUserId)? onGoogleSignedIn;
  bool _starting = false;

  @override
  Future<SignInOutcome> start(SignInProvider provider) async {
    if (provider == SignInProvider.kakao) {
      return kakao?.start(provider) ?? SignInOutcome.notConnected;
    }
    if (provider == SignInProvider.naver) {
      if (_starting) return const SignInOutcome.failed('signInInProgress');
      _starting = true;
      try {
        return await naver?.start(provider) ??
            const SignInOutcome.failed('configurationMissing');
      } finally {
        _starting = false;
      }
    }
    if (!isConfigured(provider)) {
      return const SignInOutcome.failed('configurationMissing');
    }
    if (_starting) return const SignInOutcome.failed('signInInProgress');
    _starting = true;
    try {
      try {
        if (!await server.isConfigured(provider)) {
          return const SignInOutcome.failed('configurationMissing');
        }
      } on ServerpodClientNetworkException {
        return const SignInOutcome.failed('networkError');
      } on SocketException {
        return const SignInOutcome.failed('networkError');
      } on TimeoutException {
        return const SignInOutcome.failed('networkError');
      } on Exception {
        return const SignInOutcome.failed('serverError');
      }
      late SocialCredential credential;
      try {
        credential = await sdk.authenticate(provider);
        if (credential.idToken.isEmpty ||
            (provider == SignInProvider.apple &&
                (credential.authorizationCode?.isEmpty ?? true))) {
          return const SignInOutcome.failed('invalidToken');
        }
      } on SocialLoginFailure catch (error) {
        return error.code == 'cancelled'
            ? SignInOutcome.cancelled
            : SignInOutcome.failed(error.code);
      } on SocketException {
        return const SignInOutcome.failed('networkError');
      } on TimeoutException {
        return const SignInOutcome.failed('networkError');
      } on Exception {
        return const SignInOutcome.failed('sdkError');
      }

      late AuthSuccess auth;
      try {
        auth = await server.login(provider, credential);
      } on LoginException catch (error) {
        return SignInOutcome.failed(
          error.code == 'configurationMissing'
              ? 'configurationMissing'
              : 'serverError',
        );
      } on ServerpodClientNetworkException {
        return const SignInOutcome.failed('networkError');
      } on SocketException {
        return const SignInOutcome.failed('networkError');
      } on TimeoutException {
        return const SignInOutcome.failed('networkError');
      } on Exception {
        return const SignInOutcome.failed('serverError');
      }
      try {
        // Never call updateSignedInUser here: save owns the Watch boundary.
        await session.save(auth);
      } on Exception {
        return const SignInOutcome.failed('sessionStorageError');
      }
      if (provider == SignInProvider.google) {
        try {
          await onGoogleSignedIn?.call(auth.authUserId);
        } on Exception {
          // The record only enables Google revoke at deletion; a saved
          // sign-in must not fail because of it.
        }
      }
      return SignInOutcome.signedIn;
    } finally {
      _starting = false;
    }
  }
}
