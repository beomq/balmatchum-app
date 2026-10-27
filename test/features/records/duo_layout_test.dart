import 'package:balmatchum_app/features/quiz/quiz_screen.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import '../quiz/quiz_screen_test.dart' show quiz, answered;
import '../wardrobe/wardrobe_screen_test.dart' show screen, snap;
import 'records_screen_test.dart' show date, day, dayScreen;

void main() {
  for (final viewport in duoViewports.entries) {
    testWidgets('calendar fits Duo ${viewport.key}', (tester) async {
      // Given a month with the existing confirmed step record fixture.
      useDuoViewport(tester, viewport.value);
      // When the month is rendered.
      await tester.pumpWidget(
        duoHost(
          RecordsCalendarScreen(
            initialMonth: date,
            loadMonth: (month) async =>
                RecordMonth(month: month, days: [day()]),
            onOpenDay: (_) {},
            onBack: () {},
            onHome: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Then the stored day is reachable without overflow.
      final entry = find.byKey(const ValueKey('records_day_4'));
      await tester.ensureVisible(entry);
      expect(entry.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('day detail and steps fit Duo ${viewport.key}', (tester) async {
      // Given a confirmed day with claimable steps and rewards.
      useDuoViewport(tester, viewport.value);
      // When the day detail screen loads.
      await tester.pumpWidget(duoHost(dayScreen(load: (_) async => day())));
      await tester.pumpAndSettle();
      // Then steps render and the bottom action stays reachable.
      expect(find.text('4,200걸음'), findsOneWidget);
      final remove = find.byKey(const ValueKey('records_delete_day'));
      await tester.ensureVisible(remove);
      expect(remove.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('quiz fits Duo ${viewport.key}', (tester) async {
      // Given the existing question fixture.
      useDuoViewport(tester, viewport.value);
      // When the daily quiz is rendered.
      await tester.pumpWidget(
        duoHost(
          DailyQuizScreen(
            loadQuiz: () async => quiz,
            submitAnswer: (_, i) async => answered(i),
            onBack: () {},
            onHome: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Then choices and submit remain reachable.
      final choice = find.byKey(const ValueKey('quiz_choice_1'));
      await tester.ensureVisible(choice);
      expect(choice.hitTestable(), findsOneWidget);
      final submit = find.byKey(const ValueKey('quiz_submit'));
      await tester.ensureVisible(submit);
      expect(submit.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wardrobe theme purchase fits Duo ${viewport.key}', (
      tester,
    ) async {
      // Given the existing owned and offered wardrobe fixtures.
      useDuoViewport(tester, viewport.value);
      await tester.pumpWidget(duoHost(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // When the store's theme purchase dialog opens.
      final store = find.byKey(const ValueKey('wardrobe_scope_store'));
      await tester.ensureVisible(store);
      await tester.tap(store);
      await tester.pumpAndSettle();
      final theme = find.byKey(const ValueKey('wardrobe_theme_night'));
      await tester.ensureVisible(theme);
      await tester.tap(theme);
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('wardrobe_action'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      // Then the confirmation is on screen without overflow or exceptions.
      final confirm = find.byKey(const ValueKey('wardrobe_purchase_confirm'));
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
