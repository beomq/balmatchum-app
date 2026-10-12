import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../features/auth/auth_adapters.dart';
import '../features/auth/kakao_auth_service.dart';
import '../features/bootstrap/greeting_check.dart';

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

final kakaoAuthServiceProvider = Provider<KakaoAuthService?>((ref) {
  if (serverUrl.isEmpty || kakaoNativeAppKey.isEmpty) return null;
  final client = ref.watch(clientProvider);
  return KakaoAuthService(
    server: ServerpodKakaoLoginServer(client),
    sdk: KakaoSdkLogin(),
    session: ServerpodAuthSession(client.auth),
  );
});

final greetingCheckProvider = Provider<GreetingCheck?>((ref) {
  if (serverUrl.isEmpty) return null;
  return ref.watch(clientProvider).greeting.hello;
});
