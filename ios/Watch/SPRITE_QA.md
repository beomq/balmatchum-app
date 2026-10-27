# Watch 30견종 자산 검증 — 2026-10-19

## 구현

- 실제 FirstMeetingCatalog 30개 ID만 watchDogAssetKey → dog.preview.<id> → DogAsset.name(for:) → SelectedDog<PascalCase>로 해석한다. 기존 시츄 키는 유지하며 unknown/빈 문자열/경로 형태 입력은 미지원이다.
- 승인된 assets/first_meeting/dogs/<id>.png를 이미지셋 dog.png로 바이트 복사했다. 생성·리사이즈·색 변경·타 견종 대체는 없다.
- 실제 타깃은 기존 Watch/Assets.xcassets 전체 리소스 등록을 그대로 사용한다. PreviewHarness/build.sh도 같은 카탈로그와 같은 WatchDashboard, WatchSyncContract를 컴파일한다.
- profile/epoch/인증 구현은 보존했다. 프로필 테스트의 pug 기대 키와 관련 자산 매핑 테스트만 갱신했다.

## 검증

실행 캐시·로그·스크린샷: /tmp/watch30-1792385844221
모든 명령은 RUN_TMP, TMPDIR, CLANG_MODULE_CACHE_PATH, SWIFT_MODULECACHE_PATH를 이 실행 전용 디렉터리로 export했다. Xcode 자체 전역 SDK stat cache/compilation cache 경로는 도구 기본값이다.

|검사|결과|
|---|---|
|swift test --package-path ios/Watch/SyncContract --scratch-path $RUN_TMP/swift-tests|종료 0: XCTest 2 + Swift Testing 16 통과|
|fvm flutter test test/features/watch_sync --reporter expanded|종료 0: 35 통과|
|fvm flutter test --reporter expanded|종료 0: 210 통과|
|fvm dart analyze lib/features/watch_sync/watch_sync_service.dart test/features/watch_sync/watch_sync_service_test.dart|종료 0: No issues found|
|fvm flutter analyze|종료 255: 한글 경로 LSP 초기화 JSON Unterminated string, 전체 분석 미완료|
|xcodebuild -project ios/Runner.xcodeproj -target BalmatchumWatch -configuration Debug-dev -sdk watchsimulator ARCHS=arm64 CODE_SIGNING_ALLOWED=NO SYMROOT=$RUN_TMP/product OBJROOT=$RUN_TMP/objects|종료 0|
|RUN_TMP=<전용 경로> bash ios/Watch/PreviewHarness/build.sh|종료 0: swiftc, actool, 로컬 ad-hoc codesign|
|assetutil --info 제품 및 미리보기 Assets.car|양쪽 각각 30/30 이미지 이름 존재|
|git diff --check, bash -n ios/Watch/PreviewHarness/build.sh|종료 0|

Xcode 27.1 (27A9275), watchOS 27.0 SDK. 실제 제품 산출물: /tmp/watch30-1792385844221/product/Debug-dev-watchsimulator/BalmatchumWatch.app.
미리보기 산출물: /tmp/watch30-1792385844221/WatchPreview.app.

## SHA-256 원본 / 복사본

각 행의 두 해시는 원본과 복사본이며 30/30 동일하다. Dart 회귀 테스트도 카탈로그 전체에서 원본/복사본 바이트 일치와 이미지셋 JSON을 검사한다.

