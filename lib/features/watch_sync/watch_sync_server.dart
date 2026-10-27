import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'watch_contract.dart' as watch;

abstract interface class WatchSyncServer {
  String? get accountId;
  Future<bool> validateAuthentication();
  Future<RecordReceipt> saveConfirmed(String accountId, GpsRecordInput input);
}

class ServerpodWatchSyncServer implements WatchSyncServer {
  ServerpodWatchSyncServer(this.client);

  final Client client;

  @override
  String? get accountId => client.auth.authInfo?.authUserId.toString();

  @override
  Future<bool> validateAuthentication() async {
    final account = accountId;
    if (account == null) return false;
    final validation = await _clientForAccount(account);
    try {
      // Validation must not mutate the shared manager after a timeout or a
      // concurrent logout. In particular, a stale rejection cannot sign out B.
      return await validation.modules.serverpod_auth_core.status.isSignedIn();
    } finally {
      validation.close();
    }
  }

  @override
  Future<RecordReceipt> saveConfirmed(
    String accountId,
    GpsRecordInput input,
  ) async {
    final upload = await _clientForAccount(accountId);
    try {
      return await upload.records.saveConfirmed(input);
    } finally {
      upload.close();
    }
  }

  Future<Client> _clientForAccount(String accountId) async {
    if (this.accountId != accountId) throw StateError('Watch account changed');
    final authentication = client.auth.authInfo;
    final header = await client.auth.authHeaderValue;
    if (!identical(authentication, client.auth.authInfo) ||
        this.accountId != accountId ||
        header == null ||
        header.isEmpty) {
      throw StateError('Watch account changed or missing authentication');
    }
    // A mutable session manager could refresh/retry using another account.
    // This generated client can only ever send the captured account's header.
    return Client(client.host, connectionTimeout: client.connectionTimeout)
      ..authKeyProvider = _CapturedAuthHeader(header);
  }
}

class _CapturedAuthHeader implements ClientAuthKeyProvider {
  _CapturedAuthHeader(this.header);
  final String header;

  @override
  Future<String?> get authHeaderValue async => header;
}

GpsRecordInput watchRecordInput(watch.GpsRecord record) {
  final json = record.toJson();
  return GpsRecordInput(
    schemaVersion: 1,
    clientRecordId: UuidValue.fromString(json['recordId']! as String),
    startedAt: DateTime.parse(json['startedAt']! as String),
    endedAt: DateTime.parse(json['endedAt']! as String),
    source: 'watch',
    // The first release does not collect or upload location, including records
    // left in the native queue by an older companion.
    routePoints: [],
  );
}

void validateWatchReceipt(GpsRecordInput input, RecordReceipt receipt) {
  if (receipt.clientRecordId != input.clientRecordId ||
      receipt.schemaVersion != input.schemaVersion ||
      !receipt.persistedAt.isUtc ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(receipt.recordId.toString())) {
    throw const FormatException('Server receipt does not match Watch request');
  }
}
