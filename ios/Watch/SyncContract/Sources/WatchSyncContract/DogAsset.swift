/// Only approved, bundled sprites resolve. Never substitute another breed.
public enum DogAsset {
    public static func name(for key: String) -> String? {
        switch key {
        case "dog.preview.pekingese": return "SelectedDogPekingese"
        case "dog.preview.bulldog": return "SelectedDogBulldog"
        case "dog.preview.shih-tzu": return "SelectedDogShihTzu"
        case "dog.preview.pug": return "SelectedDogPug"
        case "dog.preview.maltese": return "SelectedDogMaltese"
        case "dog.preview.chihuahua": return "SelectedDogChihuahua"
        case "dog.preview.french-bulldog": return "SelectedDogFrenchBulldog"
        case "dog.preview.dachshund": return "SelectedDogDachshund"
        case "dog.preview.miniature-schnauzer": return "SelectedDogMiniatureSchnauzer"
        case "dog.preview.bichon-frise": return "SelectedDogBichonFrise"
        case "dog.preview.yorkshire-terrier": return "SelectedDogYorkshireTerrier"
        case "dog.preview.west-highland-white-terrier": return "SelectedDogWestHighlandWhiteTerrier"
        case "dog.preview.norwich-terrier": return "SelectedDogNorwichTerrier"
        case "dog.preview.jindo": return "SelectedDogJindo"
        case "dog.preview.shiba-inu": return "SelectedDogShibaInu"
        case "dog.preview.alaskan-malamute": return "SelectedDogAlaskanMalamute"
        case "dog.preview.german-shepherd": return "SelectedDogGermanShepherd"
        case "dog.preview.pembroke-welsh-corgi": return "SelectedDogPembrokeWelshCorgi"
        case "dog.preview.pomeranian": return "SelectedDogPomeranian"
        case "dog.preview.miniature-pinscher": return "SelectedDogMiniaturePinscher"
        case "dog.preview.boston-terrier": return "SelectedDogBostonTerrier"
        case "dog.preview.siberian-husky": return "SelectedDogSiberianHusky"
        case "dog.preview.dalmatian": return "SelectedDogDalmatian"
        case "dog.preview.beagle": return "SelectedDogBeagle"
        case "dog.preview.golden-retriever": return "SelectedDogGoldenRetriever"
        case "dog.preview.labrador-retriever": return "SelectedDogLabradorRetriever"
        case "dog.preview.border-collie": return "SelectedDogBorderCollie"
        case "dog.preview.samoyed": return "SelectedDogSamoyed"
        case "dog.preview.toy-poodle": return "SelectedDogToyPoodle"
        case "dog.preview.cocker-spaniel": return "SelectedDogCockerSpaniel"
        default: return nil
        }
    }
}

