# Dev 첫 만남 기존 자산 출처

원본 경로는 balmatchum 부모 기준. 앱 대상은 `assets/first_meeting/dogs/<id>.png`.
29종은 `design/design/five-body-fit-v1/<body>/<id>/base.png`를 바이트 그대로 복사했다.
시츄만 `design/design/home-v1/assets/shih-tzu-wireframe.png`이다.
전체30 `cmp` 일치 확인. 생산30·성견·동작·착용 승인으로 확대하지 않는다.

| id | body | SHA256 |
|---|---|---|
| alaskan-malamute | balanced | f1888d1189c8aedd96bc82cbcd43416e2706bc3e7303001896e36cec612859e2 |
| beagle | balanced | 946baf77fe2e8208d4074cdb980d233cc6c4d7a91989a5f4da78a40574039310 |
| bichon-frise | compact | 360bce65c6f540cd083921ebd2c4ea0f0effc19637c3fb480eb882a7f629cc98 |
| border-collie | balanced | 570e0f18216921b00d837eaa0e8b5bc9b8c4f85b8277d5c6feee9679e82012ef |
| boston-terrier | balanced | 24ae00b63ee51fe21ea47cf2a2eafb1eb4345ff02eaa2c5892927c66a113f016 |
| bulldog | broad | 255ae65318e6de4170c566e4b5edf872fbfe8e4bd1158801c6f6d797b8bc2226 |
| chihuahua | slim | da76609ab16e585e045ac75f8c4d7e2d0ff33f774d8954268d20bd6ff410d9f3 |
| cocker-spaniel | balanced | 9308b1077112e63f4242aacf5699ec159e7353d0cc8afbb4ced3149f264444a8 |
| dachshund | long | 9c62f068f29660424a50d101356174a1f46e1803e641248b07705e0b14a9cb60 |
| dalmatian | balanced | 8ec74edb95cbce5cb77d02a5405c99d459ff6daf86a3e3f0f39a0ced448a8f19 |
| french-bulldog | broad | 9949fc75da871707b9f7562c5370c8c3145cac4eacf1c59da0b516e43477f0a8 |
| german-shepherd | balanced | 86efefe72b32ee369b6827eeb3a743144caea49f2c4be8eb068c18da49d81581 |
| golden-retriever | balanced | 22110ff5d1033dd9687782350d21aa28617032b7561682285bd9fd9928bda3c4 |
| jindo | balanced | 87790aee7534dfe11fcd8df7e32931d42a7a4a14a0fdcff5308453b4caf5a426 |
| labrador-retriever | balanced | dd4ed8e3a8a8e885e2c27c85f742a5359dc519609f7923cc0de2bba4f877a442 |
| maltese | compact | 369670c3c8d6128e616f287f886236db99a188ede2354e435f2ec347a0542a60 |
| miniature-pinscher | slim | ac3bae7aea32298de1b2f43da84446b5f53aa859696e6d3d395d4f88189519ca |
| miniature-schnauzer | balanced | bd934833874e140be2b026f96df0a45b9309beb520435b7edfba525f13f7c580 |
| norwich-terrier | compact | 742ca0661006716e017043485fd6693dfdaca2855c5c561880b4a893b1f6f272 |
| pekingese | compact | 5930b697ba5f33e162182ee2646222dc0c187a21b0252f0b11fa0972093794b1 |
| pembroke-welsh-corgi | long | b03d3647d6f4929d258935d9bb065949ceda9577665fbcec1b9e116b64e789cc |
| pomeranian | compact | f8c1d5b62fe226e374a8eec541d53c14ced351aee53ca736a54e4a6cd3182a1c |
| pug | broad | 76eb7fd85fd9f57ddae1b5095da1b2b63927dd7c7bc53358d56a1f36053ade9b |
| samoyed | balanced | ee204c2021609c88816c07f68f4665443a41b3e37d7eb3338a1d624982cf9e2e |
| shiba-inu | balanced | d72f8586c66da692142da6513c64d9c147d7e78cf53829beb98a60f4ae7186b7 |
| shih-tzu | home-v1 (위 예외 경로) | 20a1343f4769c42bd4a59948d5a55a8c9f7ec7e114c1919d16b9ab25d60862ca |
| siberian-husky | balanced | da8330a84aec686082b73d3f832299fad193cf67735214ab568c5995c211c815 |
| toy-poodle | slim | 8b99fbddf1eb4c96e2f8d018601349a3f64903c172517954b88142c792aa18db |
| west-highland-white-terrier | compact | 37e32a522f28fbc51adc96ac9ef4602f561a0e55c965c61402b60ef1e6ac68eb |
| yorkshire-terrier | compact | b78a8eead894f9106fd850b7a0f8db308a3dcd6a1d7f6fd6b89ed760700ce5d6 |

`sunny.png`: `design/design/home-v1/backgrounds/sunny.png`.
`brand.png`: `/Users/beomseok/Downloads/AppIcons (5)/appstore.png`.
`icons/female.png`, `male.png`: `design/design/icons/onboarding-v1/display/32/`
의 female.png, male-source.png. `breed.png`, `survey.png`는 같은 패킷 display/48.
back/settings/question-quiz/camera-photo는 `design/design/icons/app-v2-library/display/32`.
기존 social 로고는 그대로 유지. native splash 변경·추가 인앱 loading 없음.
런타임 참조는 모두 앱 내부 assets이며 외부 절대 경로를 사용하지 않는다.
