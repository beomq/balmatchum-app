import 'package:balmatchum_app/app/app.dart';
import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('bootstrap resolves the root route through injected router', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    final app = tester.widget<BalmatchumApp>(find.byType(BalmatchumApp));
    expect(app.router, same(router));
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(SignInScreen), findsOneWidget);
    // ListTile rows add their own SafeArea; check the screen body's one.
    expect(
      find.ancestor(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (system, expected) in const [(2.0, maxTextScale), (1.1, 1.1)]) {
    testWidgets('system text scale $system shows as $expected', (tester) async {
      // Given the system text size setting.
      tester.platformDispatcher.textScaleFactorTestValue = system;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      late TextScaler seen;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) {
              seen = MediaQuery.textScalerOf(context);
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      // When the app builds a screen.
      await tester.pumpWidget(BalmatchumApp(router: router));
      await tester.pumpAndSettle();
      // Then text grows only up to the app limit.
      expect(seen.scale(10), closeTo(10 * expected, 0.001));
    });
  }
}
