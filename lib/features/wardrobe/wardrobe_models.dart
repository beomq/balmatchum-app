/// Wardrobe state is the server's generated `WardrobeStore`; the server decides
/// prices, ownership, what may be worn and whether a set is complete. This
/// file holds the actions the screen asks for and read helpers over the store.
library;

import 'package:balmatchum_client/balmatchum_client.dart' as api;

import 'wardrobe_art.dart';

enum WardrobeFailureReason {
  insufficientPoints,
  incompatible,
  subscriptionRequired,
  unavailable,
  other,
}

/// Throw from wardrobe actions to show a specific message.
class WardrobeActionException implements Exception {
  const WardrobeActionException(this.reason);
  final WardrobeFailureReason reason;
}

enum WardrobeActionKind {
  buyItem,
  buySet,
  buyBackground,
  wearItem,
  takeOffSlot,
  wearBackground,
  wearSet,
  takeOffSet,
}

/// One server write. [id] is an item, set, background or slot id.
class WardrobeAction {
  const WardrobeAction(this.kind, this.id, [this.colourId]);

  final WardrobeActionKind kind;
  final String id;
  final String? colourId;

  /// Stable per intent, so a retry reuses its request id.
  String get key => 'wardrobe:${kind.name}:$id:${colourId ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is WardrobeAction &&
      other.kind == kind &&
      other.id == id &&
      other.colourId == colourId;

  @override
  int get hashCode => Object.hash(kind, id, colourId);
}

typedef LoadWardrobe = Future<api.WardrobeStore> Function();
typedef RunWardrobeAction = Future<api.WardrobeStore> Function(
  WardrobeAction action,
);

const slotNames = {'head': '머리', 'torso': '몸', 'feet': '발'};

extension WardrobeRead on api.WardrobeStore {
  api.WardrobeItemView? item(String id) {
    for (final i in items) {
      if (i.itemId == id) return i;
    }
    return null;
  }

  api.WardrobeSetView? set(String id) {
    for (final s in sets) {
      if (s.setId == id) return s;
    }
    return null;
  }

  api.WardrobeBackgroundView? background(String id) {
    for (final b in backgrounds) {
      if (b.backgroundId == id) return b;
    }
    return null;
  }

  api.WardrobeColourView? colour(String id) {
    for (final c in colours) {
      if (c.colourId == id) return c;
    }
    return null;
  }

  String colourName(String id) => colour(id)?.name ?? id;

  api.WardrobeEquipView? wornIn(String slot) {
    for (final e in equipped) {
      if (e.slot == slot) return e;
    }
    return null;
  }

  List<Worn> get worn => [for (final e in equipped) Worn(e.itemId, e.colourId)];

  /// Whether this state shows [action] applied (used to settle a write
  /// whose answer was lost).
  bool confirms(WardrobeAction action) {
    final id = action.id;
    final colour = action.colourId;
    return switch (action.kind) {
      WardrobeActionKind.buyItem =>
        item(id)?.ownedColours.contains(colour) ?? false,
      WardrobeActionKind.buyBackground => background(id)?.owned ?? false,
      WardrobeActionKind.buySet =>
        (set(id)?.season?.granted ?? false) ||
            (set(id)?.colours
                    .any((c) => c.colourId == colour && c.missingParts == 0) ??
                false),
      WardrobeActionKind.wearItem => equipped.any(
        (e) => e.itemId == id && e.colourId == colour,
      ),
      WardrobeActionKind.takeOffSlot => wornIn(id) == null,
      WardrobeActionKind.wearBackground => equippedBackground == id,
      WardrobeActionKind.wearSet =>
        completeSetId == id && completeColour == colour,
      WardrobeActionKind.takeOffSet => !equipped.any(
        (e) => set(id)?.itemIds.contains(e.itemId) ?? false,
      ),
    };
  }

  /// What [breed] wears now, with the set band and effect when complete.
  DogLook look(String breed) {
    final complete = completeSetId == null ? null : set(completeSetId!);
    return lookFor(
      breed,
      worn,
    ).withSet(effect: complete?.effect, setName: complete?.name);
  }
}

/// Which set (and colour) [worn] over [background] completes, judged with the
/// server's own rule so a try-on can show the band before buying: every item
/// in one colour over that set's background.
(api.WardrobeSetView, String)? completedBy(
  api.WardrobeStore store,
  Map<String, Worn> worn,
  String background,
) {
  for (final set in store.sets) {
    if (set.backgroundId != background) continue;
    for (final colour in set.colours) {
      final all = set.itemIds.every((id) {
        final slot = store.item(id)?.slot;
        return slot != null && worn[slot] == Worn(id, colour.colourId);
      });
      if (all) return (set, colour.colourId);
    }
  }
  return null;
}
