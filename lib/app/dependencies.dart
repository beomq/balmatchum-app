import 'dart:async';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../features/auth/auth_adapters.dart';
import '../features/auth/kakao_auth_service.dart';
import '../features/bootstrap/greeting_check.dart';
import '../features/watch_sync/watch_bridge.dart';
import '../features/watch_sync/watch_sync_server.dart';
import '../features/watch_sync/watch_sync_service.dart';

const serverUrl = String.fromEnvironment('SERVER_URL');

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

final greetingCheckProvider = Provider<GreetingCheck?>((ref) {
  if (serverUrl.isEmpty) return null;
  return ref.watch(clientProvider).greeting.hello;
});
