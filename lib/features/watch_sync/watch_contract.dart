import 'dart:convert';

typedef JsonObject = Map<String, Object?>;

enum AckStage { transferQueued, phoneReceived, serverSaved }

/// Validated v1 wire messages. Asset keys remain opaque, not executable paths.
class WatchMessage {
  WatchMessage._(this._encoded);

  final String _encoded;
  JsonObject toJson() => jsonDecode(_encoded) as JsonObject;
  String get contextId => toJson()['contextId']! as String;

  static JsonObject _base(JsonObject input) {
    final json = jsonDecode(jsonEncode(input)) as JsonObject;
    if (json['schemaVersion'] != 1 || json['schemaVersion'] is! int) {
      throw const FormatException('Unsupported schemaVersion');
    }
    _text(json, 'contextId');
    return json;
  }
}

class DisplaySnapshot extends WatchMessage {
  DisplaySnapshot._(super.encoded) : super._();

  factory DisplaySnapshot.fromJson(JsonObject input) {
    final json = WatchMessage._base(input);
    _integer(json, 'revision');
    if (!['authenticated', 'signedOut'].contains(json['authState'])) {
      throw const FormatException('Invalid authState');
    }
    for (final key in ['selectedDog', 'dailySteps']) {
      if (!json.containsKey(key)) throw FormatException('Missing $key');
    }
    if (json['selectedDog'] != null) {
      final dog = _object(json['selectedDog']);
      for (final key in ['dogId', 'displayName', 'assetKey']) {
        _text(dog, key);
      }
    }
    if (json['dailySteps'] != null) {
      final steps = _object(json['dailySteps']);
      final date = _text(steps, 'date');
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date ||
          steps['timeZone'] != 'Asia/Seoul') {
        throw const FormatException('Invalid daily date/timeZone');
      }
      _integer(steps, 'count');
      _utc(steps, 'observedAt');
    }
    if (json['authState'] == 'signedOut' &&
        (json['selectedDog'] != null || json['dailySteps'] != null)) {
      throw const FormatException('Signed out snapshot contains display data');
    }
    return DisplaySnapshot._(jsonEncode(json));
  }

  int get revision => toJson()['revision']! as int;
  bool get signedOut => toJson()['authState'] == 'signedOut';
}

class GpsRecord extends WatchMessage {
  GpsRecord._(super.encoded) : super._();

  factory GpsRecord.fromJson(JsonObject input) {
    final json = WatchMessage._base(input);
    _recordId(json);
    if (json['kind'] != 'gpsRecord') {
      throw const FormatException('Invalid kind');
    }
    final start = _utc(json, 'startedAt');
    final end = _utc(json, 'endedAt');
    if (end.isBefore(start)) throw const FormatException('Invalid interval');
    final payload = _object(json['payload']);
    final points = payload['points'];
    if (points is! List) throw const FormatException('Invalid points');
    DateTime? previous;
    for (final value in points) {
      final point = _object(value);
      _number(point, 'latitude', -90, 90);
      _number(point, 'longitude', -180, 180);
      _number(point, 'horizontalAccuracyMeters', 0, double.maxFinite);
      final recordedAt = _utc(point, 'recordedAt');
      if (recordedAt.isBefore(start) ||
          recordedAt.isAfter(end) ||
          (previous != null && recordedAt.isBefore(previous))) {
        throw const FormatException('Invalid point interval/order');
      }
      previous = recordedAt;
    }
    return GpsRecord._(jsonEncode(json));
  }
}

class RecordAcknowledgement extends WatchMessage {
  RecordAcknowledgement._(super.encoded) : super._();

  factory RecordAcknowledgement.fromJson(JsonObject input) {
    final json = WatchMessage._base(input);
    _recordId(json);
    if (!AckStage.values.any((stage) => stage.name == json['stage'])) {
      throw const FormatException('Invalid ack stage');
    }
    if (json.containsKey('errorCode')) _text(json, 'errorCode');
    return RecordAcknowledgement._(jsonEncode(json));
  }

  String get recordId => toJson()['recordId']! as String;
  AckStage get stage => AckStage.values.byName(toJson()['stage']! as String);
}

/// The authenticated iPhone boundary must explicitly call activateContext.
/// Receiving a message cannot establish authentication or switch accounts.
class WatchContractState {
  String? _activeContext;
  int? _revision;
  DisplaySnapshot? _display;
  final Map<String, AckStage> _acknowledgements = {};

  DisplaySnapshot? get display => _display;

  void activateContext(String contextId) {
    if (contextId.isEmpty) throw const FormatException('Empty contextId');
    if (_activeContext == contextId) return;
    clearContext();
    _activeContext = contextId;
  }

  void clearContext() {
    _activeContext = null;
    _revision = null;
    _display = null;
    _acknowledgements.clear();
  }

  bool acceptSnapshot(DisplaySnapshot snapshot) {
    if (snapshot.contextId != _activeContext ||
        (_revision != null && snapshot.revision <= _revision!)) {
      return false;
    }
    if (snapshot.signedOut) {
      clearContext();
    } else {
      _revision = snapshot.revision;
      _display = snapshot;
    }
    return true;
  }

  AckStage? acknowledgementFor(String recordId) => _acknowledgements[recordId];

  bool acceptAcknowledgement(RecordAcknowledgement ack) {
    if (ack.contextId != _activeContext ||
        ack.toJson().containsKey('errorCode'))
      return false;
    final previous = _acknowledgements[ack.recordId];
    if (previous != null && ack.stage.index < previous.index) return false;
    _acknowledgements[ack.recordId] = ack.stage;
    return true;
  }
}

JsonObject _object(Object? value) {
  if (value is! JsonObject) throw const FormatException('Expected object');
  return value;
}

String _text(JsonObject json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('Invalid $key');
  return value;
}

void _integer(JsonObject json, String key) {
  final value = json[key];
  if (value is! int || value < 0) throw FormatException('Invalid $key');
}

DateTime _utc(JsonObject json, String key) {
  final value = _text(json, key);
  final parsed = DateTime.tryParse(value);
  if (!value.endsWith('Z') ||
      parsed == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
          .hasMatch(value) ||
      parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    throw FormatException('Invalid UTC $key');
  }
  return parsed;
}

void _recordId(JsonObject json) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(_text(json, 'recordId'))) {
    throw const FormatException('Invalid recordId');
  }
}

void _number(JsonObject json, String key, double min, double max) {
  final value = json[key];
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw FormatException('Invalid $key');
  }
}
