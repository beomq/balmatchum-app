/// UI view models for the records screens.
///
/// The parent maps generated `balmatchum_client` models (`DailyRecord`,
/// `DayRoute`, `RoutePoint`, `RewardGrant`) into these; they are not wire
/// DTOs. Dates are Korea (KST) calendar dates.
library;

/// Mapped from `DailyRecord.availability`.
enum StepAvailability {
  /// `confirmed` with non-null steps.
  confirmed,

  /// Any other non-deleted value: steps are not known (not the same as 0).
  unavailable,

  /// `deleted`.
  deleted,
}

/// Mapped from `DailyRecord.rewardStatus`; the reward belongs to the whole
/// day, never to an individual GPS route.
enum DayRewardStatus {
  /// `pending`: steps not confirmed yet.
  pending,

  /// `eligible`: [RecordDay.claimablePoints] can be claimed.
  claimable,

  /// `settled`: everything earned was received.
  paid,

  /// `expired`: the free claim window passed.
  expired,

  adRequired,
  futureDate,
  legacyPolicyExcluded,

  /// `canceled`: the day was deleted.
  canceled,

  /// `policyUnconfigured`: reward policy not available on this server.
  unconfigured,
}

class RoutePointView {
  const RoutePointView({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
  });
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
}

/// One server `DayRoute`. Segments are drawn separately; nothing is
/// interpolated between routes.
class RouteSegment {
  const RouteSegment({
    required this.id,
    required this.source,
    required this.points,
  });
  final String id;
  final String source;
  final List<RoutePointView> points;
}

/// One KST day as returned by `getDay`/`listDays`/`deleteDay`.
class RecordDay {
  const RecordDay({
    required this.date,
    required this.revision,
    required this.steps,
    required this.availability,
    required this.rewardStatus,
    this.claimablePoints,
    this.adClaimablePoints,
    this.policyVersion,
    this.gracePolicyStatus,
    this.grantedPoints = 0,
    this.fixtureLabel,
    this.routes = const [],
  });

  final DateTime date;

  /// Passed back as `expectedRevision` by the parent's claim adapter.
  final int revision;
  final int? steps;
  final StepAvailability availability;
  final DayRewardStatus rewardStatus;
  final int? claimablePoints;
  final int? adClaimablePoints;
  final String? policyVersion;
  final String? gracePolicyStatus;
  final int grantedPoints;

  /// Non-null when amounts come from development fixtures.
  final String? fixtureLabel;
  final List<RouteSegment> routes;

  bool get isDeleted => availability == StepAvailability.deleted;
}

class RecordMonth {
  RecordMonth({required DateTime month, required List<RecordDay> days})
    : month = DateTime(month.year, month.month),
      _days = {for (final d in days) d.date.day: d};

  final DateTime month;
  final Map<int, RecordDay> _days;

  RecordDay? day(int day) => _days[day];
}

typedef LoadRecordMonth = Future<RecordMonth> Function(DateTime month);
typedef LoadRecordDay = Future<RecordDay> Function(DateTime date);

/// Deletes the entire KST day (steps, routes, unpaid reward) and returns the
/// server's resulting day. The parent owns request ids.
typedef DeleteRecordDay = Future<RecordDay> Function(DateTime date);

/// Claims a past day's reward; returns the granted amount. The parent uses
/// [RecordDay.revision] as `expectedRevision`.
typedef ClaimRecordDay = Future<int> Function(RecordDay day);

/// Returns a Korean holiday name for a KST date, or null.
typedef HolidayNameOf = String? Function(DateTime date);
