import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/app/dependencies.dart';
import 'package:balmatchum_app/features/daily_activity/dev_test_session.dart';
import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:balmatchum_app/features/photo/photo_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serverpod_auth_core_flutter/serverpod_auth_core_flutter.dart';

class _NoPick implements PhotoAdapter {
  @override
  Future<Uint8List?> pick(PhotoSource source) async => null;
  @override
  Future<Uint8List?> recoverLostPhoto() async => null;
  @override
  Future<void> save(Uint8List png) async {}
  @override
  Future<PhotoShareResult> share(Uint8List png, ui.Rect origin) async =>
      PhotoShareResult.cancelled;
}

/// A 2400 x 1800 gradient, so the upload copy really is resized.
Future<Uint8List> picked() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const size = ui.Size(2400, 1800);
  canvas.drawRect(
    ui.Offset.zero & size,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset.zero,
        ui.Offset(size.width, size.height),
        [const ui.Color(0xFF0F766E), const ui.Color(0xFFF5C26B)],
      ),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(2400, 1800);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real session: compress, upload to S3, confirm, show, delete', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final client = container.read(clientProvider);
    expect(await importDevTestSession(client), isTrue);
    final account = client.auth.authInfo!.authUserId.toString();

    // The production uploader: generated client, signed PUT, disk cache.
    final uploader = accountPhotoUploader(client, account);
    final progress = <double>[];
    uploader.addListener(() {
      if (uploader.phase == UploadPhase.uploading) {
        progress.add(uploader.progress);
      }
    });
    await uploader.upload(await picked());
    expect(uploader.phase, UploadPhase.done, reason: uploader.error);
    expect(progress.last, 1.0);
    final view = uploader.photos!.first;
    expect((view.width, view.height), (1600, 1200));
    expect(view.contentType, 'image/jpeg');

    // A fresh uploader lists it and downloads it through the presigned GET.
    final viewer = accountPhotoUploader(client, account);
    await viewer.loadPhotos();
    final listed = viewer.photos!.firstWhere((p) => p.photoId == view.photoId);
    final downloaded = await viewer.transport.download(listed.url);
    expect(downloaded.length, view.byteSize);
    final decoded = img.decodeJpg(downloaded)!;
    expect((decoded.width, decoded.height), (1600, 1200));
    expect(await uploader.bytesOf(view), downloaded);
    viewer.dispose();

    // The signed-in screen shows it in the uploaded strip.
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: RepaintBoundary(
          key: boundary,
          child: PhotoScreen(
            dogAssetPath: 'assets/first_meeting/dogs/pug.png',
            dogName: '검증친구',
            adapter: _NoPick(),
            createUploader: () => accountPhotoUploader(client, account),
            onBack: () {},
            onHome: () {},
          ),
        ),
      ),
    );
    final item = find.byKey(ValueKey('photo_upload_${view.photoId.uuid}'));
    for (var i = 0; i < 100 && item.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(item, findsOneWidget);
    final image = find.descendant(of: item, matching: find.byType(Image));
    for (var i = 0; i < 100 && image.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(image, findsOneWidget);
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    // Evidence capture in the app's own files; the harness pulls it.
    final shot =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final png = await shot.toByteData(format: ui.ImageByteFormat.png);
    shot.dispose();
    await File(
      '${(await getApplicationSupportDirectory()).path}'
      '/photo-upload-server-strip.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    await tester.pumpWidget(const SizedBox.shrink());

    // Delete removes it on the server and from the list.
    await uploader.delete(view.photoId);
    final after = accountPhotoUploader(client, account);
    await after.loadPhotos();
    expect(after.photos!.any((p) => p.photoId == view.photoId), isFalse);
    after.dispose();
    uploader.dispose();
  });
}
