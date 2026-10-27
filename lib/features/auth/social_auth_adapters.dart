import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'sign_in_starter.dart';
import 'social_auth_service.dart';

class SocialAuthConfiguration {
  const SocialAuthConfiguration({
    required this.serverUrl,
    required this.platform,
    this.isWeb = false,
    this.googleClientId = const String.fromEnvironment('GOOGLE_CLIENT_ID'),
    this.googleServerClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    this.appleEnabled = const bool.fromEnvironment('APPLE_SIGN_IN_ENABLED'),
    this.appleServiceIdentifier = const String.fromEnvironment(
      'APPLE_SERVICE_IDENTIFIER',
    ),
    this.appleRedirectUri = const String.fromEnvironment('APPLE_REDIRECT_URI'),
  });

  final String serverUrl;
  final TargetPlatform platform;
  final bool isWeb;
  final String googleClientId;
  final String googleServerClientId;
  final bool appleEnabled;
  final String appleServiceIdentifier;
  final String appleRedirectUri;

  bool isConfigured(SignInProvider provider) {
    if (serverUrl.trim().isEmpty || isWeb) return false;
    if (platform != TargetPlatform.iOS && platform != TargetPlatform.android) {
      return false;
    }
    return switch (provider) {
      SignInProvider.google =>
        googleServerClientId.trim().isNotEmpty &&
            (platform != TargetPlatform.iOS ||
                googleClientId.trim().isNotEmpty),
      SignInProvider.apple =>
        appleEnabled &&
            (platform == TargetPlatform.iOS ||
                (appleServiceIdentifier.trim().isNotEmpty &&
                    Uri.tryParse(appleRedirectUri)?.scheme == 'https' &&
                    (Uri.tryParse(appleRedirectUri)?.host.isNotEmpty ??
                        false))),
      _ => false,
    };
  }
}

class NativeSocialLoginSdk implements SocialLoginSdk {
  NativeSocialLoginSdk({
    required this.configuration,
    Future<void> Function()? initializeGoogle,
    Future<String?> Function()? authenticateGoogle,
    Future<void> Function()? restoreGoogle,
    Future<void> Function()? disconnectGoogle,
    Future<bool> Function()? googleCallbackConfigured,
    Future<AuthorizationCredentialAppleID> Function()? authenticateApple,
  }) : _initializeGoogle =
           initializeGoogle ??
           (() => GoogleSignIn.instance.initialize(
             clientId: configuration.platform == TargetPlatform.iOS
                 ? configuration.googleClientId
                 : null,
             serverClientId: configuration.googleServerClientId,
           )),
       _authenticateGoogle =
           authenticateGoogle ??
           (() async => (await GoogleSignIn.instance.authenticate())
               .authentication
               .idToken),
       _restoreGoogle =
           restoreGoogle ??
           (() async {
             await GoogleSignIn.instance.attemptLightweightAuthentication();
           }),
       _disconnectGoogle = disconnectGoogle ?? GoogleSignIn.instance.disconnect,
       _googleCallbackConfigured =
           googleCallbackConfigured ??
           (() async =>
               await const MethodChannel('com.beomq.balmatchum/auth')
                   .invokeMethod<bool>('googleCallbackConfigured', {
                     'clientId': configuration.googleClientId,
                   }) ??
               false),
       _authenticateApple =
           authenticateApple ??
           (() => SignInWithApple.getAppleIDCredential(
             scopes: [
               AppleIDAuthorizationScopes.email,
               AppleIDAuthorizationScopes.fullName,
             ],
             webAuthenticationOptions:
                 configuration.platform == TargetPlatform.android
                 ? WebAuthenticationOptions(
                     clientId: configuration.appleServiceIdentifier,
                     redirectUri: Uri.parse(configuration.appleRedirectUri),
                   )
                 : null,
           ));

  final SocialAuthConfiguration configuration;
  final Future<void> Function() _initializeGoogle;
  final Future<String?> Function() _authenticateGoogle;
  final Future<void> Function() _restoreGoogle;
  final Future<void> Function() _disconnectGoogle;
  final Future<bool> Function() _googleCallbackConfigured;
  final Future<AuthorizationCredentialAppleID> Function() _authenticateApple;
  Future<void>? _googleInitialization;

  Future<void> _ensureGoogleInitialized() async {
    try {
      await (_googleInitialization ??= _initializeGoogle());
    } on Exception {
      _googleInitialization = null;
      rethrow;
    }
  }

  Future<void> disconnectGoogle() async {
    if (!configuration.isConfigured(SignInProvider.google)) return;
    await _ensureGoogleInitialized();
    // Android's revoke cache is process-local; restore it after app restart.
    // This does not save or create a Serverpod session.
    await _restoreGoogle();
    await _disconnectGoogle();
  }

  @override
  Future<SocialCredential> authenticate(SignInProvider provider) async {
    if (!configuration.isConfigured(provider)) {
      throw const SocialLoginFailure('configurationMissing');
    }
    try {
      if (provider == SignInProvider.google) {
        if (configuration.platform == TargetPlatform.iOS &&
            !await _googleCallbackConfigured()) {
          throw const SocialLoginFailure('configurationMissing');
        }
        // Memoize the in-flight future, not an unawaited controller flag.
        // No event subscription or lightweight authentication can sign in.
        await _ensureGoogleInitialized();
        return SocialCredential(idToken: await _authenticateGoogle() ?? '');
      }
      final credential = await _authenticateApple();
      return SocialCredential(
        idToken: credential.identityToken ?? '',
        authorizationCode: credential.authorizationCode,
        firstName: credential.givenName,
        lastName: credential.familyName,
      );
    } on GoogleSignInException catch (error) {
      throw SocialLoginFailure(switch (error.code) {
        GoogleSignInExceptionCode.canceled => 'cancelled',
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'configurationMissing',
        _ => 'sdkError',
      });
    } on SignInWithAppleAuthorizationException catch (error) {
      throw SocialLoginFailure(
        error.code == AuthorizationErrorCode.canceled
            ? 'cancelled'
            : 'sdkError',
      );
    } on SignInWithAppleNotSupportedException {
      throw const SocialLoginFailure('configurationMissing');
    } on PlatformException catch (error) {
      throw SocialLoginFailure(
        error.code == 'network_error' ? 'networkError' : 'sdkError',
      );
    }
  }
}

class ServerpodSocialLoginServer implements SocialLoginServer {
  ServerpodSocialLoginServer(this.client, {required this.platform});

  final Client client;
  final TargetPlatform platform;

  @override
  Future<bool> isConfigured(SignInProvider provider) => switch (provider) {
    SignInProvider.google => client.googleIdp.isConfigured(),
    SignInProvider.apple => client.appleIdp.isConfigured(),
    _ => Future.value(false),
  };

  @override
  Future<AuthSuccess> login(
    SignInProvider provider,
    SocialCredential credential,
  ) => switch (provider) {
    SignInProvider.google =>
      client.getEndpointOfType<EndpointGoogleIdpBase>().login(
        idToken: credential.idToken,
        accessToken: null,
      ),
    SignInProvider.apple =>
      client.getEndpointOfType<EndpointAppleIdpBase>().login(
        identityToken: credential.idToken,
        authorizationCode: credential.authorizationCode!,
        isNativeApplePlatformSignIn: platform == TargetPlatform.iOS,
        firstName: credential.firstName,
        lastName: credential.lastName,
      ),
    _ => throw const SocialLoginFailure('unsupportedProvider'),
  };
}
