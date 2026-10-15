import 'package:balmatchum_app/features/photo/photo_editor.dart';
import 'package:balmatchum_app/features/photo/platform_photo_adapter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('actual Gal adapter forwards PNG only after permission', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'requestAccess') return true;
      return null;
    });
    final png = Uint8List.fromList([137, 80, 78, 71]);
    await PlatformPhotoAdapter().save(png);
    final save = calls.singleWhere((call) => call.method == 'putImageBytes');
    expect((save.arguments as Map)['bytes'], orderedEquals(png));
    expect((save.arguments as Map)['album'], isNull);
  });

  test('denied Gal permission never invokes native save', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return false;
    });
    await expectLater(
      PlatformPhotoAdapter().save(Uint8List(0)),
      throwsA(isA<PhotoFailure>()),
    );
    expect(calls, ['requestAccess']);
  });
}
