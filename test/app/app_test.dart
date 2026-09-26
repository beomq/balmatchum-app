import 'package:balmatchum_app/app/app.dart';
import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(find.byType(BootstrapScreen), findsOneWidget);
    expect(find.byType(SafeArea), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
