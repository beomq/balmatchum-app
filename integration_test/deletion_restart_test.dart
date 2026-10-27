import 'dart:io';

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_app/features/first_meeting/data/first_meeting_file_storage.dart';
import 'package:balmatchum_app/main.dart' show resumePendingDeletion;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('resume deletion across two native test processes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final client = container.read(clientProvider);
    const prepare = bool.fromEnvironment('PREPARE_DELETION');
    if (prepare) {
      expect(await importDevTestSession(client), isTrue);
    } else {
      await client.auth.restore();
    }
    final owner = client.auth.authInfo!.authUserId.toString();
    final directory = await getApplicationSupportDirectory();
    final marker = File('${directory.path}/deletion-$owner');
    final storage = FirstMeetingFileStorage.forAccount(owner);
    if (prepare) {
      await storage.write('pending cleanup fixture');
      await marker.writeAsString('pending', flush: true);
      await client.account.deleteAccount();
      await marker.writeAsString('deleted', flush: true);
      // Leave the real revoked session and files, as if the process stopped
      // after remote commit but before local cleanup.
      expect(client.auth.authInfo, isNotNull);
    } else {
      expect(await marker.readAsString(), 'deleted');
      await resumePendingDeletion(container);
      expect(client.auth.authInfo, isNull);
      expect(await storage.read(), isNull);
      expect(await marker.exists(), isFalse);
    }
  });
}
