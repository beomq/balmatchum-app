import 'dart:async';

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/settings/account_deletion_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _confirm = ValueKey('account_deletion_confirm');
const _cancel = ValueKey('account_deletion_cancel');
const _lock = ValueKey('account_deletion_lock');

/// Settings with the final confirmation pushed over it, as the router does.
Future<void> openDeletion(
  WidgetTester tester,
  Future<void> Function() onDelete, {
  List<String>? moves,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: meetingTheme(),
      home: Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AccountDeletionScreen(
                onDelete: onDelete,
                onBack: () {
                  moves?.add('back');
                  Navigator.of(context).pop();
                },
                onHome: () {
                  moves?.add('home');
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ),
          child: const SizedBox.square(dimension: 48),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

bool locked(WidgetTester tester) =>
    tester.widget<AbsorbPointer>(find.byKey(_lock)).absorbing;

void main() {
  testWidgets('permanent deletion is the one red confirmation', (tester) async {
    await openDeletion(tester, () async {});
    final confirm = find.byKey(_confirm);
    // The painted fill, after the theme's primary-strong default (guide 3.3).
    final fill = tester.widget<Material>(
      find.descendant(of: confirm, matching: find.byType(Material)),
    );
    expect(fill.color, MeetingColors.error);
    expect(find.byType(FilledButton), findsOneWidget);
    // The release notices stay on the page (launch plan 33).
    expect(
      find.byKey(const ValueKey('account_deletion_records')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('account_deletion_subscription')),
      findsOneWidget,
    );
  });

  testWidgets('entering, cancel, back, home and system back delete nothing', (
    tester,
  ) async {
    var calls = 0;
    final moves = <String>[];
    Future<void> delete() async => calls++;
    for (final leave in ['cancel', 'product_back', 'product_home', 'system']) {
      await openDeletion(tester, delete, moves: moves);
      expect(find.byType(AccountDeletionScreen), findsOneWidget);
      if (leave == 'system') {
        await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      } else {
        await tester.tap(
          find.byKey(leave == 'cancel' ? _cancel : ValueKey(leave)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsNothing, reason: leave);
    }
    expect(calls, 0);
    expect(moves, ['back', 'back', 'home']);
  });

  testWidgets('one confirm sends one request and locks until it answers', (
    tester,
  ) async {
    final release = Completer<void>();
    var calls = 0;
    await openDeletion(tester, () async {
      calls++;
      await release.future;
    });
    final confirm = find.byKey(_confirm);
    // A second tap in the same frame and taps while pending send nothing.
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(locked(tester), isTrue);
    expect(
      find.byKey(const ValueKey('account_deletion_progress')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_cancel)).onPressed,
      isNull,
    );
    // Neither the system back nor the top bar leaves while it runs.
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.tap(
      find.byKey(const ValueKey('product_back')),
      warnIfMissed: false,
    );
    // The progress bar runs until the request answers, so pump frames.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AccountDeletionScreen), findsOneWidget);
    release.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(locked(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed deletion stays with its notice and can run again', (
    tester,
  ) async {
    var calls = 0;
    await openDeletion(tester, () async {
      calls++;
      throw Exception('offline');
    });
    await tester.tap(find.byKey(_confirm));
    await tester.pumpAndSettle();
    // No success is assumed: the page stays, unlocked, with the notice.
    expect(
      find.byKey(const ValueKey('account_deletion_failed')),
      findsOneWidget,
    );
    expect(find.byType(AccountDeletionScreen), findsOneWidget);
    expect(locked(tester), isFalse);
    await tester.tap(find.byKey(_confirm));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
