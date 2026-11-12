/// Bundled wardrobe art: which layers exist for which breed, and how a worn
/// combination is stacked (DESIGN.md 3-4). The server decides what is owned,
/// worn and complete; this only maps that to pictures.
///
/// Mirrors assets/wardrobe/catalog.json (written by the art export script);
/// a test keeps the two equal.
library;

import 'package:flutter/foundation.dart';

class ItemArt {
  const ItemArt({
    required this.slot,
    required this.colours,
    required this.layered,
    this.fur = false,
    this.over = false,
    this.full = const {},
  });

  final String slot;
  final List<String> colours;

  /// Breeds with a layer per colour plus a cut mask (combinable).
  final List<String> layered;
  final bool fur;
  final bool over;

  /// Colour -> breeds whose only art is this item baked onto the whole dog.
  final Map<String, List<String>> full;
}

const layeredBreeds = ['maltese', 'dachshund', 'golden-retriever'];
const _winter = ['tomato', 'pine', 'plum', 'navy'];
const _holiday = ['tomato', 'pine', 'navy'];
const _seollal = ['dahong', 'jjok', 'yeondu', 'bunhong'];

const bakedPaddingBreeds = [
  'alaskan-malamute',
  'beagle',
  'bichon-frise',
  'border-collie',
  'boston-terrier',
  'bulldog',
  'chihuahua',
  'cocker-spaniel',
  'dalmatian',
  'french-bulldog',
  'german-shepherd',
  'jindo',
  'labrador-retriever',
  'miniature-pinscher',
  'miniature-schnauzer',
  'norwich-terrier',
  'pekingese',
  'pembroke-welsh-corgi',
  'pomeranian',
  'pug',
  'samoyed',
  'shiba-inu',
  'shih-tzu',
  'siberian-husky',
  'toy-poodle',
  'west-highland-white-terrier',
  'yorkshire-terrier',
];

const itemArt = <String, ItemArt>{
  'padding': ItemArt(
    slot: 'torso',
    colours: _winter,
    layered: layeredBreeds,
    over: true,
    full: {'tomato': bakedPaddingBreeds},
  ),
  'beanie': ItemArt(
    slot: 'head',
    colours: _winter,
    layered: layeredBreeds,
    fur: true,
    over: true,
  ),
  'booties': ItemArt(
    slot: 'feet',
    colours: _winter,
    layered: layeredBreeds,
    over: true,
  ),
  'rudolph-band': ItemArt(
    slot: 'head',
    colours: _holiday,
    layered: layeredBreeds,
    fur: true,
    over: true,
  ),
  'santa-cape': ItemArt(
    slot: 'torso',
    colours: _holiday,
    layered: layeredBreeds,
    over: true,
  ),
  'saekdong-jeogori': ItemArt(
    slot: 'torso',
    colours: _seollal,
    layered: layeredBreeds,
    over: true,
  ),
  'gulle': ItemArt(
    slot: 'head',
    colours: _seollal,
    layered: layeredBreeds,
    fur: true,
    over: true,
  ),
  'vest': ItemArt(
    slot: 'torso',
    colours: ['classic'],
    layered: ['dachshund', 'shih-tzu'],
  ),
};

/// Every background picture by server id.
const backgroundArt = <String, String>{
  'sunny': 'assets/first_meeting/sunny.png',
  'cloudy': 'assets/first_meeting/cloudy.png',
  'rainy': 'assets/first_meeting/rainy.png',
  'snowy': 'assets/first_meeting/snowy.png',
  'winter-dusk': 'assets/wardrobe/backgrounds/winter-dusk.png',
  'holiday-night': 'assets/wardrobe/backgrounds/holiday-night.png',
  'seollal-morning': 'assets/wardrobe/backgrounds/seollal-morning.png',
};

/// Slots in drawing order, back to front. A head item's fur ring goes in
/// before the torso so a collar can cover it (hat-fix).
const slotOrder = ['feet', 'head', 'torso'];

