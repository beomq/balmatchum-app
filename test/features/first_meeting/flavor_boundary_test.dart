import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/app/router.dart';
import 'package:balmatchum_app/features/auth/sign_in_screen.dart';
import 'package:balmatchum_app/features/auth/sign_in_starter.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_screen.dart';
import 'package:balmatchum_app/features/first_meeting/first_meeting_providers.dart';
import 'package:balmatchum_app/features/first_meeting/domain/first_meeting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryMeetingStorage implements FirstMeetingStorage {
  String? payload;
  @override
  Future<String?> read() async => payload;
  @override
  Future<void> write(String value) async => payload = value;
  @override
  Future<void> delete() async => payload = null;
}

void main() {
  test('dev router never constructs real account services', () {
    if (appFlavor != 'dev') return;
    final container = ProviderContainer(
      overrides: [
        clientProvider.overrideWith(
          (ref) => throw StateError('real client accessed'),
        ),
        watchSyncServiceProvider.overrideWith(
          (ref) => throw StateError('Watch accessed'),
        ),
        signInStarterProvider.overrideWith(
          (ref) => throw StateError('real auth accessed'),
        ),
        greetingCheckProvider.overrideWith(
          (ref) => throw StateError('network accessed'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    expect(router.configuration.routes.length, 1);
  });

  testWidgets('flavor selects only its authorized entry', (tester) async {
    final store = MemoryMeetingStorage();
    final container = ProviderContainer(
      overrides: [firstMeetingStorageProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: container.read(routerProvider)),
    );
    await tester.pumpAndSettle();
    if (appFlavor == 'dev') {
      expect(find.byType(FirstMeetingScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      await tester.ensureVisible(find.textContaining('카카오').first);
      await tester.tap(find.textContaining('카카오').first);
      await tester.pumpAndSettle();
      expect(store.payload, isNotNull);
      expect(
        container.read(firstMeetingControllerProvider).state.step,
        FirstMeetingStep.method,
      );
    } else {
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(FirstMeetingScreen), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('scope owns controller lifetime and storage injection', () async {
    final store = MemoryMeetingStorage();
    final container = ProviderContainer(
      overrides: [firstMeetingStorageProvider.overrideWithValue(store)],
    );
    final controller = container.read(firstMeetingControllerProvider);
    expect(controller.storage, same(store));
    await controller.initialize();
    await controller.enter();
    expect(store.payload, isNotNull);
    container.dispose();
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
