import 'dart:ui' as ui;

import 'package:balmatchum_app/features/wardrobe/dog_sprite.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Native canvas of each approved sprite; its vest layer shares it.
const canvases = <String, Size>{
  'shih-tzu': Size(684, 676),
  'dachshund': Size(512, 512),
};

final boundaryKey = GlobalKey();

/// Pumps [child] at [size] logical pixels (device pixel ratio 1), waits for
/// its asset images to decode, and returns the painted RGBA bytes.
Future<Uint8List> render(
  WidgetTester tester,
  Size size,
  Widget child,
  List<String> assets,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    ),
  );
  final context = boundaryKey.currentContext!;
  await tester.runAsync(() async {
    for (final asset in assets) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pump();
  final bytes = await tester.runAsync(() async {
    final boundary = context.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.physicalSize = const Size(1000, 1000);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  for (final MapEntry(key: breed, value: vest) in vestLayers.entries) {
    testWidgets('$breed base pixels are unchanged by wearing the vest', (
      tester,
    ) async {
      final size = canvases[breed]!;
      final base = 'assets/first_meeting/dogs/$breed.png';

      final offBefore = await render(tester, size, DogSprite(asset: base), [
        base,
      ]);
      final on = await render(
        tester,
        size,
        DogSprite(asset: base, layer: vest),
        [base, vest],
      );
      final offAfter = await render(tester, size, DogSprite(asset: base), [
        base,
      ]);
      final vestOnly = await render(
        tester,
        size,
        Image.asset(
          vest,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        ),
        [vest],
      );

      // Removing the vest restores the exact pre-wear picture.
      expect(listEquals(offBefore, offAfter), isTrue);

      // Outside the vest's own alpha, worn and bare pixels are identical.
      var vestPixels = 0;
      var comparedBasePixels = 0;
      var changedBasePixels = 0;
      for (var i = 0; i < on.length; i += 4) {
        if (vestOnly[i + 3] != 0) {
          vestPixels++;
          continue;
        }
        if (offBefore[i + 3] != 0) comparedBasePixels++;
        for (var c = 0; c < 4; c++) {
          if (on[i + c] != offBefore[i + c]) {
            changedBasePixels++;
            break;
          }
        }
      }
      expect(vestPixels, greaterThan(0), reason: 'vest mask is empty');
      expect(comparedBasePixels, greaterThan(0), reason: 'no base pixels');
      expect(listEquals(on, offBefore), isFalse, reason: 'vest not drawn');
      expect(changedBasePixels, 0);
    });
  }
}
