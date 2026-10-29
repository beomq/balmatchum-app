import 'package:balmatchum_app/features/daily_activity/record_mapping.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'product_controller_test.dart' show record;

void main() {
  test('a date no snapshot reached is no record, not an unknown count', () {
    // `listDays` answers every date; an untouched one keeps revision 0.
    final untouched = record().copyWith(
      availability: 'unknown',
      steps: null,
      stepRevision: 0,
      rewardStatus: 'pending',
    );
    expect(recordDay(untouched).availability, StepAvailability.none);
    for (final availability in [
      'unknown',
      'permissionUnavailable',
      'pendingSync',
      'queryFailed',
    ]) {
      final sent = untouched.copyWith(
        availability: availability,
        stepRevision: 2,
      );
      expect(
        recordDay(sent).availability,
        StepAvailability.unavailable,
        reason: availability,
      );
    }
    expect(recordDay(record()).availability, StepAvailability.confirmed);
    expect(
      recordDay(record(deleted: true)).availability,
      StepAvailability.deleted,
    );
  });
}
