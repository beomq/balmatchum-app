import 'dart:convert';

import 'package:balmatchum_client/balmatchum_client.dart' show RecordReceipt;
import 'package:flutter/services.dart';

import 'watch_contract.dart';

class WatchContext {
  const WatchContext(
    this.contextId,
    this.boundaryRevision,
    this.displayRevision,
  );

  final String contextId;
  final int boundaryRevision;
  final int displayRevision;
}

enum DailyStepsStatus {
  available,
  capabilityUnavailable,
  unavailable,
  providerUpdateRequired,
  permissionDenied,
  empty,
  error,
}

class DailyStepsResult {
  const DailyStepsResult(this.status, this.dailySteps);

  final DailyStepsStatus status;
  final JsonObject? dailySteps;
}

/// Only native owns durable context mappings, revision watermarks and the inbox.
class WatchBridge {
  WatchBridge({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('com.beomq.balmatchum/watch'),
      _events =
          events ?? const EventChannel('com.beomq.balmatchum/watch/events');

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<void> get inboxChanges => _events
      .receiveBroadcastStream()
      .where((event) => event == 'inboxChanged')
      .map((_) {});

  Future<WatchContext> activateContext(String accountId) async {
    final result = await _methods.invokeMapMethod<String, Object?>(
      'activateContext',
      {'accountId': accountId},
    );
    final context = result?['contextId'];
    final boundary = result?['boundaryRevision'];
    final revision = result?['latestDisplayRevision'];
    if (context is! String ||
        context.isEmpty ||
        boundary is! int ||
        boundary < 0 ||
        revision is! int ||
        revision < 0) {
      throw const FormatException('Invalid native context');
    }
    return WatchContext(context, boundary, revision);
  }

  Future<void> clearContext() => _methods.invokeMethod<void>('clearContext');

  Future<void> publishDisplaySnapshot(DisplaySnapshot snapshot) =>
      _methods.invokeMethod<void>(
        'publishDisplaySnapshot',
        jsonEncode(snapshot.toJson()),
      );

  Future<List<GpsRecord>> listPendingRecords() async {
    final records = await _methods.invokeListMethod<String>(
      'listPendingRecords',
    );
    if (records == null) throw const FormatException('Missing native inbox');
    return records.map((value) {
      final json = jsonDecode(value);
      if (json is! JsonObject) {
        throw const FormatException('Invalid GPS envelope');
      }
      return GpsRecord.fromJson(json);
    }).toList();
  }

  Future<void> acknowledgeServerReceipt(
    String contextId,
    RecordReceipt receipt,
  ) => _methods.invokeMethod<void>('acknowledgeServerReceipt', {
    'contextId': contextId,
    'clientRecordId': receipt.clientRecordId.toString(),
    'recordId': receipt.recordId.toString(),
    'persistedAt': receipt.persistedAt.toUtc().toIso8601String(),
    'schemaVersion': receipt.schemaVersion,
  });

  Future<DailyStepsResult> requestDailySteps() async {
    final result = await _methods.invokeMapMethod<String, Object?>(
      'requestDailySteps',
    );
    final status = DailyStepsStatus.values
        .where((value) => value.name == result?['status'])
        .firstOrNull;
    if (status == null) {
      throw const FormatException('Invalid daily steps status');
    }
    final value = result?['dailySteps'];
    if (status != DailyStepsStatus.available) {
      if (value != null) {
        throw const FormatException('Unavailable steps contain data');
      }
      return DailyStepsResult(status, null);
    }
    if (value is! Map) throw const FormatException('Missing daily steps');
    final steps = Map<String, Object?>.from(value);
    // Reuse the unchanged v1 validator, including null versus zero semantics.
    final snapshot = DisplaySnapshot.fromJson({
      'schemaVersion': 1,
      'contextId': 'validation',
      'revision': 0,
      'authState': 'authenticated',
      'selectedDog': null,
      'dailySteps': steps,
    });
    return DailyStepsResult(
      status,
      snapshot.toJson()['dailySteps']! as JsonObject,
    );
  }
}
