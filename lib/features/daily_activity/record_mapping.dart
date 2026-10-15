import 'package:balmatchum_client/balmatchum_client.dart' as api;

import '../records/records_models.dart';

RecordDay recordDay(api.DailyRecord value) => RecordDay(
  date: DateTime.parse(value.date),
  revision: value.revision,
  steps: value.steps,
  availability: value.deleted
      ? StepAvailability.deleted
      : value.availability == 'confirmed'
      ? StepAvailability.confirmed
      : StepAvailability.unavailable,
  rewardStatus: switch (value.rewardStatus) {
    'pending' => DayRewardStatus.pending,
    'eligible' => DayRewardStatus.claimable,
    'settled' => DayRewardStatus.paid,
    'expired' => DayRewardStatus.expired,
    'canceled' => DayRewardStatus.canceled,
    'policyUnconfigured' => DayRewardStatus.unconfigured,
    _ => throw const FormatException('Unknown reward status'),
  },
  claimablePoints: value.claimablePoints,
  grantedPoints: value.grantedPoints,
  fixtureLabel: value.fixtureLabel,
  routes: [
    for (final route in value.routes)
      RouteSegment(
        id: route.recordId.toString(),
        source: route.source,
        points: [
          for (final point in route.points)
            RoutePointView(
              recordedAt: point.recordedAt,
              latitude: point.latitude,
              longitude: point.longitude,
            ),
        ],
      ),
  ],
);
