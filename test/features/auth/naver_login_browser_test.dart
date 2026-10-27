import 'dart:convert';

import 'package:balmatchum_app/features/auth/naver_login_browser.dart';
import 'package:balmatchum_app/features/auth/social_auth_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final redirect = Uri.parse('com.beomq.balmatchum.dev://naver/callback');
  late NaverPkce pkce;
  late Uri url;
  setUp(() {
    pkce = NaverPkce();
    url = Uri.https('nid.naver.com', '/oauth2/authorize', {
      'response_type': 'code',
      'redirect_uri': redirect.toString(),
      'state': 'attempt-state',
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
    });
  });
  Future<String> run(String callback, {Uri? authorize}) =>
      NaverLoginBrowser(
        authenticate: (value, scheme) async {
          expect(value, (authorize ?? url).toString());
          expect(scheme, redirect.scheme);
          return callback;
        },
      ).authorize(
        authorizationUrl: (authorize ?? url).toString(),
        redirectUri: redirect,
        state: 'attempt-state',
        codeChallenge: pkce.challenge,
      );
  Matcher failure(String code) =>
      isA<SocialLoginFailure>().having((value) => value.code, 'code', code);

  test('PKCE has 32 random bytes and S256 challenge', () {
    expect(pkce.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(base64Url.decode(base64Url.normalize(pkce.verifier)), hasLength(32));
    expect(
      pkce.challenge,
      base64Url
          .encode(sha256.convert(ascii.encode(pkce.verifier)).bytes)
          .replaceAll('=', ''),
    );
  });

  test('exact callback returns only authorization code', () async {
    expect(
      await run('$redirect?state=attempt-state&code=one-time-code'),
      'one-time-code',
    );
  });

  for (final suffix in [
    '?state=wrong&code=x',
    '?state=attempt-state&state=attempt-state&code=x',
    '?state=attempt-state&code=x&code=y',
    '?state=attempt-state&code=',
    '?state=attempt-state',
    '?state=attempt-state&code=x#fragment',
    '?state=attempt-state&code=x&error=access_denied',
  ]) {
    test('rejects malformed callback $suffix', () async {
      await expectLater(
        run('$redirect$suffix'),
        throwsA(failure('invalidCallback')),
      );
    });
  }

  test('rejects callback path and scheme changes', () async {
    for (final other in [
      'com.beomq.balmatchum.dev://naver/other',
      'other.app://naver/callback',
      'com.beomq.balmatchum.dev://other/callback',
    ]) {
      await expectLater(
        run('$other?state=attempt-state&code=x'),
        throwsA(failure('invalidCallback')),
      );
    }
  });

  test('denial requires valid state', () async {
    await expectLater(
      run('$redirect?state=attempt-state&error=access_denied'),
      throwsA(failure('cancelled')),
    );
    await expectLater(
      run('$redirect?state=wrong&error=access_denied'),
      throwsA(failure('invalidCallback')),
    );
  });

  test('untrusted authorization URL never opens browser', () async {
    var opened = false;
    final browser = NaverLoginBrowser(
      authenticate: (url, scheme) async {
        opened = true;
        return '';
      },
    );
    for (final bad in [
      url.replace(host: 'untrusted.invalid'),
      url.replace(path: '/oauth2.0/authorize'),
      url.replace(queryParameters: {...url.queryParameters, 'state': 'wrong'}),
      url.replace(
        queryParameters: {
          ...url.queryParameters,
          'code_challenge_method': 'plain',
        },
      ),
    ]) {
      await expectLater(
        browser.authorize(
          authorizationUrl: bad.toString(),
          redirectUri: redirect,
          state: 'attempt-state',
          codeChallenge: pkce.challenge,
        ),
        throwsA(failure('configurationMissing')),
      );
    }
    expect(opened, isFalse);
  });

  test('native cancellation is not a server login failure', () async {
    await expectLater(
      NaverLoginBrowser(
        authenticate: (url, scheme) async =>
            throw PlatformException(code: 'CANCELED'),
      ).authorize(
        authorizationUrl: url.toString(),
        redirectUri: redirect,
        state: 'attempt-state',
        codeChallenge: pkce.challenge,
      ),
      throwsA(failure('cancelled')),
    );
  });
}
