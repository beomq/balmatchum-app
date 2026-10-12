import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';

enum SignInProvider { google, apple, kakao, naver }

enum SignInStatus { notConnected, signedIn, cancelled, failed }

final class SignInOutcome {
  const SignInOutcome._(this.status, [this.code]);

  static const notConnected = SignInOutcome._(SignInStatus.notConnected);
  static const signedIn = SignInOutcome._(SignInStatus.signedIn);
  static const cancelled = SignInOutcome._(SignInStatus.cancelled);
  const SignInOutcome.failed(String code) : this._(SignInStatus.failed, code);

  final SignInStatus status;
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is SignInOutcome && status == other.status && code == other.code;

  @override
  int get hashCode => Object.hash(status, code);
}

abstract interface class SignInStarter {
  Future<SignInOutcome> start(SignInProvider provider);
}

class NotConnectedSignInStarter implements SignInStarter {
  const NotConnectedSignInStarter();

  @override
  Future<SignInOutcome> start(SignInProvider provider) async =>
      SignInOutcome.notConnected;
}

final signInStarterProvider = Provider<SignInStarter>(
  (ref) =>
      ref.watch(kakaoAuthServiceProvider) ?? const NotConnectedSignInStarter(),
);
