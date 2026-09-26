import 'dart:async';

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explicit app action receives the real server greeting', (
    tester,
  ) async {
    final completed = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          greetingCheckProvider.overrideWith((ref) {
            final client = ref.watch(clientProvider);
            return (name) async {
              calls++;
              try {
                return await client.greeting.hello(name);
              } finally {
                completed.complete();
              }
            };
          }),
        ],
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('bootstrap_check_connection')),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'Pass --dart-define=SERVER_URL',
    );
    expect(calls, 0);
    expect(
      find.byKey(const ValueKey('bootstrap_connection_success')),
      findsNothing,
    );
    await tester.runAsync(() async {
      await tester.tap(
        find.byKey(const ValueKey('bootstrap_check_connection')),
      );
      await completed.future.timeout(const Duration(seconds: 15));
    });
    await tester.pumpAndSettle();
    final response = tester.widget<Text>(
      find.byKey(const ValueKey('bootstrap_connection_success')),
    );
    expect(response.data, 'Hello Balmatchum');
    expect(calls, 1);
    await binding.takeScreenshot('connection-success');
  });
}
