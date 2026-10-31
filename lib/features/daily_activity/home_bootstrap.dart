import 'package:balmatchum_client/balmatchum_client.dart' as api;

/// Holds the one home snapshot started as soon as the signed-in account is
/// known, so the first home refresh uses it instead of a second round trip.
/// It is handed out once; every later refresh reads the server itself.
class HomeBootstrap {
  String? _account;
  Future<api.HomeSnapshot>? _snapshot;

  /// Starts [read] once for [account]. Another account discards the earlier
  /// snapshot first; the same account never starts a second one.
  void start(String account, Future<api.HomeSnapshot> Function() read) {
    if (_account == account) return;
    _account = account;
    final snapshot = read();
    // A snapshot nobody takes must not surface as an unhandled error; the
    // refresh that takes it still sees the failure.
    snapshot.ignore();
    _snapshot = snapshot;
  }

  /// The started snapshot for [account] the first time it is asked for;
  /// null once taken, for another account or after [discard].
  Future<api.HomeSnapshot>? take(String account) {
    if (_account != account) return null;
    final snapshot = _snapshot;
    _snapshot = null;
    return snapshot;
  }

  /// The started snapshot for [account] without taking it, so the profile
  /// restore reads the same snapshot the first home refresh then takes.
  Future<api.HomeSnapshot>? peek(String account) =>
      _account == account ? _snapshot : null;

  /// Drops the snapshot on sign-out, account change or account deletion.
  void discard() {
    _account = null;
    _snapshot = null;
  }
}
