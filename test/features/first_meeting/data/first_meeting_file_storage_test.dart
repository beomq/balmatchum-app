import 'dart:io';

import 'package:balmatchum_app/features/first_meeting/data/first_meeting_file_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'file replacement and reset touch only separate dev namespace',
    () async {
      final dir = await Directory.systemTemp.createTemp('first_meeting_test');
      addTearDown(() => dir.delete(recursive: true));
      final auth = File('${dir.path}/auth.json');
      await auth.writeAsString('real account untouched');
      final storage = FirstMeetingFileStorage(directory: () async => dir);
      expect(await storage.read(), isNull);
      await storage.write('{"draft":1}');
      await storage.write('{"complete":true}');
      expect(await storage.read(), '{"complete":true}');
      expect(
        await File('${dir.path}/${FirstMeetingFileStorage.fileName}.tmp')
            .exists(),
        false,
      );
      await storage.delete();
      expect(await storage.read(), isNull);
      expect(await auth.readAsString(), 'real account untouched');
    },
  );

  test('failed replacement preserves previous contents', () async {
    final dir = await Directory.systemTemp.createTemp('first_meeting_failure');
    addTearDown(() => dir.delete(recursive: true));
    final storage = FirstMeetingFileStorage(directory: () async => dir);
    await storage.write('old profile');
    // A directory at the temporary path deterministically prevents file writing.
    final obstruction = Directory(
      '${dir.path}/${FirstMeetingFileStorage.fileName}.tmp',
    );
    await obstruction.create();
    await expectLater(
      storage.write('new profile'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await storage.read(), 'old profile');
  });
}
