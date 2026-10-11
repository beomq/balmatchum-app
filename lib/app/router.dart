import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_in_starter.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';
import 'dependencies.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final checkGreeting = ref.watch(greetingCheckProvider);
  final signInStarter = ref.watch(signInStarterProvider);
  final router = GoRouter(
    routes: [
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
