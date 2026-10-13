import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/first_meeting_state.dart';

/// Dev-only local data. Never shares auth, account or server namespaces.
class FirstMeetingFileStorage implements FirstMeetingStorage {
  FirstMeetingFileStorage({required this.directory});

  factory FirstMeetingFileStorage.device() =>
      FirstMeetingFileStorage(directory: getApplicationSupportDirectory);

  static const fileName = 'dev_first_meeting_v1.json';
  final Future<Directory> Function() directory;

  Future<File> _file() async {
    final resolvedDirectory = await directory();
    return File('${resolvedDirectory.path}/$fileName');
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String payload) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }
}
