/// Provider grants are independent of the application's server session.
class AccountProviderRevocation {
  AccountProviderRevocation({
    this.unlinkKakao,
    this.disconnectGoogle,
    this.timeout = const Duration(seconds: 10),
  });

  final Future<void> Function()? unlinkKakao;
  final Future<void> Function()? disconnectGoogle;
  final Duration timeout;

  Future<bool> revoke() async {
    var complete = true;
    for (final revoke in [unlinkKakao, disconnectGoogle]) {
      if (revoke == null) continue;
      try {
        await revoke().timeout(timeout);
      } on Exception {
        // An external provider must not prevent committed account deletion.
        // Report incomplete disconnection without exposing SDK/token errors.
        complete = false;
      }
    }
    return complete;
  }
}
