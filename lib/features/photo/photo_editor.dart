import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PhotoSource { gallery, camera }

enum PhotoShareResult { selected, cancelled, unavailable }

abstract interface class PhotoAdapter {
  Future<Uint8List?> pick(PhotoSource source);
  Future<Uint8List?> recoverLostPhoto();
  Future<void> save(Uint8List png);
  Future<PhotoShareResult> share(Uint8List png, ui.Rect origin);
}

class PhotoFailure implements Exception {
  const PhotoFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Coordinates are fractions of the photo, so window resizing preserves edits.
@immutable
class DogSticker {
  const DogSticker({
    this.x = .5,
    this.y = .65,
    this.scale = 1,
    this.rotation = 0,
    this.flipped = false,
  });

  final double x;
  final double y;
  final double scale;
  final double rotation;
  final bool flipped;

  DogSticker copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    bool? flipped,
  }) => DogSticker(
    x: (x ?? this.x).clamp(0, 1),
    y: (y ?? this.y).clamp(0, 1),
    scale: (scale ?? this.scale).clamp(.3, 3),
    rotation: rotation ?? this.rotation,
    flipped: flipped ?? this.flipped,
  );

  ui.Rect rect(ui.Size photo, ui.Size dog) {
    final width = math.min(photo.width, photo.height) * .4 * scale;
    return ui.Rect.fromCenter(
      center: ui.Offset(x * photo.width, y * photo.height),
      width: width,
      height: width * dog.height / dog.width,
    );
  }
}

/// Used by both preview and export; no UI controls enter the exported pixels.
void paintPhoto(
  ui.Canvas canvas,
  ui.Size size,
  ui.Image photo,
  ui.Image dog,
  DogSticker sticker,
) {
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  canvas.drawImageRect(
    photo,
    ui.Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
    ui.Offset.zero & size,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final rect = sticker.rect(
    size,
    ui.Size(dog.width.toDouble(), dog.height.toDouble()),
  );
  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  canvas.rotate(sticker.rotation);
  canvas.scale(sticker.flipped ? -1 : 1, 1);
  canvas.drawImageRect(
    dog,
    ui.Rect.fromLTWH(0, 0, dog.width.toDouble(), dog.height.toDouble()),
    ui.Rect.fromCenter(
      center: ui.Offset.zero,
      width: rect.width,
      height: rect.height,
    ),
    paint,
  );
  canvas.restore();
}

class PhotoEditor extends ChangeNotifier {
  PhotoEditor({required this.adapter, required this.dogAssetPath});
  final PhotoAdapter adapter;
  final String dogAssetPath;
  ui.Image? photo;
  ui.Image? dog;
  DogSticker sticker = const DogSticker();
  bool busy = false;
  String? message;
  bool isError = false;
  bool _disposed = false;

  bool get canExport => photo != null && dog != null && !busy;

  Future<ui.Image> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final ratio = math.min(1.0, 4096 / math.max(width, height));
        return ui.TargetImageSize(
          width: math.max(1, (width * ratio).round()),
          height: math.max(1, (height * ratio).round()),
        );
      },
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> initialize() => _run(() async {
    if (dog == null) {
      final bytes = await rootBundle.load(dogAssetPath);
      final loaded = await _decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      if (_disposed) {
        loaded.dispose();
        return;
      }
      dog = loaded;
    }
    final recovered = await adapter.recoverLostPhoto();
    if (recovered != null) await _replace(recovered);
  });

  Future<void> _replace(Uint8List bytes) async {
    // Decode first: cancelled/invalid replacements never discard the current edit.
    final loaded = await _decode(bytes);
    if (_disposed) {
      loaded.dispose();
      return;
    }
    photo?.dispose();
    photo = loaded;
    sticker = const DogSticker();
  }

  Future<void> pick(PhotoSource source) => _run(() async {
    final bytes = await adapter.pick(source);
    if (bytes != null) await _replace(bytes);
  });

  void edit(DogSticker value) {
    if (busy || photo == null) return;
    sticker = value;
    message = null;
    notifyListeners();
  }

  Future<Uint8List> capturePng() async {
    final image = photo;
    final sprite = dog;
    if (image == null || sprite == null) {
      throw const PhotoFailure('사진과 강아지를 먼저 불러와 주세요.');
    }
    // Bound GPU allocation while preserving photo aspect ratio and all edits.
    final ratio = math.min(1.0, 4096 / math.max(image.width, image.height));
    final width = (image.width * ratio).round();
    final height = (image.height * ratio).round();
    final recorder = ui.PictureRecorder();
    paintPhoto(
      ui.Canvas(recorder),
      ui.Size(width.toDouble(), height.toDouble()),
      image,
      sprite,
      sticker,
    );
    final picture = recorder.endRecording();
    try {
      final composite = await picture.toImage(width, height);
      try {
        final data = await composite.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const PhotoFailure('사진을 만들지 못했어요. 다시 시도해 주세요.');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        composite.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Future<void> save() => _run(() async {
    await adapter.save(await capturePng());
    message = '합성한 사진을 갤러리에 저장했어요.';
  });

  Future<void> share(ui.Rect origin) => _run(() async {
    final result = await adapter.share(await capturePng(), origin);
    message = switch (result) {
      PhotoShareResult.selected => '공유할 앱을 선택했어요.',
      PhotoShareResult.cancelled => '공유를 취소했어요. 편집은 그대로예요.',
      PhotoShareResult.unavailable => '공유 결과를 확인할 수 없어요. 편집은 그대로예요.',
    };
  });

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    isError = false;
    notifyListeners();
    try {
      await action();
    } on PhotoFailure catch (error) {
      message = error.message;
      isError = true;
    } catch (_) {
      message = '사진 작업을 완료하지 못했어요. 편집은 유지돼요. 다시 시도해 주세요.';
      isError = true;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    photo?.dispose();
    dog?.dispose();
    super.dispose();
  }
}
