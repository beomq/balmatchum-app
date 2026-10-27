import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/billing/billing_providers.dart';
import '../features/billing/billing_screen.dart';
import '../features/daily_activity/daily_activity_providers.dart';
import '../features/photo/photo_screen.dart';
import '../features/photo/platform_photo_adapter.dart';
import '../features/records/records_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/quiz/authenticated_quiz_screen.dart';
import '../features/quiz/quiz_providers.dart';
import '../features/wardrobe/wardrobe_screen.dart';
import '../features/daily_activity/product_repository.dart';
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
          builder: (context, state) => FirstMeetingScreen(
            controller: controller,
            dailySteps: ref.read(dailyStepsControllerProvider),
            product: serverUrl.isEmpty
                ? null
                : ref.read(productControllerProvider),
            onOpenPhoto: () => context.push('/photo'),
            onOpenRecords: serverUrl.isEmpty
                ? null
                : () => context.push('/records'),
            onOpenQuiz: serverUrl.isEmpty ? null : () => context.push('/quiz'),
            onOpenWardrobe: serverUrl.isEmpty
                ? null
                : () => context.push('/wardrobe'),
          ),
          routes: [
            GoRoute(
              path: 'records',
              builder: (context, state) => RecordsCalendarScreen(
                initialMonth: ProductRepository.today,
                loadMonth: ref.read(productControllerProvider).loadMonth,
                onOpenDay: (date) =>
                    context.push('/records/${ProductRepository.dateKey(date)}'),
                onBack: () => context.pop(),
                onHome: () => context.go('/'),
              ),
              routes: [
                GoRoute(
                  path: ':date',
                  redirect: (context, state) {
                    final value = state.pathParameters['date']!;
                    final date = DateTime.tryParse(value);
                    return date == null ||
                            ProductRepository.dateKey(date) != value
                        ? '/records'
                        : null;
                  },
                  builder: (context, state) => RecordDayScreen(
                    date: DateTime.parse(state.pathParameters['date']!),
                    isToday:
                        state.pathParameters['date'] ==
                        ProductRepository.dateKey(ProductRepository.today),
                    loadDay: ref.read(productControllerProvider).loadDay,
                    deleteDay: ref.read(productControllerProvider).deleteDay,
                    claimDay: ref.read(productControllerProvider).claim,
                    rewardController: ref.read(productControllerProvider),
                    onBack: () => context.pop(),
                    onHome: () => context.go('/'),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'quiz',
              builder: (context, state) => DailyQuizScreen(
                loadQuiz: ref.read(productControllerProvider).loadQuiz,
                loadHistory: () async {
                  final product = ref.read(productControllerProvider);
                  return (await product.repository.client.product
                          .listQuizHistory('9999-12-31'))
                      .map(product.quizView)
                      .toList();
                },
                submitAnswer: ref.read(productControllerProvider).answer,
                onBack: () => context.pop(),
                onHome: () => context.go('/'),
              ),
            ),
            GoRoute(
              path: 'wardrobe',
              builder: (context, state) => WardrobeScreen(
                dogAsset: controller.state.candidate!.spritePath,
                loadWardrobe: ref.read(productControllerProvider).loadWardrobe,
                purchaseTheme: (theme) => ref
                    .read(productControllerProvider)
                    .themeAction(theme, equip: false),
                equipTheme: (theme) => ref
                    .read(productControllerProvider)
                    .themeAction(theme, equip: true),
                onBack: () => context.pop(),
                onHome: () => context.go('/'),
              ),
            ),
            GoRoute(
              path: 'photo',
              builder: (context, state) => PhotoScreen(
                dogAssetPath: controller.state.candidate!.spritePath,
                dogName: controller.state.name,
                adapter: PlatformPhotoAdapter(),
                onBack: () => context.pop(),
                onHome: () => context.go('/'),
              ),
            ),
          ],
        ),
      ],
      redirect: (context, state) =>
          state.uri.path == '/' ||
              (controller.state.isComplete &&
                  (state.uri.path == '/photo' ||
                      (serverUrl.isNotEmpty &&
                          (state.uri.path == '/quiz' ||
                              state.uri.path == '/wardrobe' ||
                              state.uri.path == '/records' ||
                              state.uri.path.startsWith('/records/')))))
          ? null
          : '/',
    );
    ref.onDispose(router.dispose);
    return router;
  }
  final checkGreeting = ref.watch(greetingCheckProvider);
  final signInStarter = ref.watch(signInStarterProvider);
  final authenticated = ref.watch(authenticatedMeetingControllerProvider);
  // Application-scoped subscription, not tied to the purchase route lifetime.
  final billing = ref.watch(billingControllerProvider);
  final router = GoRouter(
    refreshListenable: authenticated,
    redirect: (context, state) {
      final path = state.uri.path;
      if ((path == '/billing' ||
              path == '/photo' ||
              path == '/quiz' ||
              path == '/records' ||
              path.startsWith('/records/')) &&
          (authenticated == null || !authenticated.state.isComplete)) {
        return '/';
      }
      return null;
    },
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
        builder: (context, state) => authenticated == null
            ? ValueListenableBuilder<String?>(
                valueListenable: ref.read(accountNoticeProvider),
                builder: (context, notice, _) =>
                    SignInScreen(starter: signInStarter, notice: notice),
              )
            : FirstMeetingScreen(
                key: ObjectKey(authenticated),
                controller: authenticated,
                dailySteps: ref.read(dailyStepsControllerProvider),
                product: authenticated.state.isComplete
                    ? ref.read(authenticatedProductControllerProvider)
                    : null,
                onLogout: ref.read(logoutProvider),
                onDeleteAccount: ref.read(accountDeletionProvider)?.delete,
                onOpenPhoto: () => context.push('/photo'),
                onOpenRecords: () => context.push('/records'),
                onOpenQuiz: () => context.push('/quiz'),
                onOpenBilling: () => context.push('/billing'),
              ),
        routes: [
          GoRoute(
            path: 'billing',
            builder: (context, state) =>
                BillingScreen(key: ObjectKey(billing), controller: billing),
          ),
          GoRoute(
            path: 'quiz',
            builder: (context, state) => AuthenticatedQuizScreen(
              key: ObjectKey(authenticated),
              controller: ref.read(authenticatedQuizControllerProvider)!,
              onBack: () => context.pop(),
              onHome: () => context.go('/'),
            ),
          ),
          GoRoute(
            path: 'photo',
            builder: (context, state) => PhotoScreen(
              key: ObjectKey(authenticated),
              dogAssetPath: authenticated!.state.candidate!.spritePath,
              dogName: authenticated.state.name,
              adapter: PlatformPhotoAdapter(),
              onBack: () => context.pop(),
              onHome: () => context.go('/'),
            ),
          ),
          GoRoute(
            path: 'records',
            builder: (context, state) => RecordsCalendarScreen(
              key: ObjectKey(authenticated),
              initialMonth: ProductRepository.today,
              loadMonth: ref
                  .read(authenticatedProductControllerProvider)!
                  .loadMonth,
              onOpenDay: (date) =>
                  context.push('/records/${ProductRepository.dateKey(date)}'),
              onBack: () => context.pop(),
              onHome: () => context.go('/'),
            ),
            routes: [
              GoRoute(
                path: ':date',
                redirect: (context, state) {
                  final value = state.pathParameters['date']!;
                  final date = DateTime.tryParse(value);
                  return date == null ||
                          ProductRepository.dateKey(date) != value
                      ? '/records'
                      : null;
                },
                builder: (context, state) => RecordDayScreen(
                  key: ValueKey((authenticated, state.pathParameters['date'])),
                  date: DateTime.parse(state.pathParameters['date']!),
                  isToday:
                      state.pathParameters['date'] ==
                      ProductRepository.dateKey(ProductRepository.today),
                  loadDay: ref
                      .read(authenticatedProductControllerProvider)!
                      .loadDay,
                  deleteDay: ref
                      .read(authenticatedProductControllerProvider)!
                      .deleteDay,
                  claimDay: ref
                      .read(authenticatedProductControllerProvider)!
                      .claim,
                  rewardController: ref.read(
                    authenticatedProductControllerProvider,
                  ),
                  onBack: () => context.pop(),
                  onHome: () => context.go('/'),
                ),
              ),
            ],
          ),
        ],
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
