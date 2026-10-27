import XCTest
@testable import WatchSyncContract

final class DogAssetTests: XCTestCase {
    func testEveryApprovedKeyResolvesToItsOwnAsset() {
        let expected = [
            "dog.preview.pekingese": "SelectedDogPekingese",
            "dog.preview.bulldog": "SelectedDogBulldog",
            "dog.preview.shih-tzu": "SelectedDogShihTzu",
            "dog.preview.pug": "SelectedDogPug",
            "dog.preview.maltese": "SelectedDogMaltese",
            "dog.preview.chihuahua": "SelectedDogChihuahua",
            "dog.preview.french-bulldog": "SelectedDogFrenchBulldog",
            "dog.preview.dachshund": "SelectedDogDachshund",
            "dog.preview.miniature-schnauzer": "SelectedDogMiniatureSchnauzer",
            "dog.preview.bichon-frise": "SelectedDogBichonFrise",
            "dog.preview.yorkshire-terrier": "SelectedDogYorkshireTerrier",
            "dog.preview.west-highland-white-terrier": "SelectedDogWestHighlandWhiteTerrier",
            "dog.preview.norwich-terrier": "SelectedDogNorwichTerrier",
            "dog.preview.jindo": "SelectedDogJindo",
            "dog.preview.shiba-inu": "SelectedDogShibaInu",
            "dog.preview.alaskan-malamute": "SelectedDogAlaskanMalamute",
            "dog.preview.german-shepherd": "SelectedDogGermanShepherd",
            "dog.preview.pembroke-welsh-corgi": "SelectedDogPembrokeWelshCorgi",
            "dog.preview.pomeranian": "SelectedDogPomeranian",
            "dog.preview.miniature-pinscher": "SelectedDogMiniaturePinscher",
            "dog.preview.boston-terrier": "SelectedDogBostonTerrier",
            "dog.preview.siberian-husky": "SelectedDogSiberianHusky",
            "dog.preview.dalmatian": "SelectedDogDalmatian",
            "dog.preview.beagle": "SelectedDogBeagle",
            "dog.preview.golden-retriever": "SelectedDogGoldenRetriever",
            "dog.preview.labrador-retriever": "SelectedDogLabradorRetriever",
            "dog.preview.border-collie": "SelectedDogBorderCollie",
            "dog.preview.samoyed": "SelectedDogSamoyed",
            "dog.preview.toy-poodle": "SelectedDogToyPoodle",
            "dog.preview.cocker-spaniel": "SelectedDogCockerSpaniel",
        ]
        XCTAssertEqual(expected.count, 30)
        XCTAssertEqual(Set(expected.values).count, 30)
        for (key, asset) in expected {
            XCTAssertEqual(DogAsset.name(for: key), asset)
        }
    }

    func testUnknownKeysNeverSubstituteABreed() {
        for key in ["dog.unsupported", "unknown", "", "dog.preview.unknown", "dog.preview.Pug", "dog.preview../pug"] {
            XCTAssertNil(DogAsset.name(for: key))
        }
    }
}
