import 'dart:ui' as ui;

import 'package:balmatchum_app/features/photo/photo_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePhotoAdapter implements PhotoAdapter {
  Uint8List? next;
  Object? failure;
  Uint8List? saved;
  Uint8List? shared;
  PhotoSource? source;
  PhotoShareResult shareResult = PhotoShareResult.cancelled;
  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    this.source = source;
    if (failure != null) throw failure!;
    return next;
  }

  @override
  Future<Uint8List?> recoverLostPhoto() async => null;
  @override
  Future<void> save(Uint8List png) async {
    if (failure != null) throw failure!;
    saved = png;
  }

  @override
  Future<PhotoShareResult> share(Uint8List png, ui.Rect origin) async {
    if (failure != null) throw failure!;
    shared = png;
    return shareResult;
  }
}

Future<Uint8List> photoFixture() async {
  final data = await rootBundle.load('assets/first_meeting/sunny.png');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('normalized transform clamps limits and preserves sprite ratio', () {
    final s = const DogSticker().copyWith(
      x: -1,
      y: 2,
      scale: 10,
      flipped: true,
      rotation: 1,
    );
    expect(s.x, 0);
    expect(s.y, 1);
    expect(s.scale, 3);
    expect(s.flipped, isTrue);
    final rect = s.rect(const ui.Size(400, 800), const ui.Size(100, 200));
    expect(rect.width / rect.height, .5);
    expect(rect.center, const ui.Offset(0, 800));
  });

  test(
    'cancel, invalid replacement and permission denial preserve edit',
    () async {
      final adapter = FakePhotoAdapter()..next = await photoFixture();
      final editor = PhotoEditor(
        adapter: adapter,
        dogAssetPath: 'assets/first_meeting/dogs/pug.png',
      );
      addTearDown(editor.dispose);
      await editor.initialize();
      await editor.pick(PhotoSource.gallery);
      editor.edit(const DogSticker(x: .2, flipped: true));
      final original = editor.photo;
      final edit = editor.sticker;
      adapter.next = null;
      await editor.pick(PhotoSource.camera);
      expect(adapter.source, PhotoSource.camera);
      expect(editor.photo, same(original));
      expect(editor.sticker, same(edit));
      adapter.next = Uint8List.fromList([1, 2, 3]);
      await editor.pick(PhotoSource.gallery);
      expect(editor.isError, isTrue);
      expect(editor.photo, same(original));
      expect(editor.sticker, same(edit));
      adapter.failure = const PhotoFailure('denied');
      await editor.save();
      expect(editor.isError, isTrue);
      expect(adapter.saved, isNull);
      expect(editor.sticker, same(edit));
    },
  );

  test('export is composited PNG and share cancellation keeps edit', () async {
    final adapter = FakePhotoAdapter()..next = await photoFixture();
    final source = Uint8List.fromList(adapter.next!);
    final editor = PhotoEditor(
      adapter: adapter,
      dogAssetPath: 'assets/first_meeting/dogs/pug.png',
    );
    addTearDown(editor.dispose);
    await editor.initialize();
    await editor.pick(PhotoSource.gallery);
    final png = await editor.capturePng();
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png, isNot(orderedEquals(source)));
    expect(adapter.next, orderedEquals(source));
    final codec = await ui.instantiateImageCodec(png);
    final output = (await codec.getNextFrame()).image;
    expect(output.width, editor.photo!.width);
    expect(output.height, editor.photo!.height);
    output.dispose();
    codec.dispose();
    editor.edit(editor.sticker.copyWith(rotation: 1, scale: .6));
    final changed = await editor.capturePng();
    expect(changed, isNot(orderedEquals(png)));
    final edit = editor.sticker;
    await editor.share(const ui.Rect.fromLTWH(0, 0, 44, 44));
    expect(editor.sticker, same(edit));
    expect(editor.isError, isFalse);
    expect(adapter.shared, orderedEquals(changed));
    await editor.save();
    expect(adapter.saved, orderedEquals(changed));
  });
}
