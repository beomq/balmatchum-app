import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SignInProvider { google, apple, kakao, naver }

enum SignInOutcome { notConnected }

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
  (ref) => const NotConnectedSignInStarter(),
);
