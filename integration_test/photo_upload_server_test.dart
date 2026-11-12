import 'dart:math';
import 'dart:ui' as ui;

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:balmatchum_app/features/photo/photo_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

/// Stands in for the system photo picker, which a test cannot drive: it
/// hands the screen one camera-sized photo. Everything after the pick is
/// the production path.
class _PickedPhoto implements PhotoAdapter {
  _PickedPhoto(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pick(PhotoSource source) async => bytes;
  @override
  Future<Uint8List?> recoverLostPhoto() async => null;
  @override
  Future<void> save(Uint8List png) async {}
  @override
  Future<PhotoShareResult> share(Uint8List png, ui.Rect origin) async =>
      PhotoShareResult.cancelled;
}

/// A 2400 x 1800 photo with fine detail, so the upload copy is large enough
/// (about 1 MB) for its progress to be seen.
Uint8List cameraPhoto() {
  final random = Random(11);
  final image = img.Image(width: 2400, height: 1800);
  for (final pixel in image) {
    final base = (pixel.x ~/ 3 + pixel.y ~/ 4) % 255;
    pixel
      ..r = (base + random.nextInt(60)) % 256
      ..g = (120 + random.nextInt(80)) % 256
      ..b = (200 - base ~/ 2 + random.nextInt(40)) % 256;
  }
  return img.encodeJpg(image, quality: 92);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps frames until [done] holds; real network work runs meanwhile.
  Future<void> until(
    WidgetTester tester,
    bool Function() done, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'pick, upload with progress, see it uploaded, long-press delete',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final client = container.read(clientProvider);
      expect(await importDevTestSession(client), isTrue);
      final account = client.auth.authInfo!.authUserId.toString();

      final adapter = _PickedPhoto(cameraPhoto());
      final uploaders = <PhotoUploader>[];
      var generation = 0;
      late StateSetter remount;
      await tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: StatefulBuilder(
            builder: (context, setState) {
              remount = setState;
              return PhotoScreen(
                key: ValueKey(generation),
                dogAssetPath: 'assets/first_meeting/dogs/pug.png',
                dogName: '검증친구',
                adapter: adapter,
                createUploader: () {
                  final uploader = accountPhotoUploader(client, account);
                  uploaders.add(uploader);
                  return uploader;
                },
                // Back from the editor opens a fresh start screen.
                onBack: () => remount(() => generation++),
                onHome: () {},
              );
            },
          ),
        ),
      );
      await until(tester, () => uploaders.last.photos != null);
      final before = {for (final p in uploaders.last.photos!) p.photoId};

      // Pick: the editor opens at once and the upload runs underneath it.
      await tester.tap(find.byKey(const ValueKey('photo_gallery')));
      final first = uploaders.last;
      await until(
        tester,
        () =>
            (first.phase == UploadPhase.uploading && first.progress > 0) ||
            first.phase == UploadPhase.done ||
            first.phase == UploadPhase.failed,
      );
      expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
      await binding.takeScreenshot('photo-upload-1-progress');
      await until(
        tester,
        () =>
            first.phase == UploadPhase.done ||
            first.phase == UploadPhase.failed,
      );
      expect(first.phase, UploadPhase.done, reason: first.error);
      await tester.pump();
      expect(find.text('사진을 안전하게 보관했어요'), findsOneWidget);
      await binding.takeScreenshot('photo-upload-2-done');
      final uploaded = first.photos!
          .firstWhere((p) => !before.contains(p.photoId))
          .photoId;

      // Leave the editor: a fresh start screen lists it from the server.
      await tester.tap(find.byKey(const ValueKey('photo_back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('나가기'));
      await until(tester, () => uploaders.length == 2);
      final item = find.byKey(ValueKey('photo_upload_${uploaded.uuid}'));
      final thumbnail = find.descendant(of: item, matching: find.byType(Image));
      await until(tester, () => thumbnail.evaluate().isNotEmpty);
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('photo-upload-3-uploaded-strip');

      // Long-press deletes after a confirm.
      await tester.longPress(item);
      await tester.pumpAndSettle();
      expect(find.text('올린 사진을 지울까요?'), findsOneWidget);
      await binding.takeScreenshot('photo-upload-4-delete-confirm');
      await tester.tap(
        find.byKey(const ValueKey('photo_upload_delete_confirm')),
      );
      await until(tester, () => item.evaluate().isEmpty);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('photo-upload-5-deleted');

      final after = await client.photo.listMine();
      expect(after.any((p) => p.photoId == uploaded), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
