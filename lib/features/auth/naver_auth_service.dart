import 'dart:async';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'kakao_auth_service.dart';
import 'naver_login_browser.dart';
import 'sign_in_starter.dart';
import 'social_auth_service.dart';

class NaverAuthService implements SignInStarter {
  NaverAuthService({
    required this.isConfigured,
    required this.beginLogin,
    required this.completeLogin,
    required this.redirectUri,
    required this.browser,
    required this.session,
    required this.authentication,
    required this.isAlive,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final Future<bool> Function() isConfigured;
  final Future<NaverLoginChallenge> Function(String challenge) beginLogin;
  final Future<AuthSuccess> Function(
    NaverLoginChallenge attempt,
    String code,
    String verifier,
  )
  completeLogin;
  final Uri redirectUri;
  final NaverLoginBrowser browser;
  final AuthSession session;
  final Object? Function() authentication;
  final bool Function() isAlive;
  final DateTime Function() now;
  bool _starting = false;

  @override
  Future<SignInOutcome> start(SignInProvider provider) async {
    if (provider != SignInProvider.naver) {
      return const SignInOutcome.failed('unsupportedProvider');
    }
    if (_starting) return const SignInOutcome.failed('signInInProgress');
    _starting = true;
    final previous = authentication();
    bool current() => isAlive() && identical(previous, authentication());
    try {
      if (!await isConfigured()) {
        return const SignInOutcome.failed('configurationMissing');
      }
      if (!current()) return SignInOutcome.cancelled;
      final pkce = NaverPkce();
      final attempt = await beginLogin(pkce.challenge);
      if (!current()) return SignInOutcome.cancelled;
      if (attempt.redirectUri != redirectUri.toString()) {
        return const SignInOutcome.failed('configurationMissing');
      }
      if (!attempt.expiresAt.isAfter(now())) {
        return const SignInOutcome.failed('invalidAttempt');
      }
      final code = await browser.authorize(
        authorizationUrl: attempt.authorizationUrl,
        redirectUri: redirectUri,
        state: attempt.state,
        codeChallenge: pkce.challenge,
      );
      if (!current()) return SignInOutcome.cancelled;
      if (!attempt.expiresAt.isAfter(now())) {
        return const SignInOutcome.failed('invalidAttempt');
      }
      final auth = await completeLogin(attempt, code, pkce.verifier);
      if (!current()) return SignInOutcome.cancelled;
      try {
        await session.save(auth);
      } on Exception {
        return const SignInOutcome.failed('sessionStorageError');
      }
      return SignInOutcome.signedIn;
    } on SocialLoginFailure catch (error) {
      return error.code == 'cancelled'
          ? SignInOutcome.cancelled
          : SignInOutcome.failed(error.code);
    } on LoginException catch (error) {
      return SignInOutcome.failed(error.code);
    } on ServerpodClientNetworkException {
      return const SignInOutcome.failed('networkError');
    } on SocketException {
      return const SignInOutcome.failed('networkError');
    } on TimeoutException {
      return const SignInOutcome.failed('networkError');
    } on Exception {
      return const SignInOutcome.failed('serverError');
    } finally {
      _starting = false;
    }
  }
}
