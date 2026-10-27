import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'social_auth_service.dart';

class NaverPkce {
  NaverPkce() {
    final random = Random.secure();
    verifier = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  late final String verifier;

  String get challenge => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
}

/// Only returns a code for the exact callback and state of this login attempt.
class NaverLoginBrowser {
  NaverLoginBrowser({
    Future<String> Function(String url, String scheme)? authenticate,
  }) : _authenticate =
           authenticate ??
           ((url, scheme) => FlutterWebAuth2.authenticate(
             url: url,
             callbackUrlScheme: scheme,
           ));

  final Future<String> Function(String url, String scheme) _authenticate;

  Future<String> authorize({
    required String authorizationUrl,
    required Uri redirectUri,
    required String state,
    required String codeChallenge,
  }) async {
    final url = Uri.tryParse(authorizationUrl);
    final parameters = url?.queryParametersAll;
    bool matches(String key, String expected) =>
        parameters?[key]?.length == 1 && parameters![key]!.single == expected;
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'nid.naver.com' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.path != '/oauth2/authorize' ||
        url.hasFragment ||
        state.isEmpty ||
        redirectUri.hasQuery ||
        redirectUri.hasFragment ||
        redirectUri.userInfo.isNotEmpty ||
        !RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(redirectUri.scheme) ||
        const {'http', 'https'}.contains(redirectUri.scheme) ||
        !matches('response_type', 'code') ||
        !matches('redirect_uri', redirectUri.toString()) ||
        !matches('state', state) ||
        !matches('code_challenge', codeChallenge) ||
        !matches('code_challenge_method', 'S256')) {
      throw const SocialLoginFailure('configurationMissing');
    }

    final String response;
    try {
      response = await _authenticate(authorizationUrl, redirectUri.scheme);
    } on PlatformException catch (error) {
      throw SocialLoginFailure(
        error.code == 'CANCELED' ? 'cancelled' : 'sdkError',
      );
    }
    final callback = Uri.tryParse(response);
    if (callback == null ||
        callback.hasFragment ||
        callback.toString().split('?').first != redirectUri.toString() ||
        callback.queryParametersAll['state']?.length != 1 ||
        callback.queryParameters['state'] != state) {
      throw const SocialLoginFailure('invalidCallback');
    }
    final values = callback.queryParametersAll;
    if (values.containsKey('error')) {
      if (values['error']!.length != 1 || values.containsKey('code')) {
        throw const SocialLoginFailure('invalidCallback');
      }
      throw SocialLoginFailure(
        values['error']!.single == 'access_denied' ? 'cancelled' : 'sdkError',
      );
    }
    if (values['code']?.length != 1 || values['code']!.single.isEmpty) {
      throw const SocialLoginFailure('invalidCallback');
    }
    return values['code']!.single;
  }
}
