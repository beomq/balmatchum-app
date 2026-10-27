/// UI view models for the wardrobe theme and outfit catalogs. The parent maps
/// generated client models into these; they are not wire DTOs.
library;

/// Server id of the only outfit approved for the first release.
const vestOutfitId = 'vest-low-v';

/// Approved vest layers by breed. Each layer shares its base sprite's exact
/// canvas, so it is drawn with the base image's own fit and alignment.
const vestLayers = <String, String>{
  'shih-tzu': 'assets/wardrobe/vest/shih-tzu.png',
  'dachshund': 'assets/wardrobe/vest/dachshund.png',
};

class WardrobeTheme {
  const WardrobeTheme({
    required this.id,
    required this.name,
    required this.owned,
    required this.colorValue,
    this.price,
    this.backgroundAsset,
  });

  final String id;
  final String name;
  final bool owned;

  /// Server `ThemeItem.colorValue` (ARGB), used when no approved image exists.
  final int colorValue;

  /// Null when the server has not confirmed a price; never invented.
  final int? price;

  /// An already-approved bundled background, for example
  /// `assets/first_meeting/sunny.png`. Null shows a neutral placeholder.
  final String? backgroundAsset;
}

class WardrobeOutfit {
  const WardrobeOutfit({
    required this.id,
    required this.name,
    required this.price,
    required this.owned,
    required this.compatible,
  });

  final String id;
  final String name;
  final int price;
  final bool owned;

  /// The server allows the profile's breed; false without a profile.
  final bool compatible;

  /// The layer drawn over the [breedId] sprite, or null when that sprite
  /// cannot wear this outfit. A missing layer is never borrowed from another
  /// breed.
  String? layerFor(String breedId) =>
      compatible && id == vestOutfitId ? vestLayers[breedId] : null;
}

/// Server outfit state after load, purchase, wear or removal.
class WardrobeOutfits {
  const WardrobeOutfits({required this.items, this.equippedId});

  final List<WardrobeOutfit> items;

  /// Null when the companion wears nothing.
  final String? equippedId;

  /// The layer to draw over the [breedId] sprite, or null.
  String? wornLayer(String breedId) {
    for (final item in items) {
      if (item.id == equippedId) return item.layerFor(breedId);
    }
    return null;
  }
}

/// Server state after load, purchase or equip.
class WardrobeSnapshot {
  const WardrobeSnapshot({
    required this.themes,
    required this.equippedThemeId,
    this.balance,
    this.fixtureLabel,
    this.outfits,
  });

  final List<WardrobeTheme> themes;
  final String? equippedThemeId;

  /// Null when the server balance is unknown.
  final int? balance;

  /// Non-null when prices/balance are development fixtures.
  final String? fixtureLabel;

  /// Null when the outfit state could not be confirmed; themes still work.
  final WardrobeOutfits? outfits;
}

enum WardrobeFailureReason {
  insufficientPoints,
  incompatible,
  unavailable,
  other,
}

/// Throw from purchase/equip callbacks to show a specific message.
class WardrobeActionException implements Exception {
  const WardrobeActionException(this.reason);
  final WardrobeFailureReason reason;
}

typedef LoadWardrobe = Future<WardrobeSnapshot> Function();
typedef WardrobeThemeAction = Future<WardrobeSnapshot> Function(
  WardrobeTheme theme,
);

enum OutfitChange { purchase, wear, remove }

typedef WardrobeOutfitAction = Future<WardrobeSnapshot> Function(
  WardrobeOutfit outfit,
  OutfitChange change,
);
