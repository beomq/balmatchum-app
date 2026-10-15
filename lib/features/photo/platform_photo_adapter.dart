import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'photo_editor.dart';

/// Local platform operations only. The source file is never written or uploaded.
class PlatformPhotoAdapter implements PhotoAdapter {
  PlatformPhotoAdapter({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.gallery
            ? ImageSource.gallery
            : ImageSource.camera,
        requestFullMetadata: false,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      return file == null ? null : await file.readAsBytes();
    } on PlatformException catch (error) {
      throw PhotoFailure(
        error.code.contains('denied') || error.code.contains('restricted')
            ? '사진 또는 카메라 권한이 필요해요. OS 설정에서 권한을 확인한 뒤 다시 시도해 주세요.'
            : '사진을 불러오지 못했어요. 카메라와 사진 접근 상태를 확인해 주세요.',
      );
    }
  }

  @override
  Future<Uint8List?> recoverLostPhoto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final result = await _picker.retrieveLostData();
    if (result.exception != null) {
      throw const PhotoFailure('이전 사진 선택을 복구하지 못했어요. 다시 선택해 주세요.');
    }
    final files = result.files;
    return files == null || files.isEmpty
        ? null
        : await files.first.readAsBytes();
  }

  @override
  Future<void> save(Uint8List png) async {
    try {
      if (!await Gal.requestAccess()) {
        throw const PhotoFailure(
          '저장 권한이 없어요. OS 설정에서 사진 저장 권한을 확인하고 다시 시도해 주세요.',
        );
      }
      await Gal.putImageBytes(
        png,
        name: 'balmatchum-${DateTime.now().microsecondsSinceEpoch}',
      );
    } on GalException catch (error) {
      throw PhotoFailure(switch (error.type) {
        GalExceptionType.accessDenied =>
          '저장 권한이 없어요. OS 설정에서 사진 저장 권한을 확인해 주세요.',
        GalExceptionType.notEnoughSpace => '저장 공간이 부족해요. 공간을 확보하고 다시 시도해 주세요.',
        GalExceptionType.notSupportedFormat => '이 기기에서 PNG 저장을 지원하지 않아요.',
        GalExceptionType.unexpected => '사진을 저장하지 못했어요. 편집은 그대로예요.',
      });
    }
  }

  @override
  Future<PhotoShareResult> share(Uint8List png, Rect origin) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png')],
        fileNameOverrides: ['balmatchum-photo.png'],
        sharePositionOrigin: origin,
        downloadFallbackEnabled: false,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => PhotoShareResult.selected,
      ShareResultStatus.dismissed => PhotoShareResult.cancelled,
      ShareResultStatus.unavailable => PhotoShareResult.unavailable,
    };
  }
}
