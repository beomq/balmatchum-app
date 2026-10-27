import 'dart:async';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../features/auth/auth_adapters.dart';
import '../features/auth/account_deletion.dart';
import '../features/first_meeting/data/first_meeting_file_storage.dart';
import '../features/auth/kakao_auth_service.dart';
import '../features/auth/naver_auth_service.dart';
import '../features/auth/naver_login_browser.dart';
import '../features/auth/sign_in_starter.dart';
import '../features/auth/social_auth_adapters.dart';
import '../features/auth/social_auth_service.dart';
import '../features/bootstrap/greeting_check.dart';
import '../features/watch_sync/watch_bridge.dart';
import '../features/watch_sync/watch_sync_server.dart';
import '../features/watch_sync/watch_sync_service.dart';

const serverUrl = String.fromEnvironment('SERVER_URL');

final accountNoticeProvider = Provider<ValueNotifier<String?>>((ref) {
  final notice = ValueNotifier<String?>(null);
  ref.onDispose(notice.dispose);
  return notice;
});

final authenticatedAccountProvider = Provider<String?>((ref) {
  if (serverUrl.isEmpty) return null;
  final auth = ref.watch(clientProvider).auth;
  void changed() => ref.invalidateSelf();
  auth.authInfoListenable.addListener(changed);
  ref.onDispose(() => auth.authInfoListenable.removeListener(changed));
  return auth.authInfo?.authUserId.toString();
});

final clientProvider = Provider<Client>((ref) {
  final client = Client(
    serverUrl,
    connectionTimeout: const Duration(seconds: 10),
  );
  client.authSessionManager = FlutterAuthSessionManager();
  ref.onDispose(client.close);
  return client;
});

final watchSyncServiceProvider = Provider<WatchSyncService?>((ref) {
  if (serverUrl.isEmpty ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS) {
    return null;
  }
  final client = ref.watch(clientProvider);
  final service = WatchSyncService(
    bridge: WatchBridge(),
    server: ServerpodWatchSyncServer(client),
  );
  var account = client.auth.authInfo?.authUserId;
  void changed() {
    final next = client.auth.authInfo?.authUserId;
    if (next != account) {
      account = next;
      service.authenticationChanged();
    }
  }

  client.auth.authInfoListenable.addListener(changed);
  ref.onDispose(() {
    client.auth.authInfoListenable.removeListener(changed);
    unawaited(service.dispose());
  });
  return service;
});

final kakaoAuthServiceProvider = Provider<KakaoAuthService?>((ref) {
  if (serverUrl.isEmpty || kakaoNativeAppKey.isEmpty) return null;
  final client = ref.watch(clientProvider);
  return KakaoAuthService(
    server: ServerpodKakaoLoginServer(client),
    sdk: KakaoSdkLogin(),
    session: ServerpodAuthSession(
      client.auth,
      watchSync: ref.watch(watchSyncServiceProvider),
    ),
  );
});

final socialAuthServiceProvider = Provider<SignInStarter>((ref) {
  final configuration = SocialAuthConfiguration(
    serverUrl: serverUrl,
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
  );
  // A disconnected app never constructs a client or invokes a native SDK.
  if (serverUrl.isEmpty) return const UnconfiguredSocialSignInStarter();
  final client = ref.watch(clientProvider);
  var alive = true;
  var authenticationEpoch = 0;
  void authenticationChanged() => authenticationEpoch++;
  client.auth.authInfoListenable.addListener(authenticationChanged);
  ref.onDispose(() {
    alive = false;
    client.auth.authInfoListenable.removeListener(authenticationChanged);
  });
  final session = ServerpodAuthSession(
    client.auth,
    watchSync: ref.watch(watchSyncServiceProvider),
  );
  return SocialAuthService(
    isConfigured: configuration.isConfigured,
    sdk: NativeSocialLoginSdk(configuration: configuration),
    server: ServerpodSocialLoginServer(client, platform: defaultTargetPlatform),
    session: session,
    kakao: ref.watch(kakaoAuthServiceProvider),
    naver:
        !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android)
        ? NaverAuthService(
            isConfigured: client.naver.isConfigured,
            beginLogin: (challenge) =>
                client.naver.beginLogin(codeChallenge: challenge),
            completeLogin: (attempt, code, verifier) =>
                client.naver.completeLogin(
                  attemptId: attempt.attemptId,
                  code: code,
                  state: attempt.state,
                  codeVerifier: verifier,
                ),
            redirectUri: Uri.parse(
              'com.beomq.balmatchum${appFlavor == 'dev' ? '.dev' : ''}'
              '://naver/callback',
            ),
            browser: NaverLoginBrowser(),
            session: session,
            authentication: () => authenticationEpoch,
            isAlive: () => alive,
          )
        : null,
  );
});

final logoutProvider = Provider<Future<LogoutOutcome> Function()?>((ref) {
  if (serverUrl.isEmpty) return null;
  final kakao = ref.watch(kakaoAuthServiceProvider);
  if (kakao != null) return kakao.logout;
  final session = ServerpodAuthSession(
    ref.watch(clientProvider).auth,
    watchSync: ref.watch(watchSyncServiceProvider),
  );
  return () async =>
      LogoutOutcome(session: await session.logout(), sdkLoggedOut: false);
});

final greetingCheckProvider = Provider<GreetingCheck?>((ref) {
  if (serverUrl.isEmpty) return null;
  return ref.watch(clientProvider).greeting.hello;
});

final accountDeletionProvider = Provider<AccountDeletion?>((ref) {
  final account = ref.watch(authenticatedAccountProvider);
  if (account == null) return null;
  final client = ref.watch(clientProvider);
  final logout = ref.watch(logoutProvider)!;
  final notice = ref.watch(accountNoticeProvider);
  Future<File> marker() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/deletion-$account');
  }

  return AccountDeletion(
    markPending: () async {
      final file = await marker();
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        await file.writeAsString('pending', flush: true);
      }
    },
    wasRemoteDeleted: () async {
      final file = await marker();
      return await file.exists() && await file.readAsString() == 'deleted';
    },
    markRemoteDeleted: () async {
      await (await marker()).writeAsString('deleted', flush: true);
    },
    clearPending: () async {
      final file = await marker();
      if (await file.exists()) await file.delete();
    },
    deleteRemote: () async {
      try {
        await client.account.deleteAccount();
        notice.value = '계정이 삭제되었습니다.';
      } on ServerpodClientUnauthorized {
        notice.value = '인증이 만료되어 기기 정보를 정리했어요. 계정 삭제 여부는 다시 로그인해 확인해 주세요.';
        rethrow;
      }
    },
    clearLocal: () async {
      await FirstMeetingFileStorage.forAccount(account).delete();
      final directory = await getApplicationSupportDirectory();
      for (final suffix in ['', '.tmp']) {
        final file = File('${directory.path}/steps-$account.json$suffix');
        if (await file.exists()) await file.delete();
      }
    },
    signOut: () async {
      final result = await logout();
      if (!result.session.localCleared) {
        throw StateError('Local session cleanup failed');
      }
    },
  );
});
