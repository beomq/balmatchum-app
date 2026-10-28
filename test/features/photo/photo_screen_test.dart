import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_editor.dart'
    show DogSticker;
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'photo_editor_test.dart' show FakePhotoAdapter, photoFixture;

class PendingPhotoAdapter extends FakePhotoAdapter {
  Completer<Uint8List?>? pendingPick;

  @override
  Future<Uint8List?> pick(PhotoSource source) =>
      pendingPick?.future ?? super.pick(source);
}

Future<void> idle(PhotoScreenState state) {
  if (!state.editor.busy) return Future.value();
  final done = Completer<void>();
  void changed() {
    if (!state.editor.busy) {
      state.editor.removeListener(changed);
      done.complete();
    }
  }

  state.editor.addListener(changed);
  return done.future.timeout(const Duration(seconds: 10));
}

void main() {
  testWidgets('scale updates require a fresh idle start', (tester) async {
    final adapter = PendingPhotoAdapter();
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: meetingTheme(),
          home: PhotoScreen(
            dogAssetPath: 'assets/first_meeting/dogs/pug.png',
            dogName: '콩이',
            adapter: adapter,
            onBack: () {},
            onHome: () {},
          ),
        ),
      ),
    );
    final state = tester.state<PhotoScreenState>(find.byType(PhotoScreen));
    await tester.runAsync(() => idle(state));
    adapter.next = await tester.runAsync(photoFixture);
    await tester.runAsync(() => state.editor.pick(PhotoSource.gallery));
    await tester.pumpAndSettle();
    GestureDetector canvas() => tester.widget<GestureDetector>(
      find.byKey(const ValueKey('photo_canvas')),
    );
    final start = ScaleStartDetails(localFocalPoint: const Offset(50, 50));
    final update = ScaleUpdateDetails(
      localFocalPoint: const Offset(70, 50),
      scale: 1.2,
      rotation: .3,
    );
    final original = state.editor.sticker;
    canvas().onScaleUpdate!(update);
    expect(state.editor.sticker, same(original));

    // A gesture that starts while busy must not become active on completion.
    adapter.pendingPick = Completer<Uint8List?>();
    var picking = state.editor.pick(PhotoSource.gallery);
    await tester.pump();
    canvas().onScaleStart!(start);
    canvas().onScaleUpdate!(update);
    adapter.pendingPick!.complete(null);
    await picking;
    await tester.pump();
    canvas().onScaleUpdate!(update);
    expect(state.editor.sticker, same(original));

    // Busy transitions invalidate an already active gesture, even without a frame.
    canvas().onScaleStart!(start);
    canvas().onScaleUpdate!(update);
    expect(state.editor.sticker.scale, 1.2);
    adapter.pendingPick = Completer<Uint8List?>();
    picking = state.editor.pick(PhotoSource.gallery);
    adapter.pendingPick!.complete(null);
    await picking;
    state.editor.edit(const DogSticker(x: .2, scale: .6));
    final changed = state.editor.sticker;
    canvas().onScaleUpdate!(update);
    expect(state.editor.sticker, same(changed));

    canvas().onScaleStart!(start);
    canvas().onScaleUpdate!(update);
    expect(state.editor.sticker.scale, closeTo(.72, .00001));
    canvas().onScaleEnd!(ScaleEndDetails());
    final ended = state.editor.sticker;
    canvas().onScaleUpdate!(update);
    expect(state.editor.sticker, same(ended));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(390, 844),
    const Size(1024, 768),
    const Size(320, 568),
  ]) {
    testWidgets('photo controls, identity and render at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = FakePhotoAdapter();
      final capture = GlobalKey();
      await tester.runAsync(() async {
        final font = FontLoader('Pretendard')
          ..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'));
        await font.load();
      });
      var back = 0;
      var home = 0;
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme(),
            home: RepaintBoundary(
              key: capture,
              child: PhotoScreen(
                dogAssetPath: 'assets/first_meeting/dogs/pug.png',
                dogName: '콩이',
                adapter: adapter,
                onBack: () => back++,
                onHome: () => home++,
              ),
            ),
          ),
        ),
      );
      final state = tester.state<PhotoScreenState>(find.byType(PhotoScreen));
      await tester.runAsync(() => idle(state));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.endsWith('/pug.png'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('photo_back')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('photo_home')));
      await tester.pump();
      expect(back, 1);
      expect(home, 1);
      adapter.next = await tester.runAsync(photoFixture);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('photo_gallery'))),
      );
      await tester.runAsync(() => idle(state));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo_back')));
      await tester.pumpAndSettle();
      expect(back, 1);
      await tester.tap(find.text('계속 편집'));
      await tester.pumpAndSettle();
      expect(state.editor.photo, isNotNull);
      expect(back, 1);
      final beforeDrag = state.editor.sticker.x;
      expect(
        tester
            .widget<GestureDetector>(find.byKey(const ValueKey('photo_canvas')))
            .onScaleUpdate,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('photo_canvas')));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('photo_canvas'))),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.editor.sticker.x, greaterThan(beforeDrag));
      await tester.ensureVisible(find.byKey(const ValueKey('photo_flip')));
      await tester.tap(find.byKey(const ValueKey('photo_flip')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Explicit opt-in evidence output. Not a golden baseline or a prose test.
      if (const bool.fromEnvironment('PHOTO_RENDER')) {
        await tester.ensureVisible(find.byKey(const ValueKey('photo_back')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('test/features/photo/render-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.byKey(const ValueKey('photo_share')));
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('photo_share'))),
      );
      await tester.runAsync(() => idle(state));
      await tester.pumpAndSettle();
      expect(adapter.shared, isNotNull);
      expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
      adapter.failure = const PhotoFailure('denied');
      final edit = state.editor.sticker;
      await tester.ensureVisible(find.byKey(const ValueKey('photo_save')));
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('photo_save'))),
      );
      await tester.runAsync(() => idle(state));
      await tester.pumpAndSettle();
      expect(state.editor.isError, isTrue);
      expect(state.editor.sticker, same(edit));
      expect(adapter.saved, isNull);
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            theme: meetingTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: PhotoScreen(
              dogAssetPath: 'assets/first_meeting/dogs/pug.png',
              dogName: '콩이',
              adapter: adapter,
              onBack: () {},
              onHome: () {},
            ),
          ),
        ),
      );
      final largeState = tester.state<PhotoScreenState>(
        find.byType(PhotoScreen),
      );
      await tester.runAsync(() => idle(largeState));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('photo_save')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Duo rail replaces the photo top bar and keeps its guards', (
    tester,
  ) async {
    // Given the measured outer portrait insets and an idle editor.
    useDuoViewport(tester, 'outer portrait');
    final adapter = PendingPhotoAdapter();
    var back = 0;
    var home = 0;
    await tester.runAsync(
      () => tester.pumpWidget(
        duoHost(
          PhotoScreen(
            dogAssetPath: 'assets/first_meeting/dogs/pug.png',
            dogName: '콩이',
            adapter: adapter,
            onBack: () => back++,
            onHome: () => home++,
          ),
        ),
      ),
    );
    final state = tester.state<PhotoScreenState>(find.byType(PhotoScreen));
    await tester.runAsync(() => idle(state));
    await tester.pumpAndSettle();
    final railBack = find.byKey(const ValueKey('duo_rail_back'));
    final railHome = find.byKey(const ValueKey('duo_rail_home'));
    VoidCallback? action(Finder button) =>
        tester.widget<IconButton>(button).onPressed;
    expect(find.byKey(const ValueKey('photo_back')), findsNothing);
    expect(find.byKey(const ValueKey('photo_home')), findsNothing);
    expect(railBack.hitTestable(), findsOneWidget);
    // When a pick is pending, both rail buttons are disabled.
    adapter.pendingPick = Completer<Uint8List?>();
    final picking = state.editor.pick(PhotoSource.gallery);
    await tester.pump();
    expect(state.editor.busy, isTrue);
    expect(action(railBack), isNull);
    expect(action(railHome), isNull);
    adapter.pendingPick!.complete(null);
    await picking;
    adapter.pendingPick = null;
    await tester.pump();
    expect(action(railBack), isNotNull);
    // Then leaving an edited photo through the rail still asks first.
    adapter.next = await tester.runAsync(photoFixture);
    await tester.runAsync(() => state.editor.pick(PhotoSource.gallery));
    await tester.pumpAndSettle();
    expect(state.editor.photo, isNotNull);
    await tester.tap(railBack);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(back, 0);
    await tester.tap(railHome);
    await tester.pumpAndSettle();
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();
    expect(home, 1);
    expect(back, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
