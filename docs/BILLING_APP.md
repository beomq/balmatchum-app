# 앱 결제 계약과 로컬 QA

## 범위와 고정 계약

서버 `cd0f16e1d4e0a393fe8586d0bc23fa947d4d346c`의
`docs/BILLING_API.md`를 사용한다. 서버 소스는 수정하지 않았다.
로컬 검증에는 해당 서버 worktree의 생성 client를 사용했다.
현재 `pubspec.yaml`과 lock은 머지된 서버 develop 커밋
`af08b3fb034a541693ae6b93e9e1187b05aa6b32`를 Git 소스로 고정하며,
`pubspec_overrides.yaml`은 커밋하지 않는다.
기존 미커밋 `pubspec_overrides.yaml`의 서버 worktree 경로 override는
사용자 변경 보존을 위해 유지했다. 따라서 현재 lockfile은 기존대로 path 의존성이다.
이번 로컬 QA가 원격 Git 다운로드 재현성을 입증하지는 않는다.
통합 담당자는 override를 포함하지 않는 배포 체크아웃에서 pinned pub get을 확인해야 한다.

앱 진입은 인증 프로필의 설정 → 구매 및 복원 → `/billing`이다.
로그아웃/미완성 프로필은 보호 라우트에 진입하지 않는다. 기존 dev 체험은
인증 없는 fixture이므로 결제 메뉴를 추가하지 않았다. 결제 리스너는 인증된
앱의 router 조립 수명에 있으며 화면을 닫아도 유지된다.

| 서버 생성 메서드 | 앱 처리 |
| --- | --- |
| getPurchaseConfiguration(store) | apple/google, UUID binding, 허용 상품만 조회 |
| verifyPurchase(input) | purchased 이벤트 한 건씩 검증 |
| restorePurchase(input) | restored 이벤트 한 건씩 검증 |
| getEntitlement() | 시작/재시도/복원 종료 시 신선한 상태 조회 |

입력은 `store`, `productId`, `purchaseReference`뿐이다. owner/binding/premium
주장을 보내지 않는다. Apple은 transaction ID, Google은 purchase token을 보낸다.
Apple JWS나 Google order ID를 검증 조회키로 바꾸어 보내지 않는다.

## 공식 SDK 선택과 플랫폼

Flutter 3.47.5 / Dart 3.13.4에서 공식 `in_app_purchase 3.3.1`,
`in_app_purchase_android 0.5.4`, `in_app_purchase_storekit 0.4.14`,
`in_app_purchase_platform_interface 1.4.0`을 사용한다. pub.dev 최신 메타데이터와
설치된 SDK Dart/Swift 소스를 읽고 선택했다. 플랫폼 인터페이스 직접 의존성은
Android 완료 응답의 BillingResultWrapper를 확인하기 위해 필요하다.
범용 completePurchase는 그 응답을 버리므로 실패를 성공으로 처리하지 않도록 했다.

