import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import '../watch_sync/watch_bridge.dart';

/// Serialized by the owning product controller. The pending payload is durable
/// before upload, so a lost reply replays the same generation and revision.
class StepUpload {
  StepUpload(
    this.client,
    this.accountId, {
    this.directory = getApplicationSupportDirectory,
  });
  final Client client;
  final String accountId;
  final Future<Directory> Function() directory;

  Future<DailyRecord?> submit(DailyStepsResult observation) async {
    final authentication = client.auth.authInfo;
    void checkAccount() {
      if (!identical(authentication, client.auth.authInfo) ||
          authentication?.authUserId.toString() != accountId) {
        throw StateError('Step upload account changed');
      }
    }

    checkAccount();
    final header = await client.auth.authHeaderValue;
    checkAccount();
    if (header == null || header.isEmpty) {
      throw StateError('Step upload authentication missing');
    }
    final upload = Client(
      client.host,
      connectionTimeout: client.connectionTimeout,
    )..authKeyProvider = _StepAuthHeader(header, checkAccount);
    try {
      return await _submit(observation, upload, checkAccount);
    } finally {
      upload.close();
    }
  }

  Future<DailyRecord?> _submit(
    DailyStepsResult observation,
    Client upload,
    void Function() checkAccount,
  ) async {
    final resolvedDirectory = await directory();
    final file = File('${resolvedDirectory.path}/steps-$accountId.json');
    var state = <String, dynamic>{};
    if (await file.exists()) {
      state = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
    Future<void> persist() async {
      checkAccount();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(state), flush: true);
      await temp.rename(file.path);
    }

    if (state['generation'] == null) {
      if (state['registration'] == null) {
        state['registration'] = Uuid().v4();
        state['expectedGeneration'] =
            (await upload.product.getWallet()).streamGeneration;
        await persist();
      }
      state['generation'] = await upload.product.registerStepStream(
        state['registration'] as String,
        state['expectedGeneration'] as int,
      );
      state['revision'] = 0;
      await persist();
    }
    if (state['pending'] != null) {
      try {
        await upload.product.submitSteps(
          DailyStepInput.fromJson(state['pending'] as Map<String, dynamic>),
        );
      } on ProductException catch (error) {
        if (error.code != 'dayDeleted') rethrow;
      }
      state.remove('pending');
      await persist();
    }
    // Missing HealthKit data must not replace a previously confirmed total.
    final steps = observation.dailySteps;
    if (observation.status != DailyStepsStatus.available || steps == null) {
      return null;
    }
    final date = steps['date']! as String;
    final currentDay = await upload.product.getDay(date);
    if (currentDay.deleted) return currentDay;
    final start = DateTime.parse('${date}T00:00:00Z')
        .subtract(const Duration(hours: 9));
    final input = DailyStepInput(
      date: date,
      streamGeneration: state['generation'] as int,
      revision: (state['revision'] as int) + 1,
      windowStart: start,
      windowEnd: start.add(const Duration(days: 1)),
      observedAt: DateTime.parse(steps['observedAt']! as String),
      total: steps['count']! as int,
      availability: 'confirmed',
    );
    state['revision'] = input.revision;
    state['pending'] = input.toJson();
    await persist();
    DailyRecord result;
    try {
      result = await upload.product.submitSteps(input);
    } on ProductException catch (error) {
      if (error.code != 'dayDeleted') rethrow;
      state.remove('pending');
      await persist();
      return upload.product.getDay(date);
    }
    state.remove('pending');
    await persist();
    return result;
  }
}

class _StepAuthHeader implements ClientAuthKeyProvider {
  _StepAuthHeader(this.header, this.checkAccount);
  final String header;
  final void Function() checkAccount;

  @override
  Future<String?> get authHeaderValue async {
    checkAccount();
    return header;
  }
}