```text
pekingese	5930b697ba5f33e162182ee2646222dc0c187a21b0252f0b11fa0972093794b1	5930b697ba5f33e162182ee2646222dc0c187a21b0252f0b11fa0972093794b1
bulldog	255ae65318e6de4170c566e4b5edf872fbfe8e4bd1158801c6f6d797b8bc2226	255ae65318e6de4170c566e4b5edf872fbfe8e4bd1158801c6f6d797b8bc2226
shih-tzu	20a1343f4769c42bd4a59948d5a55a8c9f7ec7e114c1919d16b9ab25d60862ca	20a1343f4769c42bd4a59948d5a55a8c9f7ec7e114c1919d16b9ab25d60862ca
pug	76eb7fd85fd9f57ddae1b5095da1b2b63927dd7c7bc53358d56a1f36053ade9b	76eb7fd85fd9f57ddae1b5095da1b2b63927dd7c7bc53358d56a1f36053ade9b
maltese	369670c3c8d6128e616f287f886236db99a188ede2354e435f2ec347a0542a60	369670c3c8d6128e616f287f886236db99a188ede2354e435f2ec347a0542a60
chihuahua	da76609ab16e585e045ac75f8c4d7e2d0ff33f774d8954268d20bd6ff410d9f3	da76609ab16e585e045ac75f8c4d7e2d0ff33f774d8954268d20bd6ff410d9f3
french-bulldog	9949fc75da871707b9f7562c5370c8c3145cac4eacf1c59da0b516e43477f0a8	9949fc75da871707b9f7562c5370c8c3145cac4eacf1c59da0b516e43477f0a8
dachshund	9c62f068f29660424a50d101356174a1f46e1803e641248b07705e0b14a9cb60	9c62f068f29660424a50d101356174a1f46e1803e641248b07705e0b14a9cb60
miniature-schnauzer	bd934833874e140be2b026f96df0a45b9309beb520435b7edfba525f13f7c580	bd934833874e140be2b026f96df0a45b9309beb520435b7edfba525f13f7c580
bichon-frise	360bce65c6f540cd083921ebd2c4ea0f0effc19637c3fb480eb882a7f629cc98	360bce65c6f540cd083921ebd2c4ea0f0effc19637c3fb480eb882a7f629cc98
yorkshire-terrier	b78a8eead894f9106fd850b7a0f8db308a3dcd6a1d7f6fd6b89ed760700ce5d6	b78a8eead894f9106fd850b7a0f8db308a3dcd6a1d7f6fd6b89ed760700ce5d6
west-highland-white-terrier	37e32a522f28fbc51adc96ac9ef4602f561a0e55c965c61402b60ef1e6ac68eb	37e32a522f28fbc51adc96ac9ef4602f561a0e55c965c61402b60ef1e6ac68eb
norwich-terrier	742ca0661006716e017043485fd6693dfdaca2855c5c561880b4a893b1f6f272	742ca0661006716e017043485fd6693dfdaca2855c5c561880b4a893b1f6f272
jindo	87790aee7534dfe11fcd8df7e32931d42a7a4a14a0fdcff5308453b4caf5a426	87790aee7534dfe11fcd8df7e32931d42a7a4a14a0fdcff5308453b4caf5a426
shiba-inu	d72f8586c66da692142da6513c64d9c147d7e78cf53829beb98a60f4ae7186b7	d72f8586c66da692142da6513c64d9c147d7e78cf53829beb98a60f4ae7186b7
alaskan-malamute	f1888d1189c8aedd96bc82cbcd43416e2706bc3e7303001896e36cec612859e2	f1888d1189c8aedd96bc82cbcd43416e2706bc3e7303001896e36cec612859e2
german-shepherd	86efefe72b32ee369b6827eeb3a743144caea49f2c4be8eb068c18da49d81581	86efefe72b32ee369b6827eeb3a743144caea49f2c4be8eb068c18da49d81581
pembroke-welsh-corgi	b03d3647d6f4929d258935d9bb065949ceda9577665fbcec1b9e116b64e789cc	b03d3647d6f4929d258935d9bb065949ceda9577665fbcec1b9e116b64e789cc
pomeranian	f8c1d5b62fe226e374a8eec541d53c14ced351aee53ca736a54e4a6cd3182a1c	f8c1d5b62fe226e374a8eec541d53c14ced351aee53ca736a54e4a6cd3182a1c
miniature-pinscher	ac3bae7aea32298de1b2f43da84446b5f53aa859696e6d3d395d4f88189519ca	ac3bae7aea32298de1b2f43da84446b5f53aa859696e6d3d395d4f88189519ca
boston-terrier	24ae00b63ee51fe21ea47cf2a2eafb1eb4345ff02eaa2c5892927c66a113f016	24ae00b63ee51fe21ea47cf2a2eafb1eb4345ff02eaa2c5892927c66a113f016
siberian-husky	da8330a84aec686082b73d3f832299fad193cf67735214ab568c5995c211c815	da8330a84aec686082b73d3f832299fad193cf67735214ab568c5995c211c815
dalmatian	8ec74edb95cbce5cb77d02a5405c99d459ff6daf86a3e3f0f39a0ced448a8f19	8ec74edb95cbce5cb77d02a5405c99d459ff6daf86a3e3f0f39a0ced448a8f19
beagle	946baf77fe2e8208d4074cdb980d233cc6c4d7a91989a5f4da78a40574039310	946baf77fe2e8208d4074cdb980d233cc6c4d7a91989a5f4da78a40574039310
golden-retriever	22110ff5d1033dd9687782350d21aa28617032b7561682285bd9fd9928bda3c4	22110ff5d1033dd9687782350d21aa28617032b7561682285bd9fd9928bda3c4
labrador-retriever	dd4ed8e3a8a8e885e2c27c85f742a5359dc519609f7923cc0de2bba4f877a442	dd4ed8e3a8a8e885e2c27c85f742a5359dc519609f7923cc0de2bba4f877a442
border-collie	570e0f18216921b00d837eaa0e8b5bc9b8c4f85b8277d5c6feee9679e82012ef	570e0f18216921b00d837eaa0e8b5bc9b8c4f85b8277d5c6feee9679e82012ef
samoyed	ee204c2021609c88816c07f68f4665443a41b3e37d7eb3338a1d624982cf9e2e	ee204c2021609c88816c07f68f4665443a41b3e37d7eb3338a1d624982cf9e2e
toy-poodle	8b99fbddf1eb4c96e2f8d018601349a3f64903c172517954b88142c792aa18db	8b99fbddf1eb4c96e2f8d018601349a3f64903c172517954b88142c792aa18db
cocker-spaniel	9308b1077112e63f4242aacf5699ec159e7353d0cc8afbb4ced3149f264444a8	9308b1077112e63f4242aacf5699ec159e7353d0cc8afbb4ced3149f264444a8
```