/// One worn item and colour.
@immutable
class Worn {
  const Worn(this.itemId, this.colourId);
  final String itemId;
  final String colourId;

  @override
  bool operator ==(Object other) =>
      other is Worn && other.itemId == itemId && other.colourId == colourId;

  @override
  int get hashCode => Object.hash(itemId, colourId);
}

/// The pictures for one dog wearing a combination: the base (or a baked
/// full-dog picture), the masks erased from it, then layers back to front.
@immutable
class DogLook {
  const DogLook({
    required this.base,
    this.cuts = const [],
    this.layers = const [],
    this.effect,
    this.setName,
  });

  final String base;
  final List<String> cuts;
  final List<String> layers;

  /// Effect preset of a complete set, else null.
  final String? effect;

  /// Name of the complete set for its band, else null.
  final String? setName;

  bool get plain => cuts.isEmpty && layers.isEmpty;

  /// Same pictures, also used as the cache key of the composed image.
  String get key => [base, ...cuts, '|', ...layers].join(',');

  DogLook withSet({String? effect, String? setName}) => DogLook(
    base: base,
    cuts: cuts,
    layers: layers,
    effect: effect,
    setName: setName,
  );

  @override
  bool operator ==(Object other) =>
      other is DogLook &&
      other.key == key &&
      other.effect == effect &&
      other.setName == setName;

  @override
  int get hashCode => Object.hash(key, effect, setName);
}

String dogAsset(String breed) => 'assets/first_meeting/dogs/$breed.png';

/// Whether this breed has a picture of [itemId] in [colourId].
bool hasArt(String breed, String itemId, String colourId) {
  final art = itemArt[itemId];
  if (art == null || !art.colours.contains(colourId)) return false;
  return art.layered.contains(breed) ||
      (art.full[colourId]?.contains(breed) ?? false);
}

/// Stacks [worn] on [breed] (DESIGN.md 4): erase every cut, then feet, head
/// fur, torso, head, then every over-fur layer. A baked full-dog item replaces
/// the base and is worn alone. Items without art for this breed are skipped,
/// never borrowed from another breed.
DogLook lookFor(String breed, Iterable<Worn> worn) {
  final bySlot = <String, Worn>{};
  for (final w in worn) {
    final art = itemArt[w.itemId];
    if (art != null && hasArt(breed, w.itemId, w.colourId)) {
      bySlot[art.slot] = w;
    }
  }
  for (final w in bySlot.values) {
    final art = itemArt[w.itemId]!;
    if (art.full[w.colourId]?.contains(breed) ?? false) {
      return DogLook(
        base: 'assets/wardrobe/items/${w.itemId}/${w.colourId}/full/$breed.png',
      );
    }
  }
  final cuts = <String>[];
  final layers = <String>[];
  final overs = <String>[];
  String dir(Worn w) => 'assets/wardrobe/items/${w.itemId}';
  for (final slot in slotOrder) {
    final w = bySlot[slot];
    if (w == null) continue;
    final art = itemArt[w.itemId]!;
    if (w.itemId != 'vest') cuts.add('${dir(w)}/cut/$breed.png');
    if (art.over) overs.add('${dir(w)}/over/$breed.png');
  }
  final head = bySlot['head'];
  if (bySlot['feet'] case final w?) {
    layers.add('${dir(w)}/${w.colourId}/$breed.png');
  }
  if (head != null && itemArt[head.itemId]!.fur) {
    layers.add('${dir(head)}/fur/$breed.png');
  }
  if (bySlot['torso'] case final w?) {
    layers.add('${dir(w)}/${w.colourId}/$breed.png');
  }
  if (head != null) layers.add('${dir(head)}/${head.colourId}/$breed.png');
  return DogLook(
    base: dogAsset(breed),
    cuts: cuts,
    layers: [...layers, ...overs],
  );
}
