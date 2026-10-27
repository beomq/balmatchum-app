import 'dart:io';

import 'package:balmatchum_app/features/first_meeting/domain/dog_catalog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Approved appearance baseline (design/launch-proof/baseline.json).
/// Never regenerate these values from the working tree.
const expectedSha256 = <String, String>{
  'assets/first_meeting/dogs/alaskan-malamute.png':
      'f1888d1189c8aedd96bc82cbcd43416e2706bc3e7303001896e36cec612859e2',
  'ios/Watch/Assets.xcassets/SelectedDogAlaskanMalamute.imageset/dog.png':
      'f1888d1189c8aedd96bc82cbcd43416e2706bc3e7303001896e36cec612859e2',
  'assets/first_meeting/dogs/beagle.png':
      '946baf77fe2e8208d4074cdb980d233cc6c4d7a91989a5f4da78a40574039310',
  'ios/Watch/Assets.xcassets/SelectedDogBeagle.imageset/dog.png':
      '946baf77fe2e8208d4074cdb980d233cc6c4d7a91989a5f4da78a40574039310',
  'assets/first_meeting/dogs/bichon-frise.png':
      '360bce65c6f540cd083921ebd2c4ea0f0effc19637c3fb480eb882a7f629cc98',
  'ios/Watch/Assets.xcassets/SelectedDogBichonFrise.imageset/dog.png':
      '360bce65c6f540cd083921ebd2c4ea0f0effc19637c3fb480eb882a7f629cc98',
  'assets/first_meeting/dogs/border-collie.png':
      '570e0f18216921b00d837eaa0e8b5bc9b8c4f85b8277d5c6feee9679e82012ef',
  'ios/Watch/Assets.xcassets/SelectedDogBorderCollie.imageset/dog.png':
      '570e0f18216921b00d837eaa0e8b5bc9b8c4f85b8277d5c6feee9679e82012ef',
  'assets/first_meeting/dogs/boston-terrier.png':
      '24ae00b63ee51fe21ea47cf2a2eafb1eb4345ff02eaa2c5892927c66a113f016',
  'ios/Watch/Assets.xcassets/SelectedDogBostonTerrier.imageset/dog.png':
      '24ae00b63ee51fe21ea47cf2a2eafb1eb4345ff02eaa2c5892927c66a113f016',
  'assets/first_meeting/dogs/bulldog.png':
      '255ae65318e6de4170c566e4b5edf872fbfe8e4bd1158801c6f6d797b8bc2226',
  'ios/Watch/Assets.xcassets/SelectedDogBulldog.imageset/dog.png':
      '255ae65318e6de4170c566e4b5edf872fbfe8e4bd1158801c6f6d797b8bc2226',
  'assets/first_meeting/dogs/chihuahua.png':
      'da76609ab16e585e045ac75f8c4d7e2d0ff33f774d8954268d20bd6ff410d9f3',
  'ios/Watch/Assets.xcassets/SelectedDogChihuahua.imageset/dog.png':
      'da76609ab16e585e045ac75f8c4d7e2d0ff33f774d8954268d20bd6ff410d9f3',
  'assets/first_meeting/dogs/cocker-spaniel.png':
      '9308b1077112e63f4242aacf5699ec159e7353d0cc8afbb4ced3149f264444a8',
  'ios/Watch/Assets.xcassets/SelectedDogCockerSpaniel.imageset/dog.png':
      '9308b1077112e63f4242aacf5699ec159e7353d0cc8afbb4ced3149f264444a8',
  'assets/first_meeting/dogs/dachshund.png':
      '9c62f068f29660424a50d101356174a1f46e1803e641248b07705e0b14a9cb60',
  'ios/Watch/Assets.xcassets/SelectedDogDachshund.imageset/dog.png':
      '9c62f068f29660424a50d101356174a1f46e1803e641248b07705e0b14a9cb60',
  'assets/first_meeting/dogs/dalmatian.png':
      '8ec74edb95cbce5cb77d02a5405c99d459ff6daf86a3e3f0f39a0ced448a8f19',
  'ios/Watch/Assets.xcassets/SelectedDogDalmatian.imageset/dog.png':
      '8ec74edb95cbce5cb77d02a5405c99d459ff6daf86a3e3f0f39a0ced448a8f19',
  'assets/first_meeting/dogs/french-bulldog.png':
      '9949fc75da871707b9f7562c5370c8c3145cac4eacf1c59da0b516e43477f0a8',
  'ios/Watch/Assets.xcassets/SelectedDogFrenchBulldog.imageset/dog.png':
      '9949fc75da871707b9f7562c5370c8c3145cac4eacf1c59da0b516e43477f0a8',
  'assets/first_meeting/dogs/german-shepherd.png':
      '86efefe72b32ee369b6827eeb3a743144caea49f2c4be8eb068c18da49d81581',
  'ios/Watch/Assets.xcassets/SelectedDogGermanShepherd.imageset/dog.png':
      '86efefe72b32ee369b6827eeb3a743144caea49f2c4be8eb068c18da49d81581',
  'assets/first_meeting/dogs/golden-retriever.png':
      '22110ff5d1033dd9687782350d21aa28617032b7561682285bd9fd9928bda3c4',
  'ios/Watch/Assets.xcassets/SelectedDogGoldenRetriever.imageset/dog.png':
      '22110ff5d1033dd9687782350d21aa28617032b7561682285bd9fd9928bda3c4',
  'assets/first_meeting/dogs/jindo.png':
      '87790aee7534dfe11fcd8df7e32931d42a7a4a14a0fdcff5308453b4caf5a426',
  'ios/Watch/Assets.xcassets/SelectedDogJindo.imageset/dog.png':
      '87790aee7534dfe11fcd8df7e32931d42a7a4a14a0fdcff5308453b4caf5a426',
  'assets/first_meeting/dogs/labrador-retriever.png':
      'dd4ed8e3a8a8e885e2c27c85f742a5359dc519609f7923cc0de2bba4f877a442',
  'ios/Watch/Assets.xcassets/SelectedDogLabradorRetriever.imageset/dog.png':
      'dd4ed8e3a8a8e885e2c27c85f742a5359dc519609f7923cc0de2bba4f877a442',
  'assets/first_meeting/dogs/maltese.png':
      '369670c3c8d6128e616f287f886236db99a188ede2354e435f2ec347a0542a60',
  'ios/Watch/Assets.xcassets/SelectedDogMaltese.imageset/dog.png':
      '369670c3c8d6128e616f287f886236db99a188ede2354e435f2ec347a0542a60',
  'assets/first_meeting/dogs/miniature-pinscher.png':
      'ac3bae7aea32298de1b2f43da84446b5f53aa859696e6d3d395d4f88189519ca',
  'ios/Watch/Assets.xcassets/SelectedDogMiniaturePinscher.imageset/dog.png':
      'ac3bae7aea32298de1b2f43da84446b5f53aa859696e6d3d395d4f88189519ca',
  'assets/first_meeting/dogs/miniature-schnauzer.png':
      'bd934833874e140be2b026f96df0a45b9309beb520435b7edfba525f13f7c580',
  'ios/Watch/Assets.xcassets/SelectedDogMiniatureSchnauzer.imageset/dog.png':
      'bd934833874e140be2b026f96df0a45b9309beb520435b7edfba525f13f7c580',
  'assets/first_meeting/dogs/norwich-terrier.png':
      '742ca0661006716e017043485fd6693dfdaca2855c5c561880b4a893b1f6f272',
  'ios/Watch/Assets.xcassets/SelectedDogNorwichTerrier.imageset/dog.png':
      '742ca0661006716e017043485fd6693dfdaca2855c5c561880b4a893b1f6f272',
  'assets/first_meeting/dogs/pekingese.png':
      '5930b697ba5f33e162182ee2646222dc0c187a21b0252f0b11fa0972093794b1',
  'ios/Watch/Assets.xcassets/SelectedDogPekingese.imageset/dog.png':
      '5930b697ba5f33e162182ee2646222dc0c187a21b0252f0b11fa0972093794b1',
  'assets/first_meeting/dogs/pembroke-welsh-corgi.png':
      'b03d3647d6f4929d258935d9bb065949ceda9577665fbcec1b9e116b64e789cc',
  'ios/Watch/Assets.xcassets/SelectedDogPembrokeWelshCorgi.imageset/dog.png':
      'b03d3647d6f4929d258935d9bb065949ceda9577665fbcec1b9e116b64e789cc',
  'assets/first_meeting/dogs/pomeranian.png':
      'f8c1d5b62fe226e374a8eec541d53c14ced351aee53ca736a54e4a6cd3182a1c',
  'ios/Watch/Assets.xcassets/SelectedDogPomeranian.imageset/dog.png':
      'f8c1d5b62fe226e374a8eec541d53c14ced351aee53ca736a54e4a6cd3182a1c',
  'assets/first_meeting/dogs/pug.png':
      '76eb7fd85fd9f57ddae1b5095da1b2b63927dd7c7bc53358d56a1f36053ade9b',
  'ios/Watch/Assets.xcassets/SelectedDogPug.imageset/dog.png':
      '76eb7fd85fd9f57ddae1b5095da1b2b63927dd7c7bc53358d56a1f36053ade9b',
  'assets/first_meeting/dogs/samoyed.png':
      'ee204c2021609c88816c07f68f4665443a41b3e37d7eb3338a1d624982cf9e2e',
  'ios/Watch/Assets.xcassets/SelectedDogSamoyed.imageset/dog.png':
      'ee204c2021609c88816c07f68f4665443a41b3e37d7eb3338a1d624982cf9e2e',
  'assets/first_meeting/dogs/shiba-inu.png':
      'd72f8586c66da692142da6513c64d9c147d7e78cf53829beb98a60f4ae7186b7',
  'ios/Watch/Assets.xcassets/SelectedDogShibaInu.imageset/dog.png':
      'd72f8586c66da692142da6513c64d9c147d7e78cf53829beb98a60f4ae7186b7',
  'assets/first_meeting/dogs/shih-tzu.png':
      '20a1343f4769c42bd4a59948d5a55a8c9f7ec7e114c1919d16b9ab25d60862ca',
  'ios/Watch/Assets.xcassets/SelectedDogShihTzu.imageset/dog.png':
      '20a1343f4769c42bd4a59948d5a55a8c9f7ec7e114c1919d16b9ab25d60862ca',
  'assets/first_meeting/dogs/siberian-husky.png':
      'da8330a84aec686082b73d3f832299fad193cf67735214ab568c5995c211c815',
  'ios/Watch/Assets.xcassets/SelectedDogSiberianHusky.imageset/dog.png':
      'da8330a84aec686082b73d3f832299fad193cf67735214ab568c5995c211c815',
  'assets/first_meeting/dogs/toy-poodle.png':
      '8b99fbddf1eb4c96e2f8d018601349a3f64903c172517954b88142c792aa18db',
  'ios/Watch/Assets.xcassets/SelectedDogToyPoodle.imageset/dog.png':
      '8b99fbddf1eb4c96e2f8d018601349a3f64903c172517954b88142c792aa18db',
  'assets/first_meeting/dogs/west-highland-white-terrier.png':
      '37e32a522f28fbc51adc96ac9ef4602f561a0e55c965c61402b60ef1e6ac68eb',
  'ios/Watch/Assets.xcassets/SelectedDogWestHighlandWhiteTerrier.imageset/dog.png':
      '37e32a522f28fbc51adc96ac9ef4602f561a0e55c965c61402b60ef1e6ac68eb',
  'assets/first_meeting/dogs/yorkshire-terrier.png':
      'b78a8eead894f9106fd850b7a0f8db308a3dcd6a1d7f6fd6b89ed760700ce5d6',
  'ios/Watch/Assets.xcassets/SelectedDogYorkshireTerrier.imageset/dog.png':
      'b78a8eead894f9106fd850b7a0f8db308a3dcd6a1d7f6fd6b89ed760700ce5d6',
};

