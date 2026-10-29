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

  /// Any other non-deleted value after a device snapshot: steps are not
  /// known (not the same as 0).
  unavailable,

  /// No step snapshot ever reached the server for the date (step revision 0).
  /// `listDays` returns every date, so this is a day without a record, not
  /// one whose steps could not be confirmed.
  none,

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

/// What a date shows on the calendar and in its detail (guide 7.1-2). Each
/// kind is drawn on its own; none of them stands in for another.
enum RecordDayKind {
  /// Confirmed steps reached the date's confirmed goal.
  achieved,

  /// Confirmed steps below the goal, or a date without a known goal.
  walked,

  /// Confirmed zero steps.
  zero,

  /// A snapshot whose steps were not confirmed; not the same as 0.
  unknown,

  /// No step snapshot for the date.
  none,
  deleted,

  /// After today, where nothing can be recorded yet.
  future,
}

/// The [RecordDayKind] of [day]. [goal] is the date's confirmed goal; only
/// today has one (guide 7.1-5), so other dates are never [achieved].
RecordDayKind recordDayKind(RecordDay? day, {required bool future, int? goal}) {
  if (day != null && day.isDeleted) return RecordDayKind.deleted;
  if (future) return RecordDayKind.future;
  if (day == null) return RecordDayKind.none;
  return switch (day.availability) {
    StepAvailability.deleted => RecordDayKind.deleted,
    StepAvailability.none => RecordDayKind.none,
    StepAvailability.unavailable => RecordDayKind.unknown,
    StepAvailability.confirmed => switch (day.steps) {
      null => RecordDayKind.unknown,
      0 => RecordDayKind.zero,
      final steps when goal != null && steps >= goal => RecordDayKind.achieved,
      _ => RecordDayKind.walked,
    },
  };
}

/// The records page's tiles, read apart from the shown month: one month
/// cannot settle a streak across its edges (guide 7.1-1). Owner decision ①
/// counts a day with a step record.
class RecordsSummary {
  const RecordsSummary({
    required this.thisWeek,
    required this.streak,
    required this.streakAtLeast,
    required this.monthAverage,
  });

  /// Recorded days in this Monday-first KST week, up to today.
  final int thisWeek;

  /// Consecutive recorded days ending today, or yesterday while today has
  /// no record yet.
  final int streak;

  /// The run reaches the first day read, so it may be longer; shown as
  /// "n일 이상".
  final bool streakAtLeast;

  /// Mean steps of this KST month's confirmed days so far, rounded; null
  /// without one.
  final int? monthAverage;
}

/// The quizzes answered on one KST date.
class DayQuiz {
  const DayQuiz({
    required this.answered,
    required this.correct,
    required this.points,
  });

  final int answered;
  final int correct;

  /// Points the server awarded for them.
  final int points;
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
typedef LoadRecordsSummary = Future<RecordsSummary> Function();
typedef LoadDayQuiz = Future<DayQuiz> Function(DateTime date);

/// Deletes the entire KST day (steps, routes, unpaid reward) and returns the
/// server's resulting day. The parent owns request ids.
typedef DeleteRecordDay = Future<RecordDay> Function(DateTime date);

/// Claims a past day's reward; returns the granted amount. The parent uses
/// [RecordDay.revision] as `expectedRevision`.
typedef ClaimRecordDay = Future<int> Function(RecordDay day);

/// Returns a Korean holiday name for a KST date, or null.
typedef HolidayNameOf = String? Function(DateTime date);
