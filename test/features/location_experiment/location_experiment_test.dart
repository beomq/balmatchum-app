import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/location_experiment/location_experiment.dart';
import 'package:balmatchum_app/features/location_experiment/location_experiment_screen.dart';
import 'package:balmatchum_app/features/location_experiment/platform_experiment_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Clock implements ExperimentClock {
  int micros = 0;
  DateTime time = DateTime.utc(2026, 10, 13);
  @override
  int get elapsedMicros => micros;
  @override
  DateTime get utc => time;
}

class Store implements ExperimentStore {
  Map<String, Object?>? data;
  bool fail = false;
  @override
  Future<Map<String, Object?>?> load() async => data;
  @override
  Future<void> save(Map<String, Object?> journal) async {
    if (fail) throw FileSystemException('disk unavailable');
    data = (jsonDecode(jsonEncode(journal)) as Map).cast<String, Object?>();
  }
}

class Sensor implements ExperimentSensor {
  String access = 'whileInUse', state = 'discharging';
  int level = 90;
  final fixes = StreamController<ExperimentFix>.broadcast(sync: true);
  final charging = StreamController<String>.broadcast(sync: true);
  final services = StreamController<String>.broadcast(sync: true);
  @override
  Future<Map<String, Object?>> permission({required bool request}) async => {
    'permission': access,
    'serviceEnabled': true,
  };
  @override
  Future<Map<String, Object?>> battery() async => {
    'level': level,
    'state': state,
    'source': 'test',
  };
  @override
  Stream<ExperimentFix> positions(ExperimentInput input) => fixes.stream;
  @override
  Stream<String> get serviceChanges => services.stream;
  @override
  Stream<String> get chargingChanges => charging.stream;
}

