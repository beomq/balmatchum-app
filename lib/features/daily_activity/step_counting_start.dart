import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The instant this install began counting steps. On the install day only
/// steps after it count, so a fresh install does not open with the morning's
/// walk already credited. Later days are whole days (the readers clamp the
/// instant to today's Seoul midnight).
class StepCountingStart {
  StepCountingStart({required this.directory, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  factory StepCountingStart.device() =>
      StepCountingStart(directory: getApplicationSupportDirectory);

  static const fileName = 'step_counting_start_v1.json';
  final Future<Directory> Function() directory;
  final DateTime Function() _now;
  Future<DateTime?>? _value;

  /// Null for an install that already uploaded steps before this rule
  /// existed, so an app update never shrinks a day already being counted.
  Future<DateTime?> read() => _value ??= _read();

  Future<DateTime?> _read() async {
    final resolved = await directory();
    final file = File('${resolved.path}/$fileName');
    if (await file.exists()) {
      final since = jsonDecode(await file.readAsString())['since'] as String?;
      return since == null ? null : DateTime.parse(since);
    }
    final upgraded =
        await resolved.exists() &&
        await resolved.list().any(
          (entry) =>
              entry is File &&
              RegExp(r'/steps-[^/]+\.json$').hasMatch(entry.path),
        );
    final since = upgraded ? null : _now().toUtc();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'since': since?.toIso8601String()}),
      flush: true,
    );
    await temporary.rename(file.path);
    return since;
  }
}
