import 'package:balmatchum_app/features/records/product_page.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:balmatchum_app/features/records/status_widgets.dart';
import 'package:balmatchum_app/features/wardrobe/dog_sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'records_screen_test.dart' show date, day, deleted, host;

const dog = 'assets/first_meeting/dogs/pug.png';

RecordDayScreen detail(
  RecordDay value, {
  bool isToday = false,
  int? goal,
  LoadDayQuiz? loadQuiz,
}) => RecordDayScreen(
  date: date,
  isToday: isToday,
  goal: goal,
  loadQuiz: loadQuiz,
  loadDay: (_) async => value,
  deleteDay: (_) async => deleted(),
  claimDay: (_) async => 0,
  dogAsset: dog,
  onBack: () {},
  onHome: () {},
);

GoalRing ring(WidgetTester tester) =>
    tester.widget<GoalRing>(find.byKey(const ValueKey('records_hero_ring')));

String tile(WidgetTester tester, String name) =>
    tester.widget<Text>(find.byKey(ValueKey('records_tile_$name'))).data!;

void main() {
  testWidgets('today past the goal fills an olive ring and names the gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        detail(
          day(steps: 9120, reward: DayRewardStatus.paid, granted: 91),
          isToday: true,
          goal: 8000,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ring(tester).progress, 1);
    expect(ring(tester).color, ProductColors.record);
    final body = find.byKey(const ValueKey('records_hero_body'));
    expect(tester.widget<Text>(body).semanticsLabel, contains('1,120'));
    expect(tile(tester, 'steps'), contains('9,120'));
    expect(tile(tester, 'goal'), contains('8,000'));
    // The server's grant, not a figure worked out from the steps.
    expect(tile(tester, 'points'), '91P');
    expect(
      tester
          .widget<DogSprite>(
            find.descendant(
              of: find.byKey(const ValueKey('records_day_dog')),
              matching: find.byType(DogSprite),
            ),
          )
          .asset,
      dog,
    );
    expect(find.byKey(const ValueKey('records_day_line')), findsOneWidget);
  });

  testWidgets('today below the goal shows its share in the primary ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(detail(day(steps: 6840), isToday: true, goal: 8000)),
    );
    await tester.pumpAndSettle();
    expect(ring(tester).progress, closeTo(.855, .001));
    expect(ring(tester).color, isNot(ProductColors.record));
    final body = find.byKey(const ValueKey('records_hero_body'));
    expect(tester.widget<Text>(body).semanticsLabel, contains('86%'));
  });

  testWidgets('without a confirmed goal or count the ring stays empty', (
    tester,
  ) async {
    for (final (name, value, steps) in [
      ('past', day(steps: 9120), '9,120'),
      ('zero', day(steps: 0, reward: DayRewardStatus.paid), '0'),
      (
        'unknown',
        day(
          steps: null,
          availability: StepAvailability.unavailable,
          reward: DayRewardStatus.pending,
        ),
        null,
      ),
      (
        'none',
        day(
          steps: null,
          availability: StepAvailability.none,
          reward: DayRewardStatus.pending,
        ),
        null,
      ),
    ]) {
      await tester.pumpWidget(
        host(KeyedSubtree(key: ValueKey(name), child: detail(value))),
      );
      await tester.pumpAndSettle();
      expect(ring(tester).progress, isNull, reason: name);
      // A past day's goal is not on record, so it is never "reached".
      expect(tile(tester, 'goal'), isNot(contains(RegExp(r'\d'))));
      if (steps == null) {
        expect(tile(tester, 'steps'), isNot(contains(RegExp(r'\d'))));
      } else {
        expect(tile(tester, 'steps'), contains(steps), reason: name);
      }
      expect(find.byKey(const ValueKey('records_delete_day')), findsOneWidget);
    }
  });

  testWidgets('a future date leaves its tiles empty', (tester) async {
    await tester.pumpWidget(
      host(
        detail(
          day(
            steps: null,
            availability: StepAvailability.none,
            reward: DayRewardStatus.futureDate,
          ),
          loadQuiz: (_) async =>
              const DayQuiz(answered: 0, correct: 0, points: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ring(tester).progress, isNull);
    for (final name in ['steps', 'goal', 'quiz']) {
      expect(tile(tester, name), '–', reason: name);
    }
  });

  testWidgets('the quiz tile follows the date read; points stay apart', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        detail(
          day(reward: DayRewardStatus.paid, granted: 42),
          loadQuiz: (d) async {
            expect(d, date);
            return const DayQuiz(answered: 2, correct: 1, points: 2);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tile(tester, 'quiz'), allOf(contains('1/2'), contains('+2P')));
    expect(tile(tester, 'points'), '42P');
    await tester.pumpWidget(
      host(
        KeyedSubtree(
          key: const ValueKey('failed'),
          child: detail(
            day(reward: DayRewardStatus.paid),
            loadQuiz: (_) async => throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tile(tester, 'quiz'), '–');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a settled day needs no point panel; a claimable one keeps it', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(detail(day(reward: DayRewardStatus.paid, granted: 4))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records_reward_status')), findsNothing);
    await tester.pumpWidget(
      host(KeyedSubtree(key: const ValueKey('open'), child: detail(day()))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records_reward_status')), findsOneWidget);
    expect(find.byKey(const ValueKey('records_claim')), findsOneWidget);
    // Today's points stay on the home.
    await tester.pumpWidget(
      host(
        KeyedSubtree(
          key: const ValueKey('today'),
          child: detail(day(), isToday: true, goal: 8000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records_claim')), findsNothing);
    expect(find.text('오늘 포인트는 홈에서 받기'), findsOneWidget);
  });

  testWidgets('one red text button at the bottom goes through the confirm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(detail(day(reward: DayRewardStatus.paid))));
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey('records_delete_day'));
    expect(tester.widget(delete), isA<TextButton>());
    expect(find.byType(OutlinedButton), findsNothing);
    // The last thing on the page.
    expect(tester.getRect(delete).bottom, greaterThan(844 - 80));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('records_delete_confirm')),
      findsOneWidget,
    );
  });

  testWidgets('a deleted day keeps its explanation and drops the rest', (
    tester,
  ) async {
    await tester.pumpWidget(host(detail(deleted())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('records_deleted')), findsOneWidget);
    expect(find.byKey(const ValueKey('records_day_hero')), findsNothing);
    expect(find.byKey(const ValueKey('records_day_dog')), findsNothing);
    expect(find.byType(StatTile), findsNothing);
    expect(find.byKey(const ValueKey('records_delete_day')), findsNothing);
  });
}