void main() {
  late Clock clock;
  late Store store;
  late Sensor sensor;
  late LocationExperiment experiment;
  final input = ExperimentInput(
    intervalSeconds: 5,
    distanceMeters: 0,
    accuracy: 'high',
    background: true,
    pauseAutomatically: false,
    scenario: 'stationary',
  );
  setUp(() {
    clock = Clock();
    store = Store();
    sensor = Sensor();
    experiment = LocationExperiment(clock: clock, sensor: sensor, store: store);
  });
  tearDown(() async {
    await experiment.stop('testEnd');
    await sensor.fixes.close();
    await sensor.charging.close();
    await sensor.services.close();
    experiment.dispose();
  });
  test(
    'monotonic gaps survive wall clock rollback and persist local coordinates',
    () async {
      await experiment.initialize();
      await experiment.start(input);
      clock.micros = 2000000;
      sensor.fixes.add(ExperimentFix(clock.utc, 37, 127, 8, mocked: false));
      await experiment.settled;
      clock.time = DateTime.utc(2020);
      clock.micros = 12000000;
      sensor.fixes.add(ExperimentFix(clock.utc, 37.1, 127.1, 10, mocked: true));
      await experiment.settled;
      clock.micros = 20000000;
      sensor.level = 87;
      await experiment.stop('operatorStopped');
      final run = (store.data!['runs'] as List).single as Map<String, Object?>;
      final metrics = LocationExperiment.metrics(run);
      expect(metrics['elapsedMicros'], 20000000);
      expect(metrics['maxObservedGapMicros'], 10000000);
      expect(metrics['gapsOverInputInterval'], 2);
      expect(metrics['batteryPercentagePointDrop'], 3);
      expect(metrics['observedDischargeOnly'], true);
      expect((run['samples'] as List).first['latitude'], 37);
    },
  );
  test('denied and deniedForever never subscribe', () async {
    for (final denied in ['denied', 'deniedForever']) {
      sensor.access = denied;
      await experiment.start(input);
      expect(experiment.running, false);
      expect(sensor.fixes.hasListener, false);
      expect((experiment.runs.last as Map)['status'], 'permissionDenied');
    }
  });
  test('each run preserves explicit provenance and sample sequence', () async {
    experiment.provenance.addAll({
      'source': 'simulator',
      'device': 'test device',
      'appBuild': 'test build',
    });
    await experiment.start(input);
    sensor.fixes.add(ExperimentFix(clock.utc, 37, 127, 5, mocked: true));
    await experiment.settled;
    await experiment.stop('operatorStopped');
    final first = experiment.runs.first as Map;
    final id = first['experimentId'];
    expect((first['samples'] as List).first['sequence'], 0);
    experiment.provenance['source'] = 'physical';
    await experiment.start(input);
    expect((first['provenance'] as Map)['source'], 'simulator');
    expect((experiment.runs.last as Map)['experimentId'], isNot(id));
    expect((experiment.runs.last as Map)['provenance']['source'], 'physical');
  });
  test(
    'resume detects revoked permission and preserves lifecycle/offline events',
    () async {
      await experiment.start(input);
      await experiment.annotate('lifecycle', {'state': 'paused'});
      await experiment.annotate('offline', {
        'value': true,
        'source': 'operator',
      });
      sensor.access = 'denied';
      await experiment.annotate('lifecycle', {'state': 'resumed'});
      expect(experiment.running, false);
      final run = experiment.runs.single as Map;
      expect(run['status'], 'permissionRevoked');
      expect(
        (run['events'] as List).where((e) => e['kind'] == 'offline'),
        hasLength(1),
      );
    },
  );
  test(
    'sample-time revocation rejects the coordinate and ends stream',
    () async {
      await experiment.start(input);
      sensor.access = 'deniedForever';
      sensor.fixes.add(ExperimentFix(clock.utc, 0, 0, 1, mocked: false));
      await experiment.settled;
      expect((experiment.runs.single as Map)['samples'], isEmpty);
      expect(experiment.running, false);
    },
  );
  test(
    'restart marks interrupted with unknown tail rather than joining clocks',
    () async {
      await experiment.start(input);
      final restarted = LocationExperiment(
        clock: Clock(),
        sensor: Sensor(),
        store: store,
      );
      await restarted.initialize();
      final run = restarted.runs.single as Map<String, Object?>;
      expect(run['status'], 'interrupted');
      expect(LocationExperiment.metrics(run)['tailKnown'], false);
      expect((run['events'] as List).last['elapsedMicros'], isNull);
      expect(restarted.running, false);
      restarted.dispose();
    },
  );
  test(
    'charging provenance invalidates discharge-only interpretation',
    () async {
      await experiment.start(input);
      sensor.state = 'charging';
      sensor.charging.add('charging');
      await experiment.settled;
      await experiment.stop('operatorStopped');
      expect(
        LocationExperiment.metrics(
          experiment.runs.single as Map<String, Object?>,
        )['observedDischargeOnly'],
        false,
      );
    },
  );
  test('stream error records interruption and cancels subscriptions', () async {
    await experiment.start(input);
    sensor.fixes.addError(StateError('permission removed'));
    await experiment.settled;
    expect((experiment.runs.single as Map)['status'], 'sensorError');
    expect(sensor.fixes.hasListener, false);
  });
  test('failed persistence stops collection and reports failure', () async {
    await experiment.start(input);
    store.fail = true;
    await expectLater(
      experiment.annotate('checkpoint', {}),
      throwsA(isA<FileSystemException>()),
    );
    await experiment.settled;
    expect(experiment.running, false);
    expect(experiment.error, contains('disk unavailable'));
    expect(sensor.fixes.hasListener, false);
  });
  test('service disabled stops and no-fix duration remains a gap', () async {
    await experiment.start(input);
    clock.micros = 9000000;
    sensor.services.add('disabled');
    await experiment.settled;
    final run = experiment.runs.single as Map<String, Object?>;
    expect(run['status'], 'locationServiceDisabled');
    expect(LocationExperiment.metrics(run)['maxObservedGapMicros'], 9000000);
    expect(LocationExperiment.metrics(run)['sampleCount'], 0);
  });
  test('invalid fixes stay events and checkpoint includes battery', () async {
    await experiment.start(input);
    sensor.fixes.add(ExperimentFix(clock.utc, double.nan, 0, 1, mocked: false));
    await experiment.settled;
    await experiment.annotate('checkpoint', {});
    final run = experiment.runs.single as Map;
    expect(run['samples'], isEmpty);
    expect(
      (run['events'] as List).where((e) => e['kind'] == 'invalidFix'),
      hasLength(1),
    );
    expect((run['events'] as List).last['battery']['level'], 90);
  });
  test(
    'invalid settings rejected rather than adopting production defaults',
    () {
      expect(
        () => ExperimentInput(
          intervalSeconds: 0,
          distanceMeters: 0,
          accuracy: 'high',
          background: false,
          pauseAutomatically: false,
          scenario: 'test',
        ),
        throwsArgumentError,
      );
    },
  );
  test('file store round trip and corrupt file fail closed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'location-experiment-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.json');
    final disk = FileExperimentStore(file);
    expect(await disk.load(), isNull);
    await disk.save({'schemaVersion': 1, 'runs': []});
    expect((await disk.load())!['schemaVersion'], 1);
    await file.writeAsString('broken');
    await expectLater(disk.load(), throwsFormatException);
  });
  testWidgets('non-dev build gate creates no diagnostic or plugins', (
    tester,
  ) async {
    expect(phoneLocationExperimentEnabled, false);
    await tester.pumpWidget(
      const MaterialApp(home: PhoneLocationExperimentScreen()),
    );
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
