import 'package:balmatchum_app/app/duo_rail.dart';
import 'package:balmatchum_app/features/first_meeting/domain/dog_catalog.dart';
import 'package:balmatchum_app/features/quiz/quiz_screen.dart';
import 'package:balmatchum_app/features/records/records_models.dart';
import 'package:balmatchum_app/features/records/records_screen.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_screen.dart';
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
      useDuoViewport(tester, viewport.key);
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
      useDuoViewport(tester, viewport.key);
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
      useDuoViewport(tester, viewport.key);
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

    testWidgets('wardrobe set purchase fits Duo ${viewport.key}', (
      tester,
    ) async {
      // Given the winter set offered at its set price.
      useDuoViewport(tester, viewport.key);
      await tester.pumpWidget(duoHost(screen(load: () async => snap())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // When the set's purchase dialog opens.
      final action = find.byKey(const ValueKey('wardrobe_set_action_winter'));
      // The list builds lazily; a short landscape pane has not built it yet.
      await tester.scrollUntilVisible(
        action,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('wardrobe_scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      // Then the confirmation is on screen without overflow or exceptions.
      final confirm = find.byKey(const ValueKey('wardrobe_purchase_confirm'));
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('Duo side rail', () {
    final screens = <(String, Widget Function(VoidCallback, VoidCallback))>[
      (
        'calendar',
        (back, home) => RecordsCalendarScreen(
          initialMonth: date,
          loadMonth: (month) async => RecordMonth(month: month, days: [day()]),
          onOpenDay: (_) {},
          onBack: back,
          onHome: home,
        ),
      ),
      (
        'day detail',
        (back, home) => RecordDayScreen(
          date: date,
          loadDay: (_) async => day(),
          deleteDay: (_) async => throw StateError('no delete'),
          claimDay: (_) async => throw StateError('no claim'),
          onBack: back,
          onHome: home,
        ),
      ),
      (
        'quiz',
        (back, home) => DailyQuizScreen(
          loadQuiz: () async => quiz,
          submitAnswer: (_, i) async => answered(i),
          onBack: back,
          onHome: home,
        ),
      ),
      (
        'wardrobe',
        (back, home) => WardrobeScreen(
          dog: FirstMeetingCatalog.byId('shih-tzu'),
          loadWardrobe: () async => snap(),
          runAction: (_) async => throw StateError('no action'),
          onBack: back,
          onHome: home,
        ),
      ),
    ];

    for (final (name, build) in screens) {
      testWidgets('$name moves back and home to the outer portrait rail', (
        tester,
      ) async {
        // Given the measured outer portrait insets.
        useDuoViewport(tester, 'outer portrait');
        final taps = <String>[];
        // When the screen is shown.
        await tester.pumpWidget(
          duoHost(build(() => taps.add('back'), () => taps.add('home'))),
        );
        await tester.pumpAndSettle();
        // Then the top bar is gone and the rail closes the column bottom.
        expect(find.byKey(const ValueKey('product_back')), findsNothing);
        expect(find.byKey(const ValueKey('product_home')), findsNothing);
        final back = find.byKey(const ValueKey('duo_rail_back'));
        final home = find.byKey(const ValueKey('duo_rail_home'));
        expect(tester.getRect(back).center.dx, closeTo(418, 1));
        expect(tester.getRect(back).top, closeTo(542, 1));
        expect(tester.getRect(home).bottom, closeTo(642, 1));
        await tester.tap(back);
        await tester.tap(home);
        expect(taps, ['back', 'home']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name keeps its top bar on a normal iPhone', (tester) async {
        // Given an ordinary iPhone portrait safe area.
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390, 844) * 3;
        tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
        addTearDown(tester.view.reset);
        // When the screen is shown.
        await tester.pumpWidget(duoHost(build(() {}, () {})));
        await tester.pumpAndSettle();
        // Then no rail is drawn and the top bar stays reachable.
        expect(find.byType(DuoRail), findsNothing);
        expect(
          find.byKey(const ValueKey('product_back')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('product_home')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
