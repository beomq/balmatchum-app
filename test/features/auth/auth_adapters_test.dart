import 'package:balmatchum_app/features/auth/auth_adapters.dart';
import 'package:balmatchum_app/features/auth/kakao_auth_service.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

class _Storage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  bool failSet = false;

  @override
  Future<AuthSuccess?> get() async => value;

  @override
  Future<void> set(AuthSuccess? data) async {
    if (failSet) throw Exception('storage');
    value = data;
  }
}

void main() {
  test('empty native key skips initialization', () {
    final keys = <String>[];
    expect(initializeKakaoSdk(nativeAppKey: '', initialize: keys.add), isFalse);
    expect(keys, isEmpty);
    expect(
      initializeKakaoSdk(nativeAppKey: 'public-key', initialize: keys.add),
      isTrue,
    );
    expect(keys, ['public-key']);
  });

  test('empty configuration exposes disconnected starter', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(signInStarterProvider).start(SignInProvider.kakao),
      SignInOutcome.notConnected,
    );
  });

  for (final installed in [true, false]) {
    test('selects SDK route installed=$installed and forwards nonce', () async {
      final calls = <String>[];
      final token = OAuthToken('test', DateTime.utc(2030), null, null, [
        'openid',
      ], idToken: 'oidc');
      final sdk = KakaoSdkLogin(
        isTalkInstalled: () async => installed,
        talkLogin: (nonce) async {
          calls.add('talk:$nonce');
          return token;
        },
        accountLogin: (nonce) async {
          calls.add('account:$nonce');
          return token;
        },
      );
      expect(await sdk.login('nonce'), 'oidc');
      expect(calls, [installed ? 'talk:nonce' : 'account:nonce']);
    });
  }

  final cancellations = <Exception>[
    PlatformException(code: 'CANCELED'),
    KakaoClientException(ClientErrorCause.cancelled, 'cancel'),
    KakaoAuthException(AuthErrorCause.accessDenied, 'cancel'),
    KakaoApiException(ApiErrorCause.accessDenied, 'cancel'),
  ];
  for (var i = 0; i < cancellations.length; i++) {
    test('normalizes documented cancellation type $i', () async {
      final sdk = KakaoSdkLogin(
        isTalkInstalled: () async => true,
        talkLogin: (_) async => throw cancellations[i],
      );
      await expectLater(
        sdk.login('nonce'),
        throwsA(isA<KakaoLoginCancelled>()),
      );
    });
  }

  test(
    'official manager restores persisted AuthSuccess without server calls',
    () async {
      final storage = _Storage();
      final manager = FlutterAuthSessionManager(storage: storage);
      final auth = AuthSuccess(
        authStrategy: 'session',
        token: 'test-token',
        authUserId: UuidValue.fromString(
          '00000000-0000-0000-0000-000000000001',
        ),
        scopeNames: {},
      );
      await ServerpodAuthSession(manager).save(auth);
      final restored = FlutterAuthSessionManager(storage: storage);
      await restored.restore();
      expect(restored.authInfo, same(auth));
      expect(restored.isAuthenticated, isTrue);
    },
  );

  test('failed server logout still clears local session', () async {
    final storage = _Storage();
    final manager = FlutterAuthSessionManager(storage: storage);
    final result = await ServerpodAuthSession(manager).logout();
    expect(result.serverRevoked, isFalse);
    expect(result.localCleared, isTrue);
    expect(storage.value, isNull);
  });

  test('local logout persistence failure is reported separately', () async {
    final storage = _Storage()..failSet = true;
    final result = await ServerpodAuthSession(
      FlutterAuthSessionManager(storage: storage),
    ).logout();
    expect(result.serverRevoked, isNull);
    expect(result.localCleared, isFalse);
  });
}
