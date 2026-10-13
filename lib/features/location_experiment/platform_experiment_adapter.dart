import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'location_experiment.dart';

class PluginExperimentSensor implements ExperimentSensor {
  final Battery _battery = Battery();
  @override
  Future<Map<String, Object?>> permission({required bool request}) async {
    var permission = await Geolocator.checkPermission();
    if (request && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return {
      'permission': permission.name,
      'serviceEnabled': await Geolocator.isLocationServiceEnabled(),
      'accuracyAuthorization': await Geolocator.getLocationAccuracy().then(
        (v) => v.name,
      ),
      'source': 'geolocator platform permission',
      'notificationPermission': Platform.isAndroid
          ? 'notChecked; native operator verification required'
          : 'notApplicable',
    };
  }

  @override
  Future<Map<String, Object?>> battery() async => {
    'level': await _battery.batteryLevel,
    'state': (await _battery.batteryState).name,
    'saveMode': await _battery.isInBatterySaveMode,
    'source': 'battery_plus OS percentage; not energy measurement',
    'readAt': DateTime.now().toUtc().toIso8601String(),
  };

  @override
  Stream<String> get chargingChanges =>
      _battery.onBatteryStateChanged.map((s) => s.name);
  @override
  Stream<String> get serviceChanges =>
      Geolocator.getServiceStatusStream().map((s) => s.name);
  @override
  Stream<ExperimentFix> positions(ExperimentInput input) {
    final accuracy = LocationAccuracy.values.byName(input.accuracy);
    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: input.distanceMeters,
        intervalDuration: Duration(seconds: input.intervalSeconds),
        foregroundNotificationConfig: input.background
            ? const ForegroundNotificationConfig(
                notificationTitle: '발맞춤 개발 위치 실험',
                notificationText: '진단 실험이 로컬 위치를 기록하고 있습니다',
                enableWakeLock: false,
              )
            : null,
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: accuracy,
        distanceFilter: input.distanceMeters,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: input.pauseAutomatically,
        allowBackgroundLocationUpdates: input.background,
        showBackgroundLocationIndicator: input.background,
      );
    } else {
      throw UnsupportedError('Phone experiment supports Android/iOS only');
    }
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => ExperimentFix(
        p.timestamp,
        p.latitude,
        p.longitude,
        p.accuracy,
        mocked: p.isMocked,
      ),
    );
  }
}

/// Atomic replace; corrupt journals fail closed, never silently reset history.
class FileExperimentStore implements ExperimentStore {
  FileExperimentStore(this.file);
  final File file;
  static Future<FileExperimentStore> create() async {
    final directory = await getApplicationSupportDirectory();
    return FileExperimentStore(
      File('${directory.path}/location-experiment.json'),
    );
  }

  @override
  Future<Map<String, Object?>?> load() async {
    if (!await file.exists()) return null;
    return (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
  }

  @override
  Future<void> save(Map<String, Object?> journal) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(journal), flush: true);
    await temporary.rename(file.path);
  }
}
