import 'dart:async';

import 'package:flutter/foundation.dart';

abstract interface class ExperimentClock {
  DateTime get utc;
  int get elapsedMicros;
}

class StopwatchExperimentClock implements ExperimentClock {
  final _watch = Stopwatch()..start();
  @override
  DateTime get utc => DateTime.now().toUtc();
  @override
  int get elapsedMicros => _watch.elapsedMicroseconds;
}

class ExperimentInput {
  ExperimentInput({
    required this.intervalSeconds,
    required this.distanceMeters,
    required this.accuracy,
    required this.background,
    required this.pauseAutomatically,
    required this.scenario,
  }) {
    if (intervalSeconds <= 0 ||
        distanceMeters < 0 ||
        scenario.trim().isEmpty ||
        !['low', 'medium', 'high', 'best'].contains(accuracy)) {
      throw ArgumentError('Invalid experiment inputs');
    }
  }
  final int intervalSeconds;
  final int distanceMeters;
  final String accuracy;
  final bool background;
  final bool pauseAutomatically;
  final String scenario;
  Map<String, Object?> toJson() => {
    'intervalSeconds': intervalSeconds,
    'distanceMeters': distanceMeters,
    'accuracy': accuracy,
    'background': background,
    'pauseAutomatically': pauseAutomatically,
    'scenario': scenario,
  };
}

class ExperimentFix {
  const ExperimentFix(
    this.utc,
    this.latitude,
    this.longitude,
    this.accuracy, {
    required this.mocked,
  });
  final DateTime utc;
  final double latitude, longitude, accuracy;
  final bool mocked;
}

abstract interface class ExperimentSensor {
  Future<Map<String, Object?>> permission({required bool request});
  Future<Map<String, Object?>> battery();
  Stream<ExperimentFix> positions(ExperimentInput input);
  Stream<String> get serviceChanges;
  Stream<String> get chargingChanges;
}

abstract interface class ExperimentStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> journal);
}

/// No account, uploader or product collection policy belongs in this harness.
class LocationExperiment extends ChangeNotifier {
  LocationExperiment({
    required this.clock,
    required this.sensor,
    required this.store,
    Map<String, Object?> provenance = const {'source': 'unknown'},
  }) : provenance = Map<String, Object?>.of(provenance);
  final ExperimentClock clock;
  final ExperimentSensor sensor;
  final ExperimentStore store;
  final Map<String, Object?> provenance;
  Map<String, Object?> journal = {'schemaVersion': 1, 'runs': <Object?>[]};
  Map<String, Object?>? _run;
  int _origin = 0;
  Future<void> _pending = Future.value();
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? error;
  bool get running => _run != null;
  List<Object?> get runs => journal['runs']! as List<Object?>;

