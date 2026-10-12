import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful restore completes once before startup continues', () async {
    final events = <String>[];
    await restoreSession(() async => events.add('restored'));
    events.add('startup');
    expect(events, ['restored', 'startup']);
  });

  test('restore does not swallow programming Errors', () async {
    final error = StateError('programming error');
    await expectLater(
      restoreSession(() async => throw error),
      throwsA(same(error)),
    );
  });

  testWidgets('storage Exception allows startup to reach signed-out screen', (
    tester,
  ) async {
    final previousDebugPrint = debugPrint;
    final messages = <String?>[];
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    try {
      await restoreSession(
        () async => throw Exception('private storage value'),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(messages, isNotEmpty);
    expect(messages.join(), isNot(contains('private storage value')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
