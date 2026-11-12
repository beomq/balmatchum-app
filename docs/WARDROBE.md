# 꾸미기(옷장): 아이템 · 세트 · 매달 구독 선물

서버 계약은 서버 저장소 `docs/WARDROBE_API.md`. 가격, 보유, 입을 수 있는지, 세트 완성 여부는 모두 서버가 정하고 앱은 그대로 그린다. 디자인 근거는 `~/dori/balmatchum-art/wardrobe-design/DESIGN.md`(마지막 '주인님 결정' 절이 우선).

## 화면 (`lib/features/wardrobe/wardrobe_screen.dart`)
- 위: 미리보기(배경 + 입은 강아지 + 보유 포인트). 세트가 완성되면 `<세트> 완성` 띠와 세트 효과. 입어 보는 중이면 `입어 보는 중` 표시와 `입은 옷으로 돌아가기`.
- `지금 입은 것`: 칸(머리·몸·발)마다 한 줄, 세트 표시 또는 `색 다름`, 벗기기. 세트 완성이면 `세트 한 번에 벗기기`.
- 세트에 가까우면 `<세트>까지 N개 남았어요` 안내(옷이 다 맞고 배경만 다르면 배경 안내).
- 탭: 세트(처음) / 아이템 / 배경.
  - 세트 카드: 내 강아지가 고른 색 세트를 입고 세트 배경 위에 선 그림(효과는 정지 프레임), `SET · 이름` 또는 `구독자 선물 · 이름` 띠, 색 동그라미, 들어 있는 것과 `보유`, 따로 산 값(취소선) · 20% 할인 · 낼 값, `입어 보기`와 한 개의 주 버튼(사기 / 세트로 입히기 / 세트 한 번에 벗기기 / 구독하고 받기 / 선물 받기 / 곧 입을 수 있어요).
  - 아이템 카드: 그 색을 입은 강아지, 색 동그라미(이 견종이 입을 수 없는 색은 흐리게), `입어 보기`, 사기(150P) / 입히기 / 벗기기 / 세트로만 받아요 / 곧 입을 수 있어요.
  - 배경: 누르면 입어 보기, 사기(100P) / 고르기.
- 입어 보기는 누구나 할 수 있고 서버를 부르지 않는다. 입어 보면 미리보기가 보이도록 맨 위로 스크롤한다. 사는 것은 확인 창을 거친다.

## 그림 (`assets/wardrobe/`)
- `~/dori/balmatchum-art/wardrobe-export/export.py <앱 루트>`가 아트 폴더에서 복사하고 `catalog.json`을 쓴다(그림을 새로 그리지 않음). `wardrobe_art.dart`의 표와 `catalog.json`이 같은지는 `test/features/wardrobe/wardrobe_art_test.dart`가 확인한다.
- `items/<아이템>/<색>/<견종>.png`, `items/<아이템>/{cut,fur,over}/<견종>.png`, 27견종의 토마토 패딩은 `items/padding/tomato/full/<견종>.png`(강아지 전체 그림, 혼자만 입음), 배경 `backgrounds/<id>.png`, 효과 설정 `effects/presets.json`.
- 겹쳐 입는 그림은 말티즈·닥스훈트·골든 리트리버만 있다. 다른 견종의 그림을 빌려 쓰지 않는다.

## 그리기 (`dog_sprite.dart`, `wardrobe_art.dart`)
원본 강아지 → 입은 아이템의 `cut`을 모두 지움(`BlendMode.dstOut`) → 발 → 머리 털 고리 → 몸 → 머리 → 모든 `over` 털. `FilterQuality.none`, 원본과 같은 contain 맞춤. 그림이 다 풀리기 전에는 원본 강아지만 보인다.

## 효과 (`set_effect.dart`)
`presets.json`의 falling / rising / burst / sparkle을 768×512, 48프레임 12fps로 그린다. 기기 '동작 줄이기'면 불꽃 없는 정지 프레임, 화면이 가려지면(TickerMode) 멈춘다. 상점 카드는 정지 프레임만.

## 실제 서버로 걸어 보기 (iOS 시뮬레이터)
`integration_test/wardrobe_server_test.dart`. 로컬 서버(일회용 DB `balmatchum_dev_test`)와 개발 가상 사용자 세션(서버 `docs/DEV_TEST_USER.md`)이 필요하다. 세션 JSON을 앱 컨테이너의 `Library/Application Support/dev-test-session.json`에 넣고(가져오면 지워짐) 실행한다.

```sh
XCODE_XCCONFIG_FILE=ios/Flutter/AdMobTest.xcconfig RUN_TMP=<임시 폴더> fvm flutter drive \
  --driver=test_driver/records_driver.dart --target=integration_test/wardrobe_server_test.dart \
  -d <시뮬레이터 id> --flavor dev --dart-define=SERVER_URL=http://localhost:8080/ \
  --dart-define=WARDROBE_PHASE=buy   # 구독을 끝낸 뒤 다시 WARDROBE_PHASE=kept
```
`buy`는 그 계정이 말티즈, 1,000P, 구독 중이고 이달 선물이 크리스마스 세트일 때의 흐름(아이템 사기 → 세트 320P → 세트로 입히기 → 선물 받기)이다. `kept`는 구독이 끝난 뒤 받은 선물을 입는다.
