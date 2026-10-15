/// UI view models for the wardrobe theme catalog. The parent maps generated
/// client models into these; they are not wire DTOs.
library;

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

/// Server state after load, purchase or equip.
class WardrobeSnapshot {
  const WardrobeSnapshot({
    required this.themes,
    required this.equippedThemeId,
    this.balance,
    this.fixtureLabel,
  });

  final List<WardrobeTheme> themes;
  final String? equippedThemeId;

  /// Null when the server balance is unknown.
  final int? balance;

  /// Non-null when prices/balance are development fixtures.
  final String? fixtureLabel;
}

enum WardrobeFailureReason { insufficientPoints, unavailable, other }

/// Throw from purchase/equip callbacks to show a specific message.
class WardrobeActionException implements Exception {
  const WardrobeActionException(this.reason);
  final WardrobeFailureReason reason;
}

typedef LoadWardrobe = Future<WardrobeSnapshot> Function();
typedef WardrobeThemeAction = Future<WardrobeSnapshot> Function(
  WardrobeTheme theme,
);
