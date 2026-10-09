import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/watch_sync/watch_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  JsonObject fixture(String key) {
    final root = jsonDecode(
      File('test/features/watch_sync/fixtures/v1.json').readAsStringSync(),
    ) as JsonObject;
    return root[key]! as JsonObject;
  }

  test('shared v1 wire objects round trip without changing fields', () {
    expect(
      DisplaySnapshot.fromJson(fixture('snapshot')).toJson(),
      fixture('snapshot'),
    );
    expect(GpsRecord.fromJson(fixture('record')).toJson(), fixture('record'));
    expect(
      RecordAcknowledgement.fromJson(fixture('ack')).toJson(),
      fixture('ack'),
    );
  });

  test('null is distinct from zero steps and asset keys remain opaque', () {
    final json = fixture('snapshot');
    final snapshot = DisplaySnapshot.fromJson(json);
    (json['dailySteps']! as JsonObject)['count'] = 99;
    expect((snapshot.toJson()['dailySteps']! as JsonObject)['count'], 0);
    json['selectedDog'] = null;
    json['dailySteps'] = null;
    expect(DisplaySnapshot.fromJson(json).toJson()['dailySteps'], isNull);
    json['selectedDog'] = {
      'dogId': 'id',
      'displayName': 'dog',
      'assetKey': 'future-key',
    };
    expect(
      DisplaySnapshot.fromJson(json).toJson()['selectedDog'],
      json['selectedDog'],
    );
  });

  test('rejects unsupported schema, invalid types, dates and timezone', () {
    for (final value in [0, 2, '1', 1.0]) {
      expect(
        () => DisplaySnapshot.fromJson(
          fixture('snapshot')..['schemaVersion'] = value,
        ),
        throwsFormatException,
      );
    }
    for (final value in [-1, 1.5, '2']) {
      expect(
        () =>
            DisplaySnapshot.fromJson(fixture('snapshot')..['revision'] = value),
        throwsFormatException,
      );
    }
    for (final update in [
      {'date': '2026-02-30'},
      {'timeZone': 'UTC'},
      {'count': -1},
      {'count': '0'},
      {'observedAt': '2026-10-09T01:02:03+09:00'},
      {'observedAt': '2026-02-30T01:02:03Z'},
    ]) {
      final json = fixture('snapshot');
      (json['dailySteps']! as JsonObject).addAll(update);
      expect(() => DisplaySnapshot.fromJson(json), throwsFormatException);
    }
  });

  test('validates GPS boundaries and timestamps without sensor policy', () {
    for (final update in [
      {'latitude': 91},
      {'longitude': -181},
      {'horizontalAccuracyMeters': -1},
      {'latitude': '37'},
      {'recordedAt': 'invalid'},
      {'recordedAt': '2026-10-09T00:59:59Z'},
      {'recordedAt': '2026-10-09T01:02:01Z'},
    ]) {
      final json = fixture('record');
      final points = (json['payload']! as JsonObject)['points']! as List;
      (points.first as JsonObject).addAll(update);
      expect(() => GpsRecord.fromJson(json), throwsFormatException);
    }
    expect(
      () => GpsRecord.fromJson(
        fixture('record')..['endedAt'] = '2026-10-09T00:00:00Z',
      ),
      throwsFormatException,
    );
    expect(
      () => GpsRecord.fromJson(fixture('record')..['recordId'] = 'not-uuid'),
      throwsFormatException,
    );
    expect(
      () => GpsRecord.fromJson(
        fixture('record')..['recordId'] = '12345678-1234-1234-1234-123456789abc',
      ),
      throwsFormatException,
    );
  });

  test('GPS point order is nondecreasing within the record interval', () {
    final json = fixture('record');
    final points = (json['payload']! as JsonObject)['points']! as List;
    points.add({...points.first as JsonObject});
    expect(() => GpsRecord.fromJson(json), returnsNormally);
    (points.last as JsonObject)['recordedAt'] = '2026-10-09T01:00:30Z';
    expect(() => GpsRecord.fromJson(json), throwsFormatException);
  });

  test('context requires explicit activation; revisions cannot regress', () {
    final state = WatchContractState();
    final snapshot = DisplaySnapshot.fromJson(fixture('snapshot'));
    expect(state.acceptSnapshot(snapshot), isFalse);
    state.activateContext('test-context-a');
    expect(state.acceptSnapshot(snapshot), isTrue);
    expect(state.acceptSnapshot(snapshot), isFalse);
    expect(
      state.acceptSnapshot(
        DisplaySnapshot.fromJson(fixture('snapshot')..['revision'] = 1),
      ),
      isFalse,
    );
    expect(
      state.acceptSnapshot(
        DisplaySnapshot.fromJson(
          fixture('snapshot')
            ..['contextId'] = 'arbitrary'
            ..['revision'] = 99,
        ),
      ),
      isFalse,
    );
    expect(state.display, same(snapshot));
    state.activateContext('test-context-a');
    expect(state.acceptSnapshot(snapshot), isFalse);
    state.activateContext('test-context-b');
    expect(state.display, isNull);
    expect(state.acceptSnapshot(snapshot), isFalse);
  });

  test('signed out clears state and does not adopt a following context', () {
    expect(
      () => DisplaySnapshot.fromJson(
        fixture('snapshot')..['authState'] = 'signedOut',
      ),
      throwsFormatException,
    );
    final state = WatchContractState()..activateContext('test-context-a');
    state.acceptSnapshot(DisplaySnapshot.fromJson(fixture('snapshot')));
    final json = fixture('snapshot')
      ..['revision'] = 3
      ..['authState'] = 'signedOut'
      ..['selectedDog'] = null
      ..['dailySteps'] = null;
    expect(state.acceptSnapshot(DisplaySnapshot.fromJson(json)), isTrue);
    expect(state.display, isNull);
    expect(
      state.acceptSnapshot(
        DisplaySnapshot.fromJson(fixture('snapshot')..['revision'] = 4),
      ),
      isFalse,
    );
  });

  test(
    'acknowledgements advance only within the active context and record',
    () {
      final state = WatchContractState();
      final ack = RecordAcknowledgement.fromJson(fixture('ack'));
      expect(state.acceptAcknowledgement(ack), isFalse);
      state.activateContext(ack.contextId);
      expect(
        state.acceptAcknowledgement(
          RecordAcknowledgement.fromJson(
            fixture('ack')
              ..['stage'] = 'serverSaved'
              ..['errorCode'] = 'storageFailed',
          ),
        ),
        isFalse,
      );
      expect(state.acknowledgementFor(ack.recordId), isNull);
      expect(state.acceptAcknowledgement(ack), isTrue);
      expect(state.acceptAcknowledgement(ack), isTrue);
      expect(
        state.acceptAcknowledgement(
          RecordAcknowledgement.fromJson(
            fixture('ack')..['stage'] = 'transferQueued',
          ),
        ),
        isFalse,
      );
      expect(state.acknowledgementFor(ack.recordId), AckStage.phoneReceived);
      expect(
        state.acceptAcknowledgement(
          RecordAcknowledgement.fromJson(
            fixture('ack')..['stage'] = 'serverSaved',
          ),
        ),
        isTrue,
      );
      final other = fixture('ack')
        ..['recordId'] = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
        ..['stage'] = 'transferQueued';
      expect(
        state.acceptAcknowledgement(RecordAcknowledgement.fromJson(other)),
        isTrue,
      );
      expect(state.acknowledgementFor(ack.recordId), AckStage.serverSaved);
      expect(
        state.acceptAcknowledgement(
          RecordAcknowledgement.fromJson(
            fixture('ack')..['contextId'] = 'other',
          ),
        ),
        isFalse,
      );
      state.activateContext('other');
      expect(state.acknowledgementFor(ack.recordId), isNull);
      expect(
        () => RecordAcknowledgement.fromJson(
          fixture('ack')..['stage'] = 'completed',
        ),
        throwsFormatException,
      );
    },
  );
}
