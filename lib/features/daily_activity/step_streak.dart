import 'package:balmatchum_client/balmatchum_client.dart' as api;

import 'product_repository.dart';

/// The home's recent-record summary. Owner decision ① (2026-10-28): a streak
/// counts consecutive KST days that hold a step record, whether or not the
/// goal was reached.
class StepStreak {
  const StepStreak({
    required this.days,
    required this.atLeast,
    required this.thisWeek,
  });

  /// KST days read in one request. The server answers at most 93 days per
  /// `listDays`; one month keeps the read the size of the records calendar.
  static const window = 31;

  /// Consecutive recorded days ending today, or ending yesterday while today
  /// has no record yet (today is not over).
  final int days;

  /// The run reaches the first day of the window, so the real streak can be
  /// longer than [days]; shown as "n일 이상", never as an exact number.
  final bool atLeast;

  /// Recorded days in this Monday-first week, up to today.
  final int thisWeek;

  /// Summarises [records] read for the [window] days ending [today], a KST
  /// date like [ProductRepository.today].
  static StepStreak of(Iterable<api.DailyRecord> records, DateTime today) {
    final recorded = {
      for (final record in records)
        if (hasStepRecord(record)) record.date,
    };
    bool has(DateTime day) => recorded.contains(ProductRepository.dateKey(day));
    final last = DateTime.utc(today.year, today.month, today.day);
    final first = last.subtract(const Duration(days: window - 1));
    var day = has(last) ? last : last.subtract(const Duration(days: 1));
    var days = 0;
    while (!day.isBefore(first) && has(day)) {
      days++;
      day = day.subtract(const Duration(days: 1));
    }
    var week = 0;
    for (
      var d = last.subtract(Duration(days: last.weekday - 1));
      !d.isAfter(last);
      d = d.add(const Duration(days: 1))
    ) {
      if (has(d)) week++;
    }
    return StepStreak(
      days: days,
      atLeast: days > 0 && day.isBefore(first),
      thisWeek: week,
    );
  }
}

/// A day the server confirmed with at least one step. Deleted days, days the
/// device could not confirm and confirmed zero-step days break a streak.
bool hasStepRecord(api.DailyRecord record) =>
    !record.deleted &&
    record.availability == 'confirmed' &&
    (record.steps ?? 0) > 0;