- [공식 공통 SDK](https://pub.dev/packages/in_app_purchase)
- [StoreKit SDK](https://pub.dev/packages/in_app_purchase_storekit)
- [Android SDK](https://pub.dev/packages/in_app_purchase_android)
- [공식 구현 소스](https://github.com/flutter/packages/tree/main/packages/in_app_purchase)

가격은 `ProductDetails.price`를 그대로 표시하며 실제 ProductDetails 객체로 구매한다.
서버 allowlist 외 상품은 필터링한다. 미설정/조회 실패 시 고정 가격을 만들지 않는다.
QA의 `€12,34`, `test.lifetime` 등은 test 디렉터리의 명시적 fixture이며
운영 제품/가격/자격증명으로 쓰이지 않는다.

StoreKit2가 기본이며 `Sk2PurchaseParam.applicationUserName`은 appAccountToken으로,
GooglePlayPurchaseParam.applicationUserName은 obfuscatedAccountId로 전달된다.
값은 서버 UUID 그대로다. SDK가 제공한 원래 transaction binding이 현재 configuration
binding과 같은 경우만 서버 검증한다. binding 없는 과거 구매는 임의 귀속하지 않는다.
이 비교는 로컬 라우팅 방어일 뿐이며 최종 소유권 증거는 서버의 스토어 조회다.

Android manifest에 BILLING 권한, iOS Runner에 In-App Purchase capability를 추가했다.
기존 iOS 최소 15.0은 StoreKit2와 호환된다. 앱 ID/스토어 등록/상품/서명/키를 만들거나
변경하지 않았다. lifetime과 subscription 모두 buyNonConsumable을 사용하며
buyConsumable/consume 호출은 없다.

## 계정·순서·완료 불변조건

`billing_repository.dart`: 저장소 생성 시 인증 객체를 캡처한다. 요청 시작/헤더 준비
후/응답 후 같은 인증인지 확인하고 별도 generated Client에 고정 헤더를 전달한다.
로그인 변경 후 늦은 응답은 거부한다. 계정 ID가 같아도 재로그인한 인증은 다른 수명이다.
`billingAuthenticationProvider`가 인증 객체 변경을 관찰하여 새 controller를 만든다.

BillingRequestQueue는 controller보다 오래 유지되고 계정별로 모든 billing HTTP를
직렬화한다. A → B → A 전환에도 이전 A 요청과 새 A 관측을 겹치지 않는다.
컨트롤러 큐는 SDK 이벤트의 검증/완료/재시도 순서를 추가로 보장한다.
다른 기기의 요청은 앱이 직렬화할 수 없으므로 staleObservation은 단 한 번
getEntitlement로 새로 확인하고 원래 transaction 검증은 명시적 재시도로 남긴다.

| 이벤트/결과 | 처리 |
| --- | --- |
| pending | 검증·완료하지 않고 대기, 신규 구매 차단 |
| StoreKit pending, binding 없음 | 현재 세션이 시도한 동일 상품의 UI만 대기 상태로 전환 |
| canceled/error | 권한 부여·검증·완료 없이 취소/재시도 표시 |
| purchased/restored | binding/allowlist 검사 → 순차 서버 검증 → 완료 |
| acknowledgementPending | 구매 확인과 승인 대기를 구분, 완료하지 않고 재시도 제공 |
| Google 비활성 결과 | 로컬 acknowledge하지 않고 purchaseNotActive 재확인 |
| 서버/완료 실패 | entitlement를 null로 비우고 원래 transaction을 메모리에 유지 |
| 계정 변경/삭제 | 기존 인증 응답 반영/트랜잭션 완료 중단 |

StoreKit restored의 pendingCompletePurchase가 false여도 서버 restore 성공 후
transaction ID를 finish한다. 이미 끝난 ID의 finish는 SDK에서 idempotent이다.
Google 완료는 서버가 활성 구매 승인에 성공한 뒤에만 실행되며 responseCode를 검사한다.
승인 대기 중에는 클라이언트가 서버 승인을 우회하지 않는다.

복원은 SDK stream의 배치 신호(빈 목록 포함)와 native method 완료를 모두 기다린다.
플랫폼 채널 간 도착 순서를 가정하지 않는다. 각 구매는 하나씩 서버 restore를 호출하고,
실패가 섞인 배치는 마지막 성공으로 실패를 덮지 않는다. 성공 배치 종료 후
getEntitlement로 재조회한다. Google pending이 SDK에서 restored로 표시되어도
원본 purchaseState를 확인하여 승인하지 않는다.

재시작은 Apple unfinishedTransactions와 Google queryPastPurchases로 복구한다.
토큰/권한을 별도 디스크에 캐시하지 않는다. 같은 구매의 재전달은 서버에서 다시 검증한다.
승인/완료 실패 후 앱이 종료되면 native 미완료 목록과 서버 getEntitlement로 복구한다.
앱이 장기간 실행되지 않는 경우의 승인 마감 보장은 서버 운영 후속 범위다.

## 혜택과 UI

이 화면은 구매 상태만 보여준다. 광고 생략, 보상 배수, 추가 퀴즈, 월간 선물, 자산
지급에는 연결하지 않았고 제공된다고 주장하지 않는다. 성공 응답의 active도
혜택 소비에 재사용하지 않는다. 상품 제목·설명·현지 가격 외에 임의 가격표를 만들지 않는다.
구독 변경/취소는 스토어 설정에서 관리하도록 안내한다.

## 재현 명령

각 명령마다 아래 환경을 새로 만든다. 서버 worktree는 읽기 전용이며 서버 프로세스를
실행하거나 기존 DB/스토어를 수정하지 않는다.

```sh
export RUN_TMP="$(mktemp -d)"
export TMPDIR="$RUN_TMP/" XDG_CACHE_HOME="$RUN_TMP/cache" PUB_CACHE="$HOME/.pub-cache"
export NODE_COMPILE_CACHE="$RUN_TMP/node" BUN_RUNTIME_TRANSPILER_CACHE_PATH="$RUN_TMP/bun"
export CLANG_MODULE_CACHE_PATH="$RUN_TMP/clang" SWIFT_MODULECACHE_PATH="$RUN_TMP/swift"
mkdir -p "$XDG_CACHE_HOME"
# app/.worktrees/full-feature-audit에서 각 명령을 실행한다.
fvm flutter test --reporter expanded
fvm flutter analyze
fvm dart analyze --fatal-infos --format machine
ADMOB_TEST_ADS=true fvm flutter build apk --debug --flavor dev --dart-define=ADMOB_TEST_ADS=true
XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter drive --driver=test_driver/billing_driver.dart \
  --target=integration_test/billing_flow_test.dart --flavor dev \
  --dart-define=ADMOB_TEST_ADS=true -d <booted-simulator-id>
```

`test/features/billing/billing_http_harness.dart`는 실제 loopback HttpServer와
생성 Client 직렬화, 고정 fixture 인증 헤더를 사용한다. 운영 서버 verifier/DB를
실행하는 테스트는 아니다. 실패 응답은 Protocol.encodeWithType으로 생성한다.
시뮬레이터도 같은 실제 HTTP 경계를 거치고 native 결제 SDK만 주입한다.
SDK 어댑터 테스트는 공식 InAppPurchase facade를 통해 파라미터와 복원 신호를 검증한다.
네이티브 스토어 구매창/샌드박스 구매는 실행하지 않았다.

## 실행 증거와 한계

- 전체 `fvm flutter test --reporter expanded`: 331 passed, exit 0.
- 최종 결제·설정·라우터 영향 테스트: 35 passed, exit 0.
- 최종 직접 Dart 분석 --fatal-infos: 진단 없음, exit 0.
  결제/연결부 16개 Dart 파일 format 검사 0 changed, git diff --check exit 0.
- `fvm flutter analyze`: 기존 한글 경로 출력 파싱 `FormatException: Unterminated string`,
  exit 255. 직접 `fvm dart analyze --fatal-infos --format machine`으로 보완했다.
- Android dev debug APK 빌드 exit 0. 일부 기존 플러그인의 Built-in Kotlin 이행 경고가
  있었으나 빌드 성공. 서명 릴리스/Play 업로드는 실행하지 않았다.
- iOS Duo simulator Xcode build 38.6초, generated HTTP UI 시나리오 통과 exit 0.
  iPhone 18 Pro 세로 simulator build 42.6초, 동일 시나리오 통과 exit 0.
  최종 문구 보완 후 iPhone 18 Pro build 31.4초, 10상태 QA exit 0.
- 390/1440 폭 × light/dark 위젯 상호작용 4개 통과. 네이티브 캡처에서 현지 가격,
  대기, 취소, 승인 재시도, 검증 성공, 연결 실패, 복원, 이전 계정 거부, 미설정,
  store unavailable 총 10상태를 확인했다. 세로 화면의 한글 줄바꿈을 짧게 보완했다.
- 독립 하위 리뷰는 이 세션의 nesting depth 1 제한으로 실행할 수 없었다.
  에이전트 자체 시각 확인이며 독립 QA 통과로 주장하지 않는다.
- 최종 native PNG 10개 위치:
  `/var/folders/3r/x0sqsx_d3012q12cpbyzhbp80000gn/T/tmp.n8TBW6CR6A/billing-screenshots/`.
  `billing-ready`, `billing-pending`, `billing-canceled`, `billing-approval-retry`,
  `billing-verified`, `billing-network-failure`, `billing-restored-dark`,
  `billing-old-account-rejected`, `billing-unconfigured`, `billing-store-unavailable`.
  각 PNG는 1206×2622이며 최종 화면 10개를 직접 열어 확인했다.
  레이아웃/잘림/상태 행동 자체 확인은 통과, 독립 시각 리뷰·모든 상태의
  light/dark 교차 캡처·VoiceOver 수동 검증은 미실행이다.
- 기존 미커밋 기능/설정/override를 보존했고 commit/push/deploy는 하지 않았다.
- 스토어 자격증명, 실제 상품/가격 응답, sandbox 구매·복원·환불·갱신,
  Apple/Google 실제 승인/완료, 물리 기기, 사용자 직접 확인은 외부 미검증이다.

최초 실패는 하네스 예외를 toJson만으로 보낸 점과 구매 진행 indicator에 대한
pumpAndSettle 사용이었다. 생성 Protocol wrapper와 정확한 controller 완료 신호로
수정했다. 라우터 push는 routeInformationProvider의 URL이 아니라 실제
routerDelegate 현재 매치와 화면 존재로 검증했다. 테스트를 약화하거나 skip하지 않았다.

장애 확인 순서: configuration/상품 allowlist → 현재 로그인과 원래 구매 binding →
API 오류 code → acknowledgementPending 및 native 미완료 목록 → 스토어 환경/권한.
구매 원문·인증 헤더를 운영 로그로 출력하지 않는다. 직접 확인은 설정의 구매 및 복원에서
미설정 시 가격/구매가 없는지, 재시도 시 과거 성공이 남지 않는지 먼저 살핀다.
