import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/first_meeting_state.dart';

/// Account drafts and the separate dev experience use distinct file namespaces.
class FirstMeetingFileStorage implements FirstMeetingStorage {
  FirstMeetingFileStorage({required this.directory, String? accountId})
    : _fileName = accountId == null
          ? fileName
          : 'first_meeting_${Uri.encodeComponent(accountId)}_v1.json';

  factory FirstMeetingFileStorage.device() =>
      FirstMeetingFileStorage(directory: getApplicationSupportDirectory);

  factory FirstMeetingFileStorage.forAccount(String accountId) =>
      FirstMeetingFileStorage(
        directory: getApplicationSupportDirectory,
        accountId: accountId,
      );

  static const fileName = 'dev_first_meeting_v1.json';
  final String _fileName;
  final Future<Directory> Function() directory;

  Future<File> _file() async {
    final resolvedDirectory = await directory();
    return File('${resolvedDirectory.path}/$_fileName');
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
