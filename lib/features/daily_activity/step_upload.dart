import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:path_provider/path_provider.dart';

import '../watch_sync/watch_bridge.dart';

/// Serialized by the owning product controller. The pending payload is durable
/// before upload, so a lost reply replays the same generation and revision.
class StepUpload {
  StepUpload(this.client, this.accountId);
  final Client client;
  final String accountId;

  Future<DailyRecord?> submit(DailyStepsResult observation) async {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/steps-$accountId.json');
    var state = <String, dynamic>{};
    if (await file.exists()) {
      state = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
    Future<void> persist() async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(state), flush: true);
      await temp.rename(file.path);
    }

    if (state['generation'] == null) {
      if (state['registration'] == null) {
        state['registration'] = Uuid().v4();
        state['expectedGeneration'] =
            (await client.product.getWallet()).streamGeneration;
        await persist();
      }
      state['generation'] = await client.product.registerStepStream(
        state['registration'] as String,
        state['expectedGeneration'] as int,
      );
      state['revision'] = 0;
      await persist();
    }
    if (state['pending'] != null) {
      try {
        await client.product.submitSteps(
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
    final currentDay = await client.product.getDay(date);
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
      result = await client.product.submitSteps(input);
    } on ProductException catch (error) {
      if (error.code != 'dayDeleted') rethrow;
      state.remove('pending');
      await persist();
      return client.product.getDay(date);
    }
    state.remove('pending');
    await persist();
    return result;
  }
}
