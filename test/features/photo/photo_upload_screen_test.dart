import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:balmatchum_app/features/photo/photo_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'photo_editor_test.dart' show FakePhotoAdapter, photoFixture;
import 'photo_screen_test.dart' show idle;
import 'photo_upload_test.dart' show FakePhotoTransport, pngOf;

/// Opt-in evidence captures, written under this directory when set.
const renderDir = String.fromEnvironment('PHOTO_UPLOAD_RENDER_DIR');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (renderDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$renderDir/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// Seeds [count] confirmed photos in [transport].
Future<void> seed(FakePhotoTransport transport, int count) async {
  final uploader = PhotoUploader(transport: transport, cache: PhotoCache());
  for (var i = 0; i < count; i++) {
    await uploader.upload(await pngOf(40 + i * 10, 40));
  }
}

Future<PhotoScreenState> openScreen(
  WidgetTester tester, {
  required FakePhotoAdapter adapter,
  FakePhotoTransport? transport,
  GlobalKey? boundary,
}) async {
  await tester.runAsync(() async {
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'));
    await font.load();
  });
  final screen = PhotoScreen(
    dogAssetPath: 'assets/first_meeting/dogs/pug.png',
    dogName: '콩이',
    adapter: adapter,
    createUploader: transport == null
        ? null
        : () => PhotoUploader(transport: transport, cache: PhotoCache()),
    onBack: () {},
    onHome: () {},
  );
  await tester.runAsync(
    () => tester.pumpWidget(
      MaterialApp(
        theme: meetingTheme(),
        home: RepaintBoundary(key: boundary, child: screen),
      ),
    ),
  );
  final state = tester.state<PhotoScreenState>(find.byType(PhotoScreen));
  await tester.runAsync(() => idle(state));
  await tester.pumpAndSettle();
  return state;
}

/// Lets real decoding and the JPEG isolate finish, then settles frames.
Future<void> drain(WidgetTester tester, PhotoScreenState state) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.runAsync(() => idle(state));
    await tester.pumpAndSettle();
  }
}

