import 'dart:async';

import 'package:balmatchum_app/features/auth/auth_adapters.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/auth/social_auth_adapters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('cold Google deletion initializes and restores before revoke', () async {
    // Given
    final events = <String>[];
    final sdk = NativeSocialLoginSdk(
      configuration: const SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: TargetPlatform.android,
        googleServerClientId: 'test-client',
      ),
      initializeGoogle: () async => events.add('initialize'),
      restoreGoogle: () async => events.add('restore'),
      disconnectGoogle: () async => events.add('revoke'),
      authenticateGoogle: () async {
        fail('Deletion must not start interactive authentication');
      },
    );

    // When
    await sdk.disconnectGoogle();

    // Then
    expect(events, ['initialize', 'restore', 'revoke']);
  });

  test('login and deletion await one Google initialization', () async {
    // Given
    final initialized = Completer<void>();
    final entered = Completer<void>();
    var initializations = 0;
    final events = <String>[];
    final sdk = NativeSocialLoginSdk(
      configuration: const SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: TargetPlatform.android,
        googleServerClientId: 'test-client',
      ),
      initializeGoogle: () {
        initializations++;
        entered.complete();
        return initialized.future;
      },
      authenticateGoogle: () async => 'identity',
      restoreGoogle: () async => events.add('restore'),
      disconnectGoogle: () async => events.add('revoke'),
    );
    final login = sdk.authenticate(SignInProvider.google);
    await entered.future;

    // When
    final deletion = sdk.disconnectGoogle();
    expect(events, isEmpty);
    initialized.complete();
    await Future.wait([login, deletion]);

    // Then
    expect(initializations, 1);
    expect(events, ['restore', 'revoke']);
  });

  test('unconfigured Google deletion skips every SDK operation', () async {
    // Given
    final events = <String>[];
    final sdk = NativeSocialLoginSdk(
      configuration: const SocialAuthConfiguration(
        serverUrl: 'https://api.test/',
        platform: TargetPlatform.android,
      ),
      initializeGoogle: () async => events.add('initialize'),
      restoreGoogle: () async => events.add('restore'),
      disconnectGoogle: () async => events.add('revoke'),
    );

    // When
    await sdk.disconnectGoogle();

    // Then
    expect(events, isEmpty);
  });
}