  Future<void> _serial(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object e) async {
      error = e.toString();
      _run = null;
      await _cancel();
      notifyListeners();
    });
    return result;
  }

  Future<void> get settled => _pending;

  Future<void> initialize() => _serial(() async {
    journal = await store.load() ?? journal;
    if (journal['schemaVersion'] != 1 || journal['runs'] is! List) {
      throw const FormatException('Unsupported experiment journal');
    }
    for (final value in runs) {
      final run = value as Map<String, Object?>;
      if (run['status'] == 'running') {
        run['status'] = 'interrupted';
        (run['events'] as List).add({
          'kind': 'restartInterruption',
          'utc': clock.utc.toIso8601String(),
          'elapsedMicros': null,
          'provenance': 'new process; duration unknown',
        });
      }
    }
    await store.save(journal);
    notifyListeners();
  });

  Future<void> start(ExperimentInput input) => _serial(() async {
    if (running) throw StateError('Experiment already running');
    error = null;
    _origin = clock.elapsedMicros;
    _run = {
      'experimentId': '${clock.utc.microsecondsSinceEpoch}-${runs.length}',
      'provenance': Map<String, Object?>.of(provenance),
      'startedAt': clock.utc.toIso8601String(),
      'status': 'running',
      'input': input.toJson(),
      'samples': <Object?>[],
      'events': <Object?>[],
    };
    runs.add(_run);
    _event('start', {'battery': await _battery()});
    final access = await sensor.permission(request: true);
    _event('permission', access);
    if (!_allowed(access)) {
      await _finish('permissionDenied');
      return;
    }
    await store.save(journal);
    _subscriptions.add(
      sensor
          .positions(input)
          .listen(
            (fix) {
              unawaited(
                _serial(() async {
                  if (!running) return;
                  final permission = await sensor.permission(request: false);
                  if (!_allowed(permission)) {
                    _event('permissionRevoked', permission);
                    await _finish('permissionRevoked');
                    return;
                  }
                  if (!fix.latitude.isFinite ||
                      fix.latitude.abs() > 90 ||
                      !fix.longitude.isFinite ||
                      fix.longitude.abs() > 180 ||
                      !fix.accuracy.isFinite ||
                      fix.accuracy < 0) {
                    _event('invalidFix', {});
                  } else {
                    (_run!['samples'] as List).add({
                      'sequence': (_run!['samples'] as List).length,
                      'recordedAt': fix.utc.toUtc().toIso8601String(),
                      'receivedAt': clock.utc.toIso8601String(),
                      'elapsedMicros': clock.elapsedMicros - _origin,
                      'latitude': fix.latitude,
                      'longitude': fix.longitude,
                      'horizontalAccuracyMeters': fix.accuracy,
                      'mocked': fix.mocked,
                      'permission': permission,
                      'battery': await _battery(),
                    });
                  }
                  await store.save(journal);
                  notifyListeners();
                }).catchError((Object _) {}),
              );
            },
            onError: (Object e) {
              unawaited(
                stop(
                  'sensorError',
                  detail: e.toString(),
                ).catchError((Object _) {}),
              );
            },
            onDone: () {
              unawaited(stop('streamEnded').catchError((Object _) {}));
            },
          ),
    );
    _subscriptions.add(
      sensor.serviceChanges.listen((value) {
        unawaited(
          annotate('locationService', {
            'value': value,
          }).catchError((Object _) {}),
        );
      }),
    );
    _subscriptions.add(
      sensor.chargingChanges.listen((value) {
        unawaited(
          annotate('charging', {
            'value': value,
            'source': 'battery_plus state stream',
          }).catchError((Object _) {}),
        );
      }),
    );
    notifyListeners();
  });

  Future<Map<String, Object?>> _battery() async {
    try {
      return await sensor.battery();
    } catch (e) {
      return {'level': null, 'state': 'unknown', 'error': e.toString()};
    }
  }

  bool _allowed(Map<String, Object?> p) =>
      p['serviceEnabled'] == true &&
      (p['permission'] == 'always' || p['permission'] == 'whileInUse');

  void _event(String kind, Map<String, Object?> data) {
    (_run!['events'] as List).add({
      'kind': kind,
      'utc': clock.utc.toIso8601String(),
      'elapsedMicros': clock.elapsedMicros - _origin,
      ...data,
    });
  }

  Future<void> annotate(String kind, Map<String, Object?> data) =>
      _serial(() async {
        if (!running) return;
        _event(kind, data);
        if (kind == 'locationService' && data['value'] == 'disabled') {
          await _finish('locationServiceDisabled');
          return;
        }
        if (kind == 'checkpoint') {
          _event('batteryCheckpoint', {'battery': await _battery()});
        }
        if (kind == 'lifecycle' && data['state'] == 'resumed') {
          final access = await sensor.permission(request: false);
          _event('permission', access);
          if (!_allowed(access)) {
            await _finish('permissionRevoked');
            return;
          }
        }
        await store.save(journal);
        notifyListeners();
      });

  Future<void> stop(String reason, {String? detail}) => _serial(() async {
    if (!running) return;
    if (detail != null) _event('sensorError', {'detail': detail});
    await _finish(reason);
  });

  Future<void> _finish(String reason) async {
    await _cancel();
    _event('end', {'reason': reason, 'battery': await _battery()});
    _run!['status'] = reason;
    _run!['elapsedMicros'] = clock.elapsedMicros - _origin;
    await store.save(journal);
    _run = null;
    notifyListeners();
  }

  Future<void> _cancel() async {
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  /// Includes leading/trailing silence. Threshold is an experiment input only;
  /// distance filters and iOS scheduling mean gaps are not proof of lost fixes.
  static Map<String, Object?> metrics(Map<String, Object?> run) {
    final samples = run['samples'] as List;
    final interval =
        ((run['input'] as Map)['intervalSeconds'] as int) * 1000000;
    final end = run['elapsedMicros'] as int?;
    final points = [
      0,
      ...samples.map((e) => (e as Map)['elapsedMicros'] as int),
    ];
    if (end != null) points.add(end);
    var maxGap = 0;
    var gapCount = 0;
    for (var i = 1; i < points.length; i++) {
      final gap = points[i] - points[i - 1];
      if (gap > maxGap) maxGap = gap;
      if (gap > interval) gapCount++;
    }
    final events = (run['events'] as List).cast<Map>();
    final batteries = [
      ...events
          .where((e) => e['battery'] is Map)
          .map((e) => e['battery'] as Map),
      ...samples
          .where((e) => (e as Map)['battery'] is Map)
          .map((e) => (e as Map)['battery'] as Map),
    ];
    final startBattery =
        events.where((e) => e['kind'] == 'start').firstOrNull?['battery']
            as Map?;
    final endBattery =
        events.where((e) => e['kind'] == 'end').firstOrNull?['battery'] as Map?;
    final startLevel = startBattery?['level'] as int?;
    final endLevel = endBattery?['level'] as int?;
    final dischargeOnly =
        batteries.isNotEmpty &&
        batteries.every((e) => e['state'] == 'discharging') &&
        events
            .where((e) => e['kind'] == 'charging')
            .every((e) => e['value'] == 'discharging');
    return {
      'sampleCount': samples.length,
      'maxObservedGapMicros': maxGap,
      'gapsOverInputInterval': gapCount,
      'elapsedMicros': end,
      'tailKnown': end != null,
      'batteryPercentagePointDrop': startLevel != null && endLevel != null
          ? startLevel - endLevel
          : null,
      'observedDischargeOnly': dischargeOnly,
      'batteryProvenance': 'OS percentage; charging unknown/transitions confound; not energy attribution',
    };
  }
}
