class DogBreed {
  const DogBreed(this.id, this.name, this.groupId);

  final String id;
  final String name;
  final String groupId;
  String get spritePath => 'assets/first_meeting/dogs/$id.png';
}

class DogGroup {
  const DogGroup(this.id, this.name);

  final String id;
  final String name;
  List<DogBreed> get breeds => List.unmodifiable(
    FirstMeetingCatalog.breeds.where((breed) => breed.groupId == id),
  );
}

abstract final class FirstMeetingCatalog {
  // The approved document's group and breed order is the catalog order.
  static const groups = <DogGroup>[
    DogGroup('G1', '느긋한 일상 친구'),
    DogGroup('G2', '다정한 일상 친구'),
    DogGroup('G3', '느긋한 탐색 친구'),
    DogGroup('G4', '다정한 구경 친구'),
    DogGroup('G5', '씩씩한 일상 친구'),
    DogGroup('G6', '발랄한 산책 친구'),
    DogGroup('G7', '씩씩한 모험 친구'),
    DogGroup('G8', '함께 발견하는 친구'),
  ];
  static const breeds = <DogBreed>[
    DogBreed('pekingese', '페키니즈', 'G1'),
    DogBreed('bulldog', '불독', 'G1'),
    DogBreed('shih-tzu', '시츄', 'G2'),
    DogBreed('pug', '퍼그', 'G2'),
    DogBreed('maltese', '말티즈', 'G2'),
    DogBreed('chihuahua', '치와와', 'G2'),
    DogBreed('french-bulldog', '프렌치 불독', 'G2'),
    DogBreed('dachshund', '닥스훈트', 'G3'),
    DogBreed('miniature-schnauzer', '슈나우저', 'G3'),
    DogBreed('bichon-frise', '비숑', 'G4'),
    DogBreed('yorkshire-terrier', '요크셔테리어', 'G4'),
    DogBreed('west-highland-white-terrier', '화이트 테리어', 'G4'),
    DogBreed('norwich-terrier', '노리치 테리어', 'G4'),
    DogBreed('jindo', '진돗개', 'G5'),
    DogBreed('shiba-inu', '시바견', 'G5'),
    DogBreed('alaskan-malamute', '말라뮤트', 'G5'),
    DogBreed('german-shepherd', '셰퍼드', 'G6'),
    DogBreed('pembroke-welsh-corgi', '웰시코기', 'G6'),
    DogBreed('pomeranian', '포메라니안', 'G6'),
    DogBreed('miniature-pinscher', '미니핀', 'G6'),
    DogBreed('boston-terrier', '보스턴 테리어', 'G6'),
    DogBreed('siberian-husky', '허스키', 'G7'),
    DogBreed('dalmatian', '달마시안', 'G7'),
    DogBreed('beagle', '비글', 'G7'),
    DogBreed('golden-retriever', '골든 리트리버', 'G8'),
    DogBreed('labrador-retriever', '래브라도 리트리버', 'G8'),
    DogBreed('border-collie', '보더 콜리', 'G8'),
    DogBreed('samoyed', '사모예드', 'G8'),
    DogBreed('toy-poodle', '푸들', 'G8'),
    DogBreed('cocker-spaniel', '코커 스패니얼', 'G8'),
  ];

  static DogBreed byId(String id) => breeds.firstWhere((b) => b.id == id);

  /// false is choice A; true is choice B, in the document's question order.
  static DogGroup groupForAnswers(List<bool> answers) {
    if (answers.length != 3) {
      throw ArgumentError.value(answers, 'answers', 'Three answers required');
    }
    final index =
        (answers[0] ? 4 : 0) + (answers[1] ? 2 : 0) + (answers[2] ? 1 : 0);
    return groups[index];
  }
}
