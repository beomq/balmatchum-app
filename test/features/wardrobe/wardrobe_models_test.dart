import 'package:balmatchum_app/features/first_meeting/domain/dog_catalog.dart';
import 'package:balmatchum_app/features/wardrobe/wardrobe_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG IHDR width and height (big-endian, right after the signature).
(int, int) canvas(ByteData png) => (png.getUint32(16), png.getUint32(20));

const wearable = WardrobeOutfit(
  id: vestOutfitId,
  name: 'Vest',
  price: 3,
  owned: true,
  compatible: true,
);
const refused = WardrobeOutfit(
  id: vestOutfitId,
  name: 'Vest',
  price: 3,
  owned: true,
  compatible: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each vest layer is bundled on its base sprite canvas', () async {
    for (final MapEntry(key: breed, value: layer) in vestLayers.entries) {
      final base = await rootBundle.load(
        FirstMeetingCatalog.byId(breed).spritePath,
      );
      expect(canvas(await rootBundle.load(layer)), canvas(base), reason: breed);
    }
  });

  test('a layer is drawn only for a worn outfit the sprite can wear', () {
    const worn = WardrobeOutfits(items: [wearable], equippedId: vestOutfitId);
    final cases = [
      (worn, 'shih-tzu', 'assets/wardrobe/vest/shih-tzu.png'),
      (worn, 'dachshund', 'assets/wardrobe/vest/dachshund.png'),
      // No approved layer for this sprite: never borrow another breed's.
      (worn, 'toy-poodle', null),
      (const WardrobeOutfits(items: [wearable]), 'shih-tzu', null),
      (
        const WardrobeOutfits(items: [refused], equippedId: vestOutfitId),
        'shih-tzu',
        null,
      ),
      (
        const WardrobeOutfits(items: [wearable], equippedId: 'unknown'),
        'shih-tzu',
        null,
      ),
    ];
    for (final (outfits, breed, layer) in cases) {
      expect(outfits.wornLayer(breed), layer, reason: breed);
    }
  });
}