## 직접 확인과 한계

Apple Watch Series 12 (42mm), watchOS 27.0 시뮬레이터 F50BD919-1E3D-417C-9264-5E24B0122F06에서 실행했다.
실제 374×446 캡처를 직접 열어 검사했다: `/tmp/watch30-1792385844221/pug.png`, `dalmatian.png`, `samoyed.png`, `unknown.png`.
퍼그의 황갈색과 검정 얼굴, 달마시안의 검은 점, 사모예드의 흰 털과 꼬리가 서로 다르게 표시된다. 세 이미지 모두 비율 유지, 자르기·겹침 없이 60pt 프레임에 표시된다. unknown은 이미지 없이 `강아지 이미지 준비 중`과 이름을 표시한다. 걸음 수와 갱신 시각은 실제 SwiftUI 텍스트다.
첫 퍼그 캡처는 시스템 로딩 프레임이어서 폐기하고 완성된 화면으로 교체했다. 후속 화면은 `simctl launch --console`의 `^WATCH_PREVIEW_READY$` 신호를 구독한 뒤 캡처했다. 고정 sleep을 사용하지 않았다.
독립 시각 검토 2건을 시도했으나 이 작업은 이미 자식 세션이며 하네스 최대 깊이 1 제한으로 두 스폰 모두 거부됐다. 따라서 독립 검토 PASS는 주장하지 않으며 위 화면 판정은 구현자의 직접 검사다. 전체 30개는 자동 매핑·바이트·컴파일 자산 검사로 확인했고 실제 화면 캡처는 명시한 3견종과 unknown이다.
미리보기 실행: xcrun simctl launch --terminate-running-process <UDID> com.beomq.balmatchum.watchpreview steps breed=dalmatian. 다른 ID나 unknown으로 교체한다.

화면 문제는 Dart 키 → DogAsset 명시적 매핑 → imageset/Contents.json과 dog.png → 제품 Assets.car 순서로 확인한다.
실기기·실시간 iPhone 전송·운영 서명·배포·사용자 직접 확인은 이 자산 증분의 검증 범위에 포함되지 않는다. 커밋·푸시·배포하지 않았다. Biome/bash LSP가 없어 JSON은 Dart 파싱과 actool, 셸은 bash -n으로 검사했다. Swift 단독 LSP의 모듈 탐색 오류는 실제 Swift 패키지 테스트와 타깃 빌드로 검증했다.
