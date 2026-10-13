import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/first_meeting_file_storage.dart';
import 'domain/first_meeting.dart';

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
