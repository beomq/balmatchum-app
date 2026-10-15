import 'package:balmatchum_app/features/photo/photo_editor.dart';
import 'package:balmatchum_app/features/photo/platform_photo_adapter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class NativeSaveAdapter extends PlatformPhotoAdapter {
  @override
  Future<Uint8List?> recoverLostPhoto() async => null;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final bytes = await rootBundle.load('assets/first_meeting/sunny.png');
    return bytes.buffer.asUint8List();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native photo gallery receives composite PNG', (tester) async {
    final editor = PhotoEditor(
      adapter: NativeSaveAdapter(),
      dogAssetPath: 'assets/first_meeting/dogs/pug.png',
    );
    await editor.initialize();
    await editor.pick(PhotoSource.gallery);
    editor.edit(const DogSticker(x: .6, y: .6, rotation: .2, flipped: true));
    await editor.save();
    expect(editor.isError, isFalse);
    expect(editor.photo, isNotNull);
    editor.dispose();
  });
}
