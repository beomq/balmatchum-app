import 'dart:ui' as ui;

import 'package:balmatchum_app/features/wardrobe/dog_sprite.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_art.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const size = Size(512, 512);
final boundaryKey = GlobalKey();

/// Pumps [child] at 512 x 512 logical pixels (device pixel ratio 1), lets its
/// asset images decode, and returns the painted RGBA bytes.
Future<Uint8List> render(
  WidgetTester tester,
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
  // The layered sprite decodes through image streams; let them deliver.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  final bytes = await tester.runAsync(() async {
    final boundary = context.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

Future<Uint8List> picture(WidgetTester tester, String asset) => render(
  tester,
  Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.none),
  [asset],
);

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

  testWidgets(
    'worn padding erases its cut and taking it off restores the dog',
    (tester) async {
      final base = dogAsset('maltese');
      final look = lookFor('maltese', const [Worn('padding', 'tomato')]);
      final assets = [look.base, ...look.cuts, ...look.layers];

      final before = await render(tester, DogSprite(asset: base), [base]);
      final worn = await render(
        tester,
        DogSprite(asset: base, look: look),
        assets,
      );
      final after = await render(tester, DogSprite(asset: base), [base]);
      final cut = await picture(tester, look.cuts.single);
      final layers = [for (final l in look.layers) await picture(tester, l)];

      expect(listEquals(before, after), isTrue);
      var erased = 0;
      var kept = 0;
      var keptChanged = 0;
      for (var i = 0; i < worn.length; i += 4) {
        final covered = layers.any((l) => l[i + 3] != 0);
        if (cut[i + 3] != 0 && !covered && before[i + 3] != 0) {
          // Old outline under the cut is gone, not drawn over.
          expect(worn[i + 3], 0);
          erased++;
        } else if (cut[i + 3] == 0 && !covered) {
          kept++;
          for (var c = 0; c < 4; c++) {
            if (worn[i + c] != before[i + c]) {
              keptChanged++;
              break;
            }
          }
        }
      }
      expect(erased, greaterThan(0), reason: 'cut erased nothing');
      expect(kept, greaterThan(0));
      expect(keptChanged, 0, reason: 'pixels outside cut and layers changed');
    },
  );

  testWidgets('the worn sprite releases every image handle it receives', (
    tester,
  ) async {
    final base = dogAsset('maltese');
    final tomato = lookFor('maltese', const [Worn('padding', 'tomato')]);
    final pine = lookFor('maltese', const [Worn('padding', 'pine')]);

    /// Image handles still open after [body] and a full teardown.
    Future<int> leftOver(Future<void> Function() body) async {
      // Start from an empty cache so earlier tests cannot shift the count.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      final open = <ui.Image>{};
      ui.Image.onCreate = open.add;
      ui.Image.onDispose = open.remove;
      try {
        await body();
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
        await tester.pump();
        return open.length;
      } finally {
        ui.Image.onCreate = null;
        ui.Image.onDispose = null;
      }
    }

    Future<void> wear(DogLook look) => render(
      tester,
      DogSprite(asset: base, look: look),
      [look.base, ...look.cuts, ...look.layers],
    );

    // Baseline: the plain sprite with the same pictures decoded into the
    // cache, so only handles the worn sprite keeps can differ.
    final pictures = {
      for (final look in [tomato, pine]) ...[
        look.base,
        ...look.cuts,
        ...look.layers,
      ],
    }.toList();
    final plain = await leftOver(
      () => render(tester, DogSprite(asset: base), pictures),
    );
    final worn = await leftOver(() async {
      await wear(tomato);
      // Changing the look replaces the decoded stack.
      await wear(pine);
    });

    expect(worn, plain);
  });

  testWidgets('padding is drawn over the booties where they overlap', (
    tester,
  ) async {
    final base = dogAsset('maltese');
    final look = lookFor('maltese', const [
      Worn('booties', 'pine'),
      Worn('padding', 'tomato'),
    ]);
    final padding = 'assets/wardrobe/items/padding/tomato/maltese.png';
    final booties = 'assets/wardrobe/items/booties/pine/maltese.png';
    final overs = [
      for (final l in look.layers)
        if (l.contains('/over/')) l,
    ];

    final worn = await render(tester, DogSprite(asset: base, look: look), [
      look.base,
      ...look.cuts,
      ...look.layers,
    ]);
    final top = await picture(tester, padding);
    final under = await picture(tester, booties);
    final overPictures = [for (final o in overs) await picture(tester, o)];

    var overlap = 0;
    for (var i = 0; i < worn.length; i += 4) {
      if (top[i + 3] != 255 || under[i + 3] == 0) continue;
      if (overPictures.any((o) => o[i + 3] != 0)) continue;
      overlap++;
      expect(worn.sublist(i, i + 4), top.sublist(i, i + 4));
    }
    expect(overlap, greaterThan(0), reason: 'no padding/booties overlap');
  });
}
