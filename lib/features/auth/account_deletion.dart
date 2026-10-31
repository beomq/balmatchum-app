import 'package:balmatchum_client/balmatchum_client.dart';

/// Keep credentials and local records when the server result is uncertain.
/// A successful server deletion is followed by local cleanup, then sign-out.
class AccountDeletion {
  AccountDeletion({
    required this.deleteRemote,
    required this.clearLocal,
    required this.signOut,
    required this.markPending,
    required this.clearPending,
    required this.wasRemoteDeleted,
    required this.markRemoteDeleted,
    required this.revokeProviders,
    required this.forgetAccount,
  });

  final Future<void> Function() deleteRemote;
  final Future<void> Function() clearLocal;
  final Future<void> Function() signOut;
  final Future<void> Function() markPending;
  final Future<void> Function() clearPending;
  final Future<bool> Function() wasRemoteDeleted;
  final Future<void> Function() markRemoteDeleted;
  final Future<void> Function() revokeProviders;

  /// Drops the deleted account's pooled client and home snapshot and stops
  /// its late responses; runs before any step that can fail afterwards.
  final void Function() forgetAccount;
  bool _remoteDeleted = false;
  bool _busy = false;

  Future<void> delete() async {
    if (_busy) return;
    _busy = true;
    try {
      await markPending();
      _remoteDeleted = _remoteDeleted || await wasRemoteDeleted();
      if (!_remoteDeleted) {
        try {
          await deleteRemote();
        } on ServerpodClientUnauthorized {
          // A revoked session does not prove deletion. Clear this device only
          // and retain the error so the caller never reports remote success.
          await clearLocal();
          await signOut();
          await clearPending();
          rethrow;
        }
        _remoteDeleted = true;
        forgetAccount();
        await markRemoteDeleted();
      } else {
        forgetAccount();
      }
      try {
        await revokeProviders();
      } finally {
        // The account no longer exists remotely; never leave this device
        // signed in because a provider SDK threw.
        await clearLocal();
        await signOut();
        await clearPending();
      }
    } finally {
      _busy = false;
    }
  }
}
