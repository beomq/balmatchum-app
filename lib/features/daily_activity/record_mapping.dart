import 'package:balmatchum_client/balmatchum_client.dart' as api;

import '../records/records_models.dart';

RecordDay recordDay(api.DailyRecord value, {bool rewardsEnabled = true}) =>
    RecordDay(
      date: DateTime.parse(value.date),
      revision: value.revision,
      steps: value.steps,
      availability: value.deleted
          ? StepAvailability.deleted
          : value.availability == 'confirmed'
          ? StepAvailability.confirmed
          : StepAvailability.unavailable,
      rewardStatus: !rewardsEnabled
          ? DayRewardStatus.unconfigured
          : switch (value.rewardStatus) {
              'pending' => DayRewardStatus.pending,
              'eligible' => DayRewardStatus.claimable,
              'settled' => DayRewardStatus.paid,
              'expired' => DayRewardStatus.expired,
              'adRequired' => DayRewardStatus.adRequired,
              'futureDate' => DayRewardStatus.futureDate,
              'legacyPolicyExcluded' => DayRewardStatus.legacyPolicyExcluded,
              'canceled' => DayRewardStatus.canceled,
              'policyUnconfigured' => DayRewardStatus.unconfigured,
              _ => throw const FormatException('Unknown reward status'),
            },
      claimablePoints: rewardsEnabled ? value.claimablePoints : null,
      adClaimablePoints: rewardsEnabled ? value.adClaimablePoints : null,
      policyVersion: value.policyVersion,
      gracePolicyStatus: value.gracePolicyStatus,
      grantedPoints: rewardsEnabled ? value.grantedPoints : 0,
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
