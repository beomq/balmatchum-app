import 'dart:async';

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/main.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('request only starts on tap and disables duplicate requests', (
    tester,
  ) async {
    final response = Completer<Greeting>();
    final names = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          greetingCheckProvider.overrideWithValue((name) {
            names.add(name);
            return response.future;
          }),
        ],
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    expect(names, isEmpty);

    final button = find.byKey(const ValueKey('bootstrap_check_connection'));
    await tester.tap(button);
    await tester.pump();
    expect(names, ['Balmatchum']);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(names, hasLength(1));

    response.complete(
      Greeting(
        message: 'server response',
        author: 'Serverpod',
        timestamp: DateTime.utc(2026),
      ),
    );
    await tester.pumpAndSettle();
    final result = tester.widget<Text>(
      find.byKey(const ValueKey('bootstrap_connection_success')),
    );
    expect(result.data, 'server response');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('failure is visible and a new explicit tap can retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          greetingCheckProvider.overrideWithValue((name) async {
            calls++;
            if (calls == 1) throw Exception('offline');
            return Greeting(
              message: name,
              author: 'test',
              timestamp: DateTime.utc(2026),
            );
          }),
        ],
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('bootstrap_check_connection'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bootstrap_connection_error')),
      findsOneWidget,
    );
    expect(calls, 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.byKey(const ValueKey('bootstrap_connection_error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bootstrap_connection_success')),
      findsOneWidget,
    );
  });

  testWidgets('missing server configuration disables check', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [greetingCheckProvider.overrideWithValue(null)],
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('bootstrap_check_connection')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'in-flight completion after removal does not update disposed UI',
    (tester) async {
      final response = Completer<Greeting>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            greetingCheckProvider.overrideWithValue((_) => response.future),
          ],
          child: const AppBootstrap(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('bootstrap_check_connection')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      response.completeError(Exception('disconnected'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
