import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import 'product_controller.dart';
import 'product_repository.dart';
import '../watch_sync/watch_bridge.dart';
import 'daily_steps_controller.dart';

final dailyStepsControllerProvider = Provider<DailyStepsController>((ref) {
  final controller = DailyStepsController(
    readSteps: WatchBridge().requestDailySteps,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final productControllerProvider = Provider<ProductController>((ref) {
  final controller = ProductController(
    ProductRepository(ref.watch(clientProvider)),
    ref.watch(dailyStepsControllerProvider),
    ref.watch(watchSyncServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
