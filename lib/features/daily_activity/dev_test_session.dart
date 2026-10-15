import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

/// Local harness import, never an OAuth response or a bundled credential.
/// The harness puts the private server-issued file in Application Support.
Future<bool> importDevTestSession(Client client) async {
  if (appFlavor != 'dev') return false;
  final uri = Uri.tryParse(client.host);
  if (uri == null || !{'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
    return false;
  }
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/dev-test-session.json');
  if (!await file.exists()) return false;
  final data = jsonDecode(await file.readAsString());
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Invalid dev session file');
  }
  final auth = AuthSuccess.fromJson(data);
  // The server remains authoritative. Never activate a native account merely
  // because a local file supplied an account ID.
  final validation = Client(
    client.host,
    connectionTimeout: client.connectionTimeout,
  )..authKeyProvider = _DevSessionHeader(auth.token);
  try {
    if (!await validation.modules.serverpod_auth_core.status.isSignedIn()) {
      return false;
    }
  } finally {
    validation.close();
  }
  await client.auth.updateSignedInUser(auth);
  await file.delete();
  return true;
}

class _DevSessionHeader implements ClientAuthKeyProvider {
  _DevSessionHeader(this.token);
  final String token;

  @override
  Future<String?> get authHeaderValue async => 'Bearer $token';
}
