import 'package:balmatchum_client/balmatchum_client.dart';

abstract interface class ProfileRepository {
  Future<ProfileView?> getProfile();
  Future<ProfileView> createProfile(ProfileInput input, String requestId);
  Future<ProfileView> renameDog(String name, String requestId, int revision);
  Future<ProfileView> updateGoal(int goal, String requestId, int revision);
}

class ServerpodProfileRepository implements ProfileRepository {
  ServerpodProfileRepository(this.client);
  final Client client;

  @override
  Future<ProfileView?> getProfile() => client.profile.getProfile();
  @override
  Future<ProfileView> createProfile(ProfileInput input, String requestId) =>
      client.profile.createProfile(input, requestId);
  @override
  Future<ProfileView> renameDog(String name, String requestId, int revision) =>
      client.profile.renameDog(name, requestId, revision);
  @override
  Future<ProfileView> updateGoal(int goal, String requestId, int revision) =>
      client.profile.updateGoal(goal, requestId, revision);
}
