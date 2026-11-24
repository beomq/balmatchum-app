import 'dart:convert';
import 'dart:io';

import 'package:balmatchum_app/features/wardrobe/wardrobe_art.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Dart art table equals the exported catalog.json', () {
    final json = jsonDecode(
      File('assets/wardrobe/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final items = json['items'] as Map<String, dynamic>;
    expect(items.keys, unorderedEquals(itemArt.keys));
    for (final MapEntry(key: id, value: art) in itemArt.entries) {
      final spec = items[id] as Map<String, dynamic>;
      expect(spec['slot'], art.slot, reason: id);
      expect(spec['colours'], art.colours, reason: id);
      expect(spec['layered'], art.layered, reason: id);
      expect(spec['fur'], art.fur, reason: id);
      expect(spec['over'], art.over, reason: id);
      expect(spec.containsKey('full'), isFalse, reason: id);
    }
    expect(json['backgrounds'], backgroundArt);
  });

  test('every picture a wearable combination names is bundled', () {
    final missing = <String>[];
    for (final MapEntry(key: id, value: art) in itemArt.entries) {
      for (final breed in art.layered) {
        for (final colour in art.colours) {
          if (!hasArt(breed, id, colour)) continue;
          final look = lookFor(breed, [Worn(id, colour)]);
          for (final path in [look.base, ...look.cuts, ...look.layers]) {
            if (!File(path).existsSync()) missing.add(path);
          }
        }
      }
    }
    for (final path in backgroundArt.values) {
      if (!File(path).existsSync()) missing.add(path);
    }
    expect(missing, isEmpty);
  });

  test('pubspec declares every wardrobe picture folder so it is bundled', () {
    final declared = {
      for (final line in File('pubspec.yaml').readAsLinesSync())
        if (line.trim() case final entry when entry.startsWith('- assets/'))
          entry.substring(2),
    };
    final folders = {
      for (final file in Directory('assets/wardrobe').listSync(recursive: true))
        if (file is File && file.path.endsWith('.png')) '${file.parent.path}/',
    };
    expect(folders.difference(declared), isEmpty);
  });

  test('a layered breed stacks feet, head fur, torso, head, then over fur', () {
    final look = lookFor('maltese', const [
      Worn('beanie', 'pine'),
      Worn('padding', 'tomato'),
      Worn('booties', 'navy'),
    ]);

    const dir = 'assets/wardrobe/items';
    expect(look.base, 'assets/first_meeting/dogs/maltese.png');
    expect(look.cuts, [
      '$dir/booties/cut/maltese.png',
      '$dir/beanie/cut/maltese.png',
      '$dir/padding/cut/maltese.png',
    ]);
    expect(look.layers, [
      '$dir/booties/navy/maltese.png',
      '$dir/beanie/fur/maltese.png',
      '$dir/padding/tomato/maltese.png',
      '$dir/beanie/pine/maltese.png',
      '$dir/booties/over/maltese.png',
      '$dir/beanie/over/maltese.png',
      '$dir/padding/over/maltese.png',
    ]);
  });

  test('a formerly baked-padding breed now layers items like any other', () {
    final look = lookFor('beagle', const [
      Worn('padding', 'navy'),
      Worn('rib-beanie', 'cream'),
      Worn('vest', 'classic'),
    ]);

    const dir = 'assets/wardrobe/items';
    expect(look.base, 'assets/first_meeting/dogs/beagle.png');
    expect(look.cuts, [
      '$dir/rib-beanie/cut/beagle.png',
      '$dir/padding/cut/beagle.png',
    ]);
    expect(look.layers, [
      '$dir/rib-beanie/fur/beagle.png',
      '$dir/padding/navy/beagle.png',
      '$dir/rib-beanie/cream/beagle.png',
      '$dir/rib-beanie/over/beagle.png',
      '$dir/padding/over/beagle.png',
    ]);
    // The vest art still exists only for dachshund and shih-tzu.
    expect(hasArt('beagle', 'vest', 'classic'), isFalse);
  });
}