Future<void> uploadSettled(WidgetTester tester, PhotoScreenState state) async {
  final uploader = state.uploader!;
  await tester.runAsync(() async {
    if (!uploader.busy) return;
    final done = Completer<void>();
    void changed() {
      if (!uploader.busy && !done.isCompleted) done.complete();
    }

    uploader.addListener(changed);
    await done.future.timeout(const Duration(seconds: 20));
    uploader.removeListener(changed);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without an uploader nothing about uploads is shown', (
    tester,
  ) async {
    final state = await openScreen(tester, adapter: FakePhotoAdapter());
    expect(state.uploader, isNull);
    expect(find.byKey(const ValueKey('photo_uploads')), findsNothing);
  });

  testWidgets('an empty account says where photos will appear', (tester) async {
    await openScreen(
      tester,
      adapter: FakePhotoAdapter(),
      transport: FakePhotoTransport(),
    );
    expect(find.byKey(const ValueKey('photo_uploads_empty')), findsOneWidget);
  });

  testWidgets('a failed listing offers a retry that loads the photos', (
    tester,
  ) async {
    final transport = FakePhotoTransport();
    await tester.runAsync(() => seed(transport, 1));
    transport.listFailure = const SocketException('offline');
    final state = await openScreen(
      tester,
      adapter: FakePhotoAdapter(),
      transport: transport,
    );
    expect(find.byKey(const ValueKey('photo_uploads_error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo_uploads_retry')));
    await drain(tester, state);
    expect(find.byKey(const ValueKey('photo_uploads_list')), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('upload states and the uploaded strip at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = size.width.toInt();
      final boundary = GlobalKey();
      final transport = FakePhotoTransport();
      await tester.runAsync(() => seed(transport, 3));
      final adapter = FakePhotoAdapter();
      final state = await openScreen(
        tester,
        adapter: adapter,
        transport: transport,
        boundary: boundary,
      );
      await drain(tester, state);
      // Three thumbnails, newest first, from the photos' own bytes.
      final strip = find.byKey(const ValueKey('photo_uploads_list'));
      expect(strip, findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.byType(Image)),
        findsNWidgets(3),
      );
      expect(find.text('올린 사진 3'), findsOneWidget);
      await tester.ensureVisible(strip);
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'upload-strip-$w');

      // A pick starts the upload; the PUT is held to show its progress.
      // Completers live in the real zone so the held PUT resumes inside
      // runAsync, not on a later fake-async pump.
      late final Completer<void> gate;
      adapter.next = await tester.runAsync(photoFixture);
      await tester.ensureVisible(find.byKey(const ValueKey('photo_gallery')));
      await tester.runAsync(() async {
        gate = Completer<void>();
        final started = Completer<void>();
        transport
          ..putGate = gate
          ..putStarted = started;
        unawaited(state.pick(PhotoSource.gallery));
        await started.future.timeout(const Duration(seconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
      expect(find.text('사진 보관 중 50%'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('photo_upload_progress')),
        findsOneWidget,
      );
      // Editing is not blocked by the upload.
      expect(state.editor.busy, isFalse);
      await capture(tester, boundary, 'upload-progress-$w');

      // The PUT fails: the photo stays and a retry is offered.
      transport.putFailure = const SocketException('offline');
      await tester.runAsync(() async => gate.complete());
      await uploadSettled(tester, state);
      expect(find.byKey(const ValueKey('photo_upload_retry')), findsOneWidget);
      expect(find.text('사진을 올리지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      await capture(tester, boundary, 'upload-failed-$w');

      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('photo_upload_retry'))),
      );
      await uploadSettled(tester, state);
      expect(find.text('사진을 안전하게 보관했어요'), findsOneWidget);
      expect(state.uploader!.photos, hasLength(4));
      expect(
        transport.tickets,
        hasLength(4),
        reason: 'retry reused the ticket',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('saving uploads the composite, which leads its strip entry', (
    tester,
  ) async {
    final boundary = GlobalKey();
    final transport = FakePhotoTransport();
    final adapter = FakePhotoAdapter();
    final state = await openScreen(
      tester,
      adapter: adapter,
      transport: transport,
      boundary: boundary,
    );
    await drain(tester, state);
    adapter.next = await tester.runAsync(photoFixture);
    await tester.runAsync(() => state.pick(PhotoSource.gallery));
    await uploadSettled(tester, state);
    expect(find.text('사진을 안전하게 보관했어요'), findsOneWidget);
    final original = transport.tickets.single.photoId;

    await tester.ensureVisible(find.byKey(const ValueKey('photo_save')));
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('photo_save'))),
    );
    await tester.runAsync(() => idle(state));
    await uploadSettled(tester, state);
    expect(adapter.saved, isNotNull);
    expect(find.text('꾸민 사진도 보관했어요'), findsOneWidget);
    final composite = transport.tickets.last.photoId;
    expect(transport.reserved[composite], (UploadKind.composite, original));
    await capture(tester, boundary, 'composite-saved-390');

    // One entry for the pair, led by the saved picture.
    final groups = state.uploader!.groups;
    expect(groups, hasLength(1));
    expect(groups.single.main.photoId, composite);
    expect(groups.single.original!.photoId, original);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long-press deletes after a confirm; tap opens in the editor', (
    tester,
  ) async {
    final transport = FakePhotoTransport();
    await tester.runAsync(() => seed(transport, 2));
    final state = await openScreen(
      tester,
      adapter: FakePhotoAdapter(),
      transport: transport,
    );
    await drain(tester, state);
    final first = transport.views.first.photoId;
    final item = find.byKey(ValueKey('photo_upload_${first.uuid}'));
    await tester.ensureVisible(item);
    await tester.longPress(item);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(transport.views, hasLength(2));
    await tester.longPress(item);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () =>
          tester.tap(find.byKey(const ValueKey('photo_upload_delete_confirm'))),
    );
    await drain(tester, state);
    expect(transport.views.map((v) => v.photoId), isNot(contains(first)));
    expect(item, findsNothing);

    final second = transport.views.single.photoId;
    await tester.runAsync(
      () => tester.tap(find.byKey(ValueKey('photo_upload_${second.uuid}'))),
    );
    await drain(tester, state);
    expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
    // Opening an uploaded photo does not upload it again.
    expect(state.uploader!.phase, UploadPhase.idle);
    expect(transport.tickets, hasLength(2));
  });
}
