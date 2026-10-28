import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/step_streak.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'product_controller_test.dart'
    show AccountRepository, accountController, record;

/// The record [ago] days before [today].
DailyRecord day(
  DateTime today,
  int ago, {
  int? steps = 4000,
  String availability = 'confirmed',
  bool deleted = false,
}) => record().copyWith(
  date: ProductRepository.dateKey(today.subtract(Duration(days: ago))),
  steps: steps,
  availability: availability,
  deleted: deleted,
);

void main() {
  // A Wednesday; its week starts on Monday 2026-10-26.
  final wednesday = DateTime.utc(2026, 10, 28);

  test('a streak counts recorded days through today', () {
    final streak = StepStreak.of([
      for (var i = 0; i < 6; i++) day(wednesday, i),
    ], wednesday);
    expect(streak.days, 6);
    expect(streak.atLeast, isFalse);
  });

  test('today without a record yet keeps the run that ended yesterday', () {
    final streak = StepStreak.of([
      for (var i = 1; i < 4; i++) day(wednesday, i),
    ], wednesday);
    expect(streak.days, 3);
  });

  test('a missing, zero, unconfirmed or deleted day breaks the run', () {
    for (final breaker in [
      null,
      day(wednesday, 2, steps: 0),
      day(wednesday, 2, steps: null, availability: 'unavailable'),
      day(wednesday, 2, deleted: true),
    ]) {
      final streak = StepStreak.of([
        day(wednesday, 0),
        day(wednesday, 1),
        ?breaker,
        day(wednesday, 3),
      ], wednesday);
      expect(streak.days, 2, reason: '$breaker');
    }
  });

  test('a run crosses month and year ends', () {
    final november = DateTime.utc(2026, 11, 2);
    expect(
      StepStreak.of([
        for (var i = 0; i < 4; i++) day(november, i),
      ], november).days,
      4,
    );
    final newYear = DateTime.utc(2027, 1, 2);
    expect(
      StepStreak.of([
        for (var i = 0; i < 5; i++) day(newYear, i),
      ], newYear).days,
      5,
    );
  });

  test('a run that fills the read window is only a lower bound', () {
    final full = StepStreak.of([
      for (var i = 0; i < StepStreak.window; i++) day(wednesday, i),
    ], wednesday);
    expect(full.days, StepStreak.window);
    expect(full.atLeast, isTrue);
    // Ending yesterday, the run also reaches the window's first day.
    final yesterday = StepStreak.of([
      for (var i = 1; i < StepStreak.window; i++) day(wednesday, i),
    ], wednesday);
    expect(yesterday.days, StepStreak.window - 1);
    expect(yesterday.atLeast, isTrue);
    final short = StepStreak.of([
      for (var i = 0; i < StepStreak.window - 1; i++) day(wednesday, i),
    ], wednesday);
    expect(short.atLeast, isFalse);
  });

  test('this week counts recorded days from Monday through today', () {
    final streak = StepStreak.of([
      day(wednesday, 0),
      day(wednesday, 2),
      day(wednesday, 3),
    ], wednesday);
    // Wednesday and Monday count; the Sunday before belongs to last week.
    expect(streak.thisWeek, 2);
    expect(streak.days, 1);
  });

  test(
    'the controller reads one window ending today; a failure shows none',
    () async {
      final today = ProductRepository.today;
      final repository = AccountRepository()
        ..recentDays = [for (var i = 0; i < 3; i++) day(today, i)];
      final product = accountController(repository);
      await product.loadStreak();
      expect(product.streak!.days, 3);
      final (from, to) = repository.dayRanges.single;
      expect(ProductRepository.dateKey(to), ProductRepository.dateKey(today));
      expect(to.difference(from).inDays, StepStreak.window - 1);
      repository.recentDays = null;
      await product.loadStreak();
      expect(product.streak, isNull);
    },
  );

  test('the month average counts confirmed days of today\'s month only', () {
    final records = [
      day(wednesday, 0, steps: 6000),
      day(wednesday, 1, steps: 0),
      day(wednesday, 2, steps: 9000),
      // No count: never averaged in as 0.
      day(wednesday, 3, steps: null, availability: 'unknown'),
      day(wednesday, 4, deleted: true),
      // September 30, the month before.
      day(wednesday, 28, steps: 30000),
    ];
    expect(monthAverage(records, wednesday), 5000);
    expect(
      monthAverage([
        day(wednesday, 3, steps: null, availability: 'unknown'),
      ], wednesday),
      isNull,
    );
    expect(monthAverage(const [], wednesday), isNull);
  });

  test('the records tiles share the streak read and add the average', () async {
    final today = ProductRepository.today;
    final repository = AccountRepository()
      ..recentDays = [day(today, 0, steps: 3000), day(today, 1, steps: 5000)];
    final product = accountController(repository);
    final summary = await product.loadRecordsSummary();
    expect(summary.streak, 2);
    expect(summary.streakAtLeast, isFalse);
    // Both days fall in today's month unless today is the first.
    expect(summary.monthAverage, today.day == 1 ? 3000 : 4000);
    final (from, to) = repository.dayRanges.single;
    expect(ProductRepository.dateKey(to), ProductRepository.dateKey(today));
    expect(to.difference(from).inDays, StepStreak.window - 1);
    repository.recentDays = null;
    await expectLater(product.loadRecordsSummary(), throwsException);
  });

  test('a deleted day or a disconnect leaves no old streak', () async {
    final today = ProductRepository.today;
    final repository = AccountRepository()..recentDays = [day(today, 0)];
    final product = accountController(repository);
    await product.loadStreak();
    expect(product.streak, isNotNull);
    await product.deleteDay(today);
    expect(product.streak, isNull);
    await product.loadStreak();
    expect(product.streak, isNotNull);
    product.disconnect();
    expect(product.streak, isNull);
    await product.loadStreak();
    expect(product.streak, isNull);
  });
}