const baselineBreedIds = <String>{
  'alaskan-malamute',
  'beagle',
  'bichon-frise',
  'border-collie',
  'boston-terrier',
  'bulldog',
  'chihuahua',
  'cocker-spaniel',
  'dachshund',
  'dalmatian',
  'french-bulldog',
  'german-shepherd',
  'golden-retriever',
  'jindo',
  'labrador-retriever',
  'maltese',
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
};

/// Returns the paths whose bytes under [root] are missing or differ.
List<String> mismatchedPaths(Directory root, Map<String, String> expected) {
  final bad = <String>[];
  for (final entry in expected.entries) {
    final file = File('${root.path}/${entry.key}');
    if (!file.existsSync() ||
        sha256.convert(file.readAsBytesSync()).toString() != entry.value) {
      bad.add(entry.key);
    }
  }
  return bad;
}

void main() {
  test('baseline lists 30 breeds x Flutter and Watch images', () {
    expect(expectedSha256, hasLength(60));
  });

  test('catalog breed ids equal the baseline breed ids', () {
    expect(
      FirstMeetingCatalog.breeds.map((b) => b.id).toSet(),
      baselineBreedIds,
    );
    expect(FirstMeetingCatalog.breeds, hasLength(30));
  });

  test('every Flutter and Watch image matches its approved SHA-256', () {
    expect(mismatchedPaths(Directory.current, expectedSha256), isEmpty);
  });

  test('the check fails on a one-byte-modified copy', () {
    final tmp = Directory.systemTemp.createTempSync('appearance_lock_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final path in expectedSha256.keys) {
      final copy = File('${tmp.path}/$path')..createSync(recursive: true);
      copy.writeAsBytesSync(File(path).readAsBytesSync());
    }
    expect(mismatchedPaths(tmp, expectedSha256), isEmpty);

    final victim = expectedSha256.keys.first;
    final file = File('${tmp.path}/$victim');
    final bytes = file.readAsBytesSync();
    bytes[bytes.length - 1] ^= 0x01;
    file.writeAsBytesSync(bytes);
    expect(mismatchedPaths(tmp, expectedSha256), [victim]);
  });
}
