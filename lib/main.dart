import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'app/router.dart';
import 'features/auth/auth_adapters.dart';
import 'features/ads/ads_sdk.dart';
import 'features/records/record_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // UMP needs a mounted native view. Missing metadata never initializes the SDK.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(GoogleAdsSdk.instance.prepare());
  });
  await recordMapRuntime.initialize(clientId: naverMapClientId);
  if (appFlavor == 'dev') {
    runApp(const ProviderScope(child: AppBootstrap()));
    return;
  }
  initializeKakaoSdk(
    nativeAppKey: kakaoNativeAppKey,
    initialize: (key) => KakaoSdk.init(nativeAppKey: key),
  );
  final container = ProviderContainer();
  if (serverUrl.isNotEmpty) {
    await restoreSession(container.read(clientProvider).auth.restore);
    await resumePendingDeletion(container);
  }
  // Restoring credentials never vouches for a Watch account boundary.
  final watchSync = container.read(watchSyncServiceProvider);
  if (watchSync != null) {
    try {
      await watchSync.initialize();
    } on Exception {
      debugPrint('Watch reconciliation failed; explicit sync is required.');
    }
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AppBootstrap(),
    ),
  );
}

Future<void> resumePendingDeletion(ProviderContainer container) async {
  final account = container.read(authenticatedAccountProvider);
  if (account != null) {
    final directory = await getApplicationSupportDirectory();
    final marker = File('${directory.path}/deletion-$account');
    if (await marker.exists()) {
      try {
        await container.read(accountDeletionProvider)!.delete();
      } on Exception {
        debugPrint('Account deletion remains pending; retry from settings.');
      }
    }
  }
}

Future<void> restoreSession(Future<void> Function() restore) async {
  try {
    await restore();
  } on Exception {
    debugPrint('Session restore failed; continuing signed out.');
  }
}

class AppBootstrap extends ConsumerWidget {
  const AppBootstrap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BalmatchumApp(router: ref.watch(routerProvider));
  }
}
