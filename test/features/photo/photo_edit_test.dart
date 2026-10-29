import 'dart:async';
import 'dart:ui' as ui;

import 'package:balmatchum_app/features/first_meeting/meeting_theme.dart';
import 'package:balmatchum_app/features/photo/photo_editor.dart'
    show DogSticker;
import 'package:balmatchum_app/features/photo/photo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/duo_viewports.dart';
import 'photo_editor_test.dart' show FakePhotoAdapter;
import 'photo_screen_test.dart' show PendingPhotoAdapter, idle;
import 'photo_start_test.dart' show open;

const photoColor = Color(0xFF336699);

/// A one-colour photo of [width] × [height] pixels.
Future<Uint8List> solidPhoto(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(photoColor, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List();
}

Future<PhotoScreenState> editing(
  WidgetTester tester,
  FakePhotoAdapter adapter, {
  int width = 400,
  int height = 400,
  Widget Function(Widget)? wrap,
}) async {
  final state = await open(tester, adapter, wrap: wrap);
  adapter.next = await tester.runAsync(() => solidPhoto(width, height));
  await tester.runAsync(() => state.editor.pick(PhotoSource.gallery));
  await tester.pumpAndSettle();
  return state;
}

Rect preview(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('photo_preview')));

void main() {
  testWidgets('the editor has no sliders, saves on top and keeps two tools', (
    tester,
  ) async {
    await editing(tester, FakePhotoAdapter());
    expect(find.byType(Slider), findsNothing);
    final save = find.byKey(const ValueKey('photo_save'));
    final canvas = find.byKey(const ValueKey('photo_canvas'));
    expect(tester.getRect(save).bottom, lessThan(tester.getRect(canvas).top));
    for (final key in ['photo_flip', 'photo_reset']) {
      expect(
        tester.getRect(find.byKey(ValueKey(key))).top,
        greaterThan(tester.getRect(canvas).bottom),
        reason: key,
      );
    }
    // The way out is the close button; the pick is gone from editing.
    expect(find.byKey(const ValueKey('photo_back')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo_gallery')), findsNothing);
    expect(find.byKey(const ValueKey('photo_hint')), findsOneWidget);
  });

  testWidgets(
    'a tall photo keeps its ratio and the pointer moves by its size',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = await editing(
        tester,
        FakePhotoAdapter(),
        width: 300,
        height: 900,
      );
      final drawn = preview(tester);
      final canvas = tester.getRect(find.byKey(const ValueKey('photo_canvas')));
      // Whole and unstretched: narrower than the canvas, at the photo ratio.
      expect(drawn.width, lessThan(canvas.width - 100));
      expect(drawn.width / drawn.height, closeTo(1 / 3, .01));
      final before = state.editor.sticker;
      final gesture = await tester.startGesture(drawn.center);
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(10, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final after = state.editor.sticker;
      // In points of the drawn photo on both axes; 60 x 30 at most, short
      // of the photo's edge, so no clamp interferes.
      final dx = (after.x - before.x) * drawn.width;
      final dy = (after.y - before.y) * drawn.height;
      expect(dx, greaterThan(20));
      expect(dx, lessThanOrEqualTo(60.5));
      expect(dy, closeTo(dx / 2, 1));
    },
  );

  testWidgets('the selection follows a turned and flipped companion', (
    tester,
  ) async {
    final state = await editing(tester, FakePhotoAdapter());
    state.editor.edit(
      const DogSticker(x: .3, y: .4, scale: 1.4, rotation: .7, flipped: true),
    );
    await tester.pump();
    final overlay = tester.widget<PhotoSelectionOverlay>(
      find.byType(PhotoSelectionOverlay),
    );
    final drawn = preview(tester);
    final canvas = tester.getRect(find.byKey(const ValueKey('photo_canvas')));
    final dog = state.editor.dog!;
    final expected = state.editor.sticker
        .rect(drawn.size, Size(dog.width.toDouble(), dog.height.toDouble()))
        .shift(drawn.topLeft - canvas.topLeft);
    expect(overlay.rotation, .7);
    expect(overlay.rect.left, closeTo(expected.left, .01));
    expect(overlay.rect.top, closeTo(expected.top, .01));
    expect(overlay.rect.size, expected.size);
  });

  testWidgets('the saved PNG has the photo and dog only, at photo size', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter);
    state.editor.edit(const DogSticker(x: .5, y: .5, scale: 1.2));
    await tester.pump();
    expect(find.byType(PhotoSelectionOverlay), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('photo_save'))),
    );
    await tester.runAsync(() => idle(state));
    await tester.pumpAndSettle();
    final saved = adapter.saved!;
    final composite = await tester.runAsync(state.editor.capturePng);
    expect(saved, orderedEquals(composite!));
    final pixels = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(saved);
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData();
      final size = (image.width, image.height);
      image.dispose();
      codec.dispose();
      return (data!, size);
    });
    final (data, (width, height)) = pixels!;
    expect((width, height), (400, 400));
    final dog = state.editor.dog!;
    final box = state.editor.sticker.rect(
      const Size(400, 400),
      Size(dog.width.toDouble(), dog.height.toDouble()),
    );
    // Just outside each corner, where a corner mark would be drawn.
    for (final corner in [
      box.topLeft + const Offset(-4, -4),
      box.topRight + const Offset(4, -4),
      box.bottomLeft + const Offset(-4, 4),
      box.bottomRight + const Offset(4, 4),
    ]) {
      final offset = (corner.dy.round() * width + corner.dx.round()) * 4;
      expect(
        [for (var i = 0; i < 4; i++) data.getUint8(offset + i)],
        [0x33, 0x66, 0x99, 0xFF],
        reason: '$corner',
      );
    }
  });

  testWidgets('assistive actions move, size and turn the companion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final state = await editing(tester, FakePhotoAdapter());
    final canvas = find.semantics.byLabel(RegExp('사진 편집'));
    final start = state.editor.sticker;
    tester.semantics.customAction(canvas, PhotoCanvasActions.right);
    tester.semantics.customAction(canvas, PhotoCanvasActions.down);
    tester.semantics.customAction(canvas, PhotoCanvasActions.bigger);
    tester.semantics.customAction(canvas, PhotoCanvasActions.turnRight);
    await tester.pump();
    final s = state.editor.sticker;
    expect(s.x, closeTo(start.x + PhotoCanvasActions.move, 1e-9));
    expect(s.y, closeTo(start.y + PhotoCanvasActions.move, 1e-9));
    expect(s.scale, closeTo(start.scale * PhotoCanvasActions.grow, 1e-9));
    expect(s.rotation, closeTo(PhotoCanvasActions.turn, 1e-9));
    tester.semantics.customAction(canvas, PhotoCanvasActions.left);
    tester.semantics.customAction(canvas, PhotoCanvasActions.up);
    tester.semantics.customAction(canvas, PhotoCanvasActions.smaller);
    tester.semantics.customAction(canvas, PhotoCanvasActions.turnLeft);
    await tester.pump();
    final back = state.editor.sticker;
    expect(back.x, closeTo(start.x, 1e-9));
    expect(back.y, closeTo(start.y, 1e-9));
    expect(back.scale, closeTo(start.scale, 1e-9));
    expect(back.rotation, closeTo(0, 1e-9));
    // Still no visible slider: the actions live on the canvas itself.
    expect(find.byType(Slider), findsNothing);
    semantics.dispose();
  });

  testWidgets('flip and reset still work; a failed save keeps the edit', (
    tester,
  ) async {
    final adapter = FakePhotoAdapter();
    final state = await editing(tester, adapter);
    state.editor.edit(const DogSticker(x: .2, scale: .6, rotation: 1));
    await tester.tap(find.byKey(const ValueKey('photo_flip')));
    await tester.pump();
    expect(state.editor.sticker.flipped, isTrue);
    adapter.failure = const PhotoFailure('no space');
    final edit = state.editor.sticker;
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('photo_save'))),
    );
    await tester.runAsync(() => idle(state));
    await tester.pumpAndSettle();
    expect(state.editor.isError, isTrue);
    expect(state.editor.sticker, same(edit));
    expect(find.byKey(const ValueKey('photo_canvas')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo_reset')));
    await tester.pump();
    expect(state.editor.sticker.x, const DogSticker().x);
    expect(state.editor.sticker.rotation, 0);
    expect(state.editor.sticker.flipped, isFalse);
    expect(state.editor.sticker.scale, 1);
  });

  testWidgets('work in flight locks save, the tools and the way out', (
    tester,
  ) async {
    final adapter = PendingPhotoAdapter();
    final state = await editing(tester, adapter);
    adapter.pendingPick = Completer<Uint8List?>();
    final picking = state.editor.pick(PhotoSource.gallery);
    await tester.pump();
    for (final key in ['photo_save', 'photo_flip', 'photo_reset']) {
      expect(
        tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
        reason: key,
      );
    }
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('photo_back')))
          .onPressed,
      isNull,
    );
    adapter.pendingPick!.complete(null);
    await picking;
    await tester.pump();
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const ValueKey('photo_flip')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('on the Duo the rail takes the way out; save stays on top', (
    tester,
  ) async {
    useDuoViewport(tester, 'outer portrait');
    await editing(tester, FakePhotoAdapter(), wrap: duoHost);
    expect(find.byKey(const ValueKey('photo_back')), findsNothing);
    expect(find.byKey(const ValueKey('duo_rail_back')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('photo_save')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('photo_flip')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(1024, 768)]) {
    testWidgets('the editor fits $size at 1.15x', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await editing(
        tester,
        FakePhotoAdapter(),
        wrap: (screen) => MaterialApp(
          theme: meetingTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.15)),
            child: child!,
          ),
          home: screen,
        ),
      );
      for (final key in ['photo_save', 'photo_flip', 'photo_reset']) {
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
