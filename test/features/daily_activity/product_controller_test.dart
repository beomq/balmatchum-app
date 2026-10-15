import 'package:balmatchum_app/features/daily_activity/product_controller.dart';
import 'package:balmatchum_app/features/daily_activity/product_repository.dart';
import 'package:balmatchum_app/features/daily_activity/daily_steps_controller.dart';
import 'package:balmatchum_app/features/watch_sync/watch_bridge.dart';
import 'package:balmatchum_client/balmatchum_client.dart';
import 'package:flutter_test/flutter_test.dart';

class MissingSessionRepository extends ProductRepository {
  MissingSessionRepository() : super(Client('http://localhost/'));
  @override
  Future<void> connectDevelopmentUser() async =>
      throw const FormatException('No session');
}

void main() {
  test(
    'missing and revoked sessions enable reconnect without throwing',
    () async {
      final repository = MissingSessionRepository();
      final steps = DailyStepsController(
        readSteps: () async =>
            const DailyStepsResult(DailyStepsStatus.empty, null),
      );
      final controller = ProductController(repository, steps, null);
      addTearDown(() {
        controller.dispose();
        steps.dispose();
        repository.client.close();
      });
      await controller.connect();
      expect(controller.connected, isFalse);
      expect(controller.error, isNotNull);
      controller.connected = true;
      controller.store = ThemeStore(
        items: [],
        equippedTheme: 'cloudy',
        balance: 5,
      );
      await controller.sync();
      expect(controller.connected, isFalse);
      expect(controller.store, isNull);
      expect(controller.today, isNull);
      expect(controller.quiz, isNull);
      expect(controller.busy, isFalse);
      expect(controller.error, isNotNull);
    },
  );
}
