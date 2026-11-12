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
      expect(spec['full'] ?? const {}, art.full, reason: id);
    }
    expect(json['backgrounds'], backgroundArt);
  });

  test('every picture a wearable combination names is bundled', () {
    final missing = <String>[];
    for (final MapEntry(key: id, value: art) in itemArt.entries) {
      final breeds = {...art.layered, for (final b in art.full.values) ...b};
      for (final breed in breeds) {
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

  test('a breed with only baked padding wears it alone and nothing else', () {
    final padded = lookFor('beagle', const [
      Worn('padding', 'tomato'),
      Worn('beanie', 'tomato'),
    ]);
    final hatOnly = lookFor('beagle', const [Worn('beanie', 'tomato')]);

    expect(padded.base, 'assets/wardrobe/items/padding/tomato/full/beagle.png');
    expect(padded.cuts, isEmpty);
    expect(padded.layers, isEmpty);
    expect(hatOnly.plain, isTrue);
    expect(hatOnly.base, 'assets/first_meeting/dogs/beagle.png');
    expect(hasArt('beagle', 'padding', 'navy'), isFalse);
  });
}
