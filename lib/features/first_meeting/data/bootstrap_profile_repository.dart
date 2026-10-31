import 'package:balmatchum_client/balmatchum_client.dart';

import '../../daily_activity/home_bootstrap.dart';
import 'profile_repository.dart';

/// Restores the profile from the home snapshot started at sign-in instead of
/// a round trip of its own. Only the first read uses the snapshot; later
/// reads and every change go to [server].
class BootstrapProfileRepository implements ProfileRepository {
  BootstrapProfileRepository(this.server, this.bootstrap, this.account);
  final ProfileRepository server;
  final HomeBootstrap bootstrap;
  final String account;
  bool _used = false;

  @override
  Future<ProfileView?> getProfile() async {
    final snapshot = _used ? null : bootstrap.peek(account);
    _used = true;
    if (snapshot == null) return server.getProfile();
    try {
      return (await snapshot).profile;
    } on Exception {
      // The home refresh reports the failed snapshot itself; the profile
      // still asks the server once.
      return server.getProfile();
    }
  }

  // A profile change makes the started snapshot stale (it carries the old
  // profile), so the first home refresh reads a new one.
  @override
  Future<ProfileView> createProfile(ProfileInput input, String requestId) {
    bootstrap.discard();
    return server.createProfile(input, requestId);
  }

  @override
  Future<ProfileView> renameDog(String name, String requestId, int revision) {
    bootstrap.discard();
    return server.renameDog(name, requestId, revision);
  }

  @override
  Future<ProfileView> updateGoal(int goal, String requestId, int revision) {
    bootstrap.discard();
    return server.updateGoal(goal, requestId, revision);
  }
}
