import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dev router never constructs real account services', () {
    if (appFlavor != 'dev') return;
    final container = ProviderContainer(
      overrides: [
        clientProvider.overrideWith(
          (ref) => throw StateError('real client accessed'),
        ),
        watchSyncServiceProvider.overrideWith(
          (ref) => throw StateError('Watch accessed'),
        ),
        signInStarterProvider.overrideWith(
          (ref) => throw StateError('real auth accessed'),
        ),
        greetingCheckProvider.overrideWith(
          (ref) => throw StateError('network accessed'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    expect(router.configuration.routes.length, 1);
  });

  testWidgets('flavor selects only its authorized entry', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: container.read(routerProvider)),
    );
    await tester.pump();
    if (appFlavor == 'dev') {
      expect(find.byType(FirstMeetingScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
    } else {
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(FirstMeetingScreen), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
