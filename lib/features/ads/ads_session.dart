import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'ads_controller.dart';
import 'ads_sdk.dart';

/// Captures credentials once, before create AND get. Never follows another login.
Future<AdsController?> createAdsController(Client client, {AdsSdk? sdk}) async {
  final authentication = client.auth.authInfo;
  if (authentication == null) return null;
  final header = await client.auth.authHeaderValue;
  if (header == null || !identical(authentication, client.auth.authInfo)) {
    return null;
  }
  final scoped = Client(
    client.host,
    connectionTimeout: client.connectionTimeout,
  )..authKeyProvider = _FixedAdsHeader(header);
  late final AdsController controller;
  bool isCurrent() => identical(authentication, client.auth.authInfo);
  void changed() {
    if (!isCurrent()) controller.cancel();
  }

  controller = AdsController(
    server: _SessionAdsServer(scoped, isCurrent, () {
      client.auth.authInfoListenable.removeListener(changed);
      scoped.close();
    }),
    sdk: sdk ?? GoogleAdsSdk.instance,
  );
  client.auth.authInfoListenable.addListener(changed);
  return controller;
}

class _FixedAdsHeader implements ClientAuthKeyProvider {
  _FixedAdsHeader(this.header);
  final String header;
  @override
  Future<String?> get authHeaderValue async => header;
}

class _SessionAdsServer implements AdsServer {
  _SessionAdsServer(this.client, this.current, this.onClose);
  final Client client;
  final bool Function() current;
  final void Function() onClose;
  @override
  bool get isCurrent => current();
  @override
  Future<AdIntent> create(String purpose, String date, int revision) {
    if (!isCurrent) throw StateError('Ad account changed');
    return client.ads.createIntent(purpose, date, revision);
  }

  @override
  Future<AdIntent> get(String id) {
    if (!isCurrent) throw StateError('Ad account changed');
    return client.ads.getIntent(id);
  }

  @override
  void close() => onClose();
}
