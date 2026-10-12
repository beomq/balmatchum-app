import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'kakao_auth_service.dart';

const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

bool initializeKakaoSdk({
  required String nativeAppKey,
  required void Function(String) initialize,
}) {
  if (nativeAppKey.isEmpty) return false;
  initialize(nativeAppKey);
  return true;
}

class ServerpodKakaoLoginServer implements KakaoLoginServer {
  ServerpodKakaoLoginServer(this.client);

  final Client client;

  @override
  Future<LoginChallenge> beginLogin() =>
      client.kakao.beginLogin(provider: 'kakao');

  @override
  Future<AuthSuccess> loginKakao(LoginChallenge challenge, String idToken) =>
      client.kakao.loginKakao(attemptId: challenge.attemptId, idToken: idToken);
}

class ServerpodAuthSession implements AuthSession {
  ServerpodAuthSession(this.manager);

  final FlutterAuthSessionManager manager;

  @override
  Future<void> save(AuthSuccess auth) => manager.updateSignedInUser(auth);

  @override
  Future<SessionLogoutOutcome> logout() async {
    try {
      final revoked = await manager.signOutDevice();
      return SessionLogoutOutcome(serverRevoked: revoked, localCleared: true);
    } on Exception {
      // signOutDevice only returns after local storage has been cleared.
      return const SessionLogoutOutcome(
        serverRevoked: null,
        localCleared: false,
      );
    }
  }
}

class KakaoSdkLogin implements KakaoLoginSdk {
  KakaoSdkLogin({
    Future<bool> Function()? isTalkInstalled,
    Future<OAuthToken> Function(String)? talkLogin,
    Future<OAuthToken> Function(String)? accountLogin,
    Future<void> Function()? sdkLogout,
  }) : isTalkInstalled = isTalkInstalled ?? isKakaoTalkInstalled,
       talkLogin =
           talkLogin ??
           ((nonce) => UserApi.instance.loginWithKakaoTalk(nonce: nonce)),
       accountLogin =
           accountLogin ??
           ((nonce) => UserApi.instance.loginWithKakaoAccount(nonce: nonce)),
       sdkLogout =
           sdkLogout ??
           (() async {
             await UserApi.instance.logout();
           });

  final Future<bool> Function() isTalkInstalled;
  final Future<OAuthToken> Function(String) talkLogin;
  final Future<OAuthToken> Function(String) accountLogin;
  final Future<void> Function() sdkLogout;

  @override
  Future<String?> login(String nonce) async {
    try {
      final token = await isTalkInstalled()
          ? await talkLogin(nonce)
          : await accountLogin(nonce);
      return token.idToken;
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') throw const KakaoLoginCancelled();
      rethrow;
    } on KakaoClientException catch (error) {
      if (error.reason == ClientErrorCause.cancelled) {
        throw const KakaoLoginCancelled();
      }
      rethrow;
    } on KakaoAuthException catch (error) {
      if (error.error == AuthErrorCause.accessDenied) {
        throw const KakaoLoginCancelled();
      }
      rethrow;
    } on KakaoApiException catch (error) {
      if (error.code == ApiErrorCause.accessDenied) {
        throw const KakaoLoginCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() => sdkLogout();
}
