import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/bootstrap/greeting_check.dart';

const serverUrl = String.fromEnvironment('SERVER_URL');

final clientProvider = Provider<Client>((ref) {
  final client = Client(
    serverUrl,
    connectionTimeout: const Duration(seconds: 10),
  );
  ref.onDispose(client.close);
  return client;
});

final greetingCheckProvider = Provider<GreetingCheck?>((ref) {
  if (serverUrl.isEmpty) return null;
  return ref.watch(clientProvider).greeting.hello;
});
