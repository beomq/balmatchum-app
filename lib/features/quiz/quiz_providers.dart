import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../billing/billing_providers.dart';
import 'quiz_controller.dart';
import 'quiz_repository.dart';

final authenticatedQuizControllerProvider = Provider<QuizController?>((ref) {
  final account = ref.watch(authenticatedAccountProvider);
  if (account == null) return null;
  final client = ref.watch(clientProvider);
  final billing = ref.watch(billingRepositoryProvider);
  final controller = QuizController(
    QuizRepository(client, account, billing: billing),
    isCurrentAccount: () => billing?.isCurrent ?? false,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
