import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/first_meeting/first_meeting_screen.dart';
import '../features/first_meeting/first_meeting_providers.dart';
import '../features/auth/sign_in_starter.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';
import '../features/location_experiment/location_experiment_screen.dart';
import '../features/watch_sync/watch_diagnostics_screen.dart';
import 'dependencies.dart';

final routerProvider = Provider<GoRouter>((ref) {
  if (appFlavor == 'dev') {
    final controller = ref.watch(firstMeetingControllerProvider);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              FirstMeetingScreen(controller: controller),
        ),
      ],
      redirect: (context, state) => state.uri.path == '/' ? null : '/',
    );
    ref.onDispose(router.dispose);
    return router;
  }
  final checkGreeting = ref.watch(greetingCheckProvider);
  final signInStarter = ref.watch(signInStarterProvider);
  final router = GoRouter(
    routes: [
      if (phoneLocationExperimentEnabled)
        GoRoute(
          path: '/debug/watch',
          builder: (context, state) => const WatchDiagnosticsScreen(),
        ),
      if (phoneLocationExperimentEnabled)
        GoRoute(
          path: '/debug/location',
          builder: (context, state) => const PhoneLocationExperimentScreen(),
        ),
      GoRoute(
        path: '/',
        builder: (context, state) => SignInScreen(starter: signInStarter),
      ),
      GoRoute(
        path: '/greeting',
        builder: (context, state) =>
            BootstrapScreen(checkGreeting: checkGreeting),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
