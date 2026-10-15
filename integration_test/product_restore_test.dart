import 'dart:io';

import 'package:balmatchum_app/features/daily_activity/daily_activity_providers.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'product_flow_test.dart' show changedTo;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('fresh process restores native credentials and purchased theme', (
    tester,
  ) async {
    final container = ProviderContainer();
    final meeting = container.read(firstMeetingControllerProvider);
    await meeting.initialize();
    expect(meeting.state.isComplete, isTrue);
    final directory = await getApplicationSupportDirectory();
    expect(
      await File('${directory.path}/dev-test-session.json').exists(),
      isFalse,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppBootstrap(),
      ),
    );
    await tester.pumpAndSettle();
    final product = container.read(productControllerProvider);
    await changedTo(product, () => !product.busy, () async {
      final connect = find.text('개발 테스트 사용자 연결');
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pump();
    });
    expect(product.connected, isTrue, reason: product.error);
    expect(product.store?.equippedTheme, 'cloudy');
    expect(product.store?.balance, 2);
    await tester.pumpAndSettle();
    final image = await binding.takeScreenshot('product-process-restored');
    await File('${directory.path}/product-process-restored.png')
        .writeAsBytes(image);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
