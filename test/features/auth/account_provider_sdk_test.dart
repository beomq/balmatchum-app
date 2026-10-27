import 'dart:async';

import 'package:balmatchum_app/features/auth/auth_adapters.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/auth/social_auth_adapters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _android = SocialAuthConfiguration(
  serverUrl: 'https://api.test/',
  platform: TargetPlatform.android,
  googleServerClientId: 'test-client',
);

const _ios = SocialAuthConfiguration(
  serverUrl: 'https://api.test/',
  platform: TargetPlatform.iOS,
  googleClientId: 'ios-client',
  googleServerClientId: 'test-client',
);

NativeSocialLoginSdk _googleSdk(
  SocialAuthConfiguration configuration,
  List<String> events, {
  Future<void> Function()? initializeGoogle,
}) => NativeSocialLoginSdk(
  configuration: configuration,
  googleCallbackConfigured: () async => true,
  initializeGoogle: initializeGoogle ?? () async => events.add('initialize'),
  authenticateGoogle: () async {
    events.add('authenticate');
    return 'identity';
  },
  restoreGoogle: () async => events.add('restore'),
  disconnectGoogle: () async => events.add('revoke'),
);

void main() {
  test('Kakao deletion unlinks instead of logging out', () async {
    // Given
    final events = <String>[];
    final sdk = KakaoSdkLogin(
      hasToken: () async => true,
      sdkUnlink: () async => events.add('unlink'),
      sdkLogout: () async => events.add('logout'),
    );

    // When
    await sdk.unlink();

    // Then
    expect(events, ['unlink']);
  });

  test('Kakao deletion skips unlink when there is no stored grant', () async {
    // Given
    final events = <String>[];
    final sdk = KakaoSdkLogin(
      hasToken: () async => false,
      sdkUnlink: () async => events.add('unlink'),
    );

    // When
    await sdk.unlink();

    // Then
    expect(events, isEmpty);
  });

  for (final configuration in [_android, _ios]) {
    test(
      '${configuration.platform.name} non-Google account never touches Google',
      () async {
        // Given
        final events = <String>[];
        final sdk = _googleSdk(configuration, events);

        // When
        await sdk.disconnectGoogle(signedInWithGoogle: false);

        // Then
        expect(events, isEmpty);
      },
    );
  }

  test('iOS Google account restores from keychain then revokes', () async {
    // Given
    final events = <String>[];
    final sdk = _googleSdk(_ios, events);

    // When
    await sdk.disconnectGoogle(signedInWithGoogle: true);

    // Then
    expect(events, ['initialize', 'restore', 'revoke']);
  });

  test('Android revokes the in-process account without restore UI', () async {
    // Given
    final events = <String>[];
    final sdk = _googleSdk(_android, events);
    await sdk.authenticate(SignInProvider.google);
    events.clear();

    // When
    await sdk.disconnectGoogle(signedInWithGoogle: true);

    // Then
    expect(events, ['revoke']);
  });

  test(
    'Android cold Google account reports incomplete instead of prompting',
    () async {
      // Given
      final events = <String>[];
      final sdk = _googleSdk(_android, events);

      // When
      final result = sdk.disconnectGoogle(signedInWithGoogle: true);

      // Then
      await expectLater(result, throwsA(isA<GoogleDisconnectUnavailable>()));
      expect(events, isNot(contains('restore')));
      expect(events, isNot(contains('revoke')));
    },
  );

  test('login and deletion await one Google initialization', () async {
    // Given
    final initialized = Completer<void>();
    final entered = Completer<void>();
    var initializations = 0;
    final events = <String>[];
    final sdk = _googleSdk(
      _ios,
      events,
      initializeGoogle: () {
        initializations++;
        entered.complete();
        return initialized.future;
      },
    );
    final login = sdk.authenticate(SignInProvider.google);
    await entered.future;

    // When
    final deletion = sdk.disconnectGoogle(signedInWithGoogle: true);
    expect(events, isEmpty);
    initialized.complete();
    await Future.wait([login, deletion]);

    // Then
    expect(initializations, 1);
    expect(events, containsAllInOrder(['restore', 'revoke']));
  });

  test('unconfigured Google deletion skips every SDK operation', () async {
    // Given
    final events = <String>[];
    final sdk = _googleSdk(
      const SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: TargetPlatform.android,
      ),
      events,
    );

    // When
    await sdk.disconnectGoogle(signedInWithGoogle: true);

    // Then
    expect(events, isEmpty);
  });
}
