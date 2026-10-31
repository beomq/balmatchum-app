import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

import 'data/first_meeting_file_storage.dart';
import 'domain/first_meeting.dart';
import '../../app/dependencies.dart';
import 'data/bootstrap_profile_repository.dart';
import 'data/profile_repository.dart';

final authenticatedMeetingControllerProvider =
    Provider<FirstMeetingController?>((ref) {
      final account = ref.watch(authenticatedAccountProvider);
      if (account == null) return null;
      final client = ref.watch(clientProvider);
      final deleted = ref.watch(deletedAccountsProvider);
      final controller = FirstMeetingController(
        storage: FirstMeetingFileStorage.forAccount(account),
        // The restore reads the profile out of the home snapshot that the
        // signed-in account already started.
        profileRepository: BootstrapProfileRepository(
          ServerpodProfileRepository(client),
          ref.watch(homeBootstrapProvider)!,
          account,
        ),
        isCurrentAccount: () =>
            client.auth.authInfo?.authUserId.toString() == account &&
            !deleted.contains(account),
      );
      final stopObserving = ref
          .watch(watchSyncServiceProvider)
          ?.observeProfile(account, controller);
      ref.onDispose(() => stopObserving?.call());
      ref.onDispose(controller.dispose);
      return controller;
    });

final firstMeetingStorageProvider = Provider<FirstMeetingStorage>((ref) {
  return FirstMeetingFileStorage.device();
});

final firstMeetingControllerProvider = Provider<FirstMeetingController>((ref) {
  final controller = FirstMeetingController(
    storage: ref.watch(firstMeetingStorageProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
