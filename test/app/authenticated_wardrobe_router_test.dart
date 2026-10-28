import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_screen.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/daily_activity/product_controller_test.dart'
    show AccountRepository;
import '../features/first_meeting/domain/authenticated_profile_test.dart'
    show Profiles, view;
import '../features/first_meeting/domain/first_meeting_test.dart'
    show MemoryStorage;

void main() {
  testWidgets('signed out wardrobe request shows sign in', (tester) async {
    if (appFlavor == 'dev') return;
    final container = ProviderContainer(
      overrides: [
        authenticatedMeetingControllerProvider.overrideWithValue(null),
        authenticatedProductControllerProvider.overrideWith(
          (ref) => throw StateError('Protected product accessed'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/wardrobe');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(WardrobeScreen), findsNothing);
  });

  testWidgets('completed account opens server wardrobe from home', (
    tester,
  ) async {
    if (appFlavor == 'dev') return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profiles = Profiles()..current = view(name: '실제친구');
    final meeting = FirstMeetingController(
      storage: MemoryStorage(),
      profileRepository: profiles,
    );
    await meeting.initialize();
    final repository = AccountRepository();
    final steps = DailyStepsController(
      readSteps: () async =>
          const DailyStepsResult(DailyStepsStatus.empty, null),
    );
    final product = ProductController(repository, steps, null, account: 'A');
    final container = ProviderContainer(
      overrides: [
        authenticatedMeetingControllerProvider.overrideWithValue(meeting),
        authenticatedProductControllerProvider.overrideWithValue(product),
        dailyStepsControllerProvider.overrideWithValue(steps),
      ],
    );
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      MaterialApp.router(theme: meetingTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('home_tile_wardrobe'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/wardrobe',
    );
    expect(find.byType(WardrobeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('product_fixture_badge')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('wardrobe_balance'))).data,
      '보유 42포인트',
    );
    expect(repository.calls, isNot(contains('dev')));
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    product.dispose();
    steps.dispose();
    meeting.dispose();
    repository.client.close();
  });
}
