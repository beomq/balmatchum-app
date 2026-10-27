# 유료 혜택 앱 통합 검증

계약: 서버 `4487b88ced56307527b7f951bd1916cc724b7cc6`의
`docs/PAID_BENEFITS_API.md`. 앱 Git client ref는 기존
`93435c4cdd53c8b9f802007dccfe4899f8109ead`를 변경하지 않았다.
미게시 서버 client는 기존 `pubspec_overrides.yaml` 상대 경로로만 사용한다.
원격 client만으로 이 증분을 빌드할 수 있다고 주장하지 않는다.

## 구현과 선택

- `billingRepositoryProvider`가 계정 인증 객체를 캡처한
  `ServerpodBillingRepository`를 공유한다. 그 public `request`가 기존
  `BillingRequestQueue`에서 계정별 직렬 실행한다. 구매 확인·복원·entitlement와
  `claimDayWithPremium/getTodayWithPremium/unlockExtraWithPremium` 모두 같은 큐다.
  별도 프리미엄 큐는 서버 account observation sequence를 보호하지 못하므로 쓰지 않았다.
- 보상은 `checkPremium`으로 새 entitlement를 조회하고 날짜 projection도 갱신한 뒤
  별도 버튼으로 `claimWithPremium`을 호출한다. 표시 금액은 서버의
  `adClaimablePoints` 그대로이며 기지급분 topup을 계산하지 않는다.
  무료 유예가 만료된 `adRequired`도 가능하다. 서버가 실제 소비 시 재검증한다.
- 퀴즈 기본 `load`는 무료 API이며 `premiumStatus: notChecked`다.
  `checkPremium`만 결제를 조회하고 active/inactive를 구분한다. 조회 오류는 별도
  오류 상태이며 inactive로 바꾸지 않는다. active와 premiumAvailable 모두 있어야
  명시적 추가 발급이 가능하다. 발급 후 제출은 무료 `answer` 경로 그대로다.
- 광고 표시 시작부터 컨트롤러의 공유 busy gate를 획득한다. 무료·광고·유료 변경과
  프리미엄 관측이 서로 겹치지 않는다. 구매 API와의 경합은 공통 계정 큐가 처리한다.
- 응답 유실 뒤 요청 closure가 원래 date/revision/requestId/지급 방식을 보존한다.
  다른 날짜·방식은 차단하고 같은 요청 재생만 제공한다. 이전 유실이 없는 확정
  BillingException은 새 조회/무료·광고 선택을 허용한다. 유실 뒤 BillingException은
  이미 성공했을 가능성이 있으므로 원본을 유지한다. 퀴즈 발급 재생 후 getToday로
  현재 제출 상태를 재조정한다.
- 구매 자동 실행은 없다. 월별 선물은 미구현 안내를 유지한다.

## 자동 검증 범위

`paid_reward_test.dart`, `paid_quiz_test.dart`, `paid_request_queue_test.dart`는
명시적 선택, 미확인/비활성/오류, 공유 gate, 원본 재생, 계정 변경, A→B→A의 캡처
인증 폐기 및 구매/퀴즈/보상 관측의 최대 동시 HTTP 요청 1개를 확인한다.
이 큐 HTTP 테스트는 로컬 응답 대역이다. 아래 네이티브 테스트와 구분한다.

`paid_benefits_server_test.dart`는 실제 iOS Flutter UI에서 생성 client HTTP,
실제 Serverpod endpoint, 격리 PostgreSQL 원장과 서버 Google 구매 파서를 사용한다.
외부 OAuth/Google store 전송만 고정 fixture다. 실제 Google/Apple sandbox 구매를
검증한 것이 아니다. 테스트 문항은 운영 승인 콘텐츠가 아니며 지급 기록 2P씩은
fixture 정책 원장에만 기록되어 운영 걸음 지갑에 합산되지 않는다.

실제 서버 commit 응답을 앱 repository 경계에서 한 번 유실시키고, 스토어 장애 중
원본 요청을 재전송하여 걸음과 추가 퀴즈의 DB 성공 재생을 검증한다.
실제 네트워크 패킷 손실이나 프로세스 강제 종료 테스트는 아니다.

## 재현

APP은 앱 worktree, SERVER는 서버 worktree 절대 경로다. 서버를 수정하지 않는다.
하네스 template은 소스 위치에서 실행하므로 fixture 상대 import가 유지된다.

```sh
export RUN_TMP="$(mktemp -d /tmp/bmpaid-native.XXXXXX)"
export TMPDIR="$RUN_TMP/" XDG_CACHE_HOME="$RUN_TMP/cache" PUB_CACHE="$HOME/.pub-cache"
export PATH="/Users/beomseok/fvm/versions/3.47.5/bin/cache/dart-sdk/bin:$PATH"
mkdir -p "$XDG_CACHE_HOME"
cd "$SERVER/server"
SERVERPOD_PASSWORD_database=local-disposable-test-only \
  dart --packages=.dart_tool/package_config.json \
  "$APP/integration_test/support/paid_benefits_server_harness.dart.template"
```

`PAID_HARNESS_READY` 이후 별도 셸에서 실행한다. API 18110, 로컬 QA seam 18111을
사용하며 서버 실행의 RUN_TMP에 native PNG를 저장한다. 매 실행 새 DB로 시작한다.

```sh
export RUN_TMP="$(mktemp -d /tmp/bmpaid-ios.XXXXXX)"
export TMPDIR="$RUN_TMP/" XDG_CACHE_HOME="$RUN_TMP/cache" PUB_CACHE="$HOME/.pub-cache"
mkdir -p "$XDG_CACHE_HOME"
cd "$APP"
XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter test integration_test/paid_benefits_server_test.dart --flavor dev \
  --dart-define=ADMOB_TEST_ADS=true -d 06C7AD47-C910-4D53-95C3-C1AD6283311B \
  --reporter expanded
fvm flutter test --reporter expanded --dart-define=PAID_RENDER=true
fvm dart analyze --fatal-infos --format machine
```

## 한계와 장애 확인 순서

원본 mutation은 컨트롤러 수명 동안 유지되며 디스크에 저장하지 않는다. 재시작 후
서버의 최신 날짜·지갑·퀴즈를 조회해야 하고 과거 성공을 잔액 차이로 추정하지 않는다.
외부 sandbox/콘솔/실구매·실제 광고·물리 기기·Android native·월별 선물·운영 문항은
이번 실행으로 검증하지 않는다. 서버 게시·배포·커밋·푸시는 하지 않았다.

장애 확인은 인증 객체 및 공통 큐 → BillingException code → 새 entitlement 또는
quiz premiumStatus → date/revision 및 adClaimablePoints/extraRevision → 원래
requestId → 서버 원장 순서다. 구매 원문은 로그에 출력하지 않는다.
직접 확인은 새 하네스에서 유료 확인만으로 지갑/추가 문제 불변, 명시적 수령 후 180P,
원본 재생 후 180P 유지, 추가 발급 후 스토어 장애 중에도 답 제출과 2P 기록을 확인한다.
사용자 직접 확인과 이해는 미확인이다.

## 최종 실행 근거 (2026-10-19)

- 전체 `fvm flutter test --reporter expanded --dart-define=PAID_RENDER=true`:
  **347 passed**, 종료 0. `fvm dart analyze --fatal-infos --format machine`:
  진단 없음, 종료 0. 변경 Dart 18개 format 검사: 변경 0개, 종료 0.
- `fvm flutter analyze`는 기존 한글 경로 JSON 파싱 문제
  `FormatException: Unterminated string`이 재현됐다. 동일 SDK의 위 Dart 분석과
  구분한다. LSP는 일부 호출에서 최신 진단 시간 초과가 있었다.
- iOS simulator `06C7AD47-C910-4D53-95C3-C1AD6283311B`:
  Xcode build 37.2초, native test **1 passed**, 종료 0.
  실제 원장 3행, 걸음 지갑 180P, fixture 퀴즈 무료/추가 각각 2P 기록,
  응답 유실 원본 재생, 장애 오류와 환불 inactive를 확인했다.
- 빌드된 Runner.app Info.plist의 GADApplicationIdentifier:
  `ca-app-pub-3940256099942544~1458002511`. 명시적 AdMobTest 설정 적용 확인.
- native 캡처 6개: `/tmp/bmpaid-native.r2yJGK/paid-*.png`.
  단위 렌더 16개: `/tmp/bmpaid-final.WN4CgK/paid-*.png`.
  보상·퀴즈를 390/1440, light/dark, top/end로 렌더했다. 실제 캡처를 직접 열어
  프리미엄 CTA와 본문에 겹침/잘림이 없는 것을 확인했다. 일부 native 상태 캡처는
  스크롤 위치 때문에 상태 문구가 프레임 밖에 있으므로 해당 상태의 증거는 테스트
  assertion이며 캡처만으로 전 상태 시각 검증을 주장하지 않는다.
- 독립 리뷰는 child 중첩 제한으로 실행할 수 없었다. 이 기록은 구현자 검증이며
  독립 시각 QA 승인이나 전체 접근성 검증으로 표시하지 않는다.
- 처음 서버 하네스의 embedded DB 기본 연결 1개가 마이그레이션 lock을 막아
  기존 서버 테스트와 같은 maxConnectionCount 10으로 수정했다. 첫 native 실행의
  184P 기대는 fixture 퀴즈의 운영 지갑 분리 정책과 맞지 않아 180P로 바로잡았다.
  앱/서버 정책 또는 기존 테스트를 완화하지 않았다.
- 서버 worktree `git status --porcelain`은 비어 있고 앱 `git diff --check` 종료 0.

## 이 작업에서 변경한 정확한 파일

모두 앱 worktree 기준이며 기존 dirty 변경은 보존했다.

```text
lib/features/billing/billing_repository.dart
lib/features/billing/billing_providers.dart
lib/features/billing/billing_screen.dart
lib/features/daily_activity/product_repository.dart
lib/features/daily_activity/daily_activity_providers.dart
lib/features/daily_activity/product_controller.dart
lib/features/daily_activity/reward_panel.dart
lib/features/quiz/quiz_repository.dart
lib/features/quiz/quiz_providers.dart
lib/features/quiz/quiz_controller.dart
lib/features/quiz/authenticated_quiz_screen.dart
test/features/quiz/authenticated_quiz_test.dart
test/features/quiz/quiz_repository_test.dart
test/features/daily_activity/paid_reward_test.dart
test/features/quiz/paid_quiz_test.dart
test/features/billing/paid_request_queue_test.dart
test/features/billing/paid_benefits_render_test.dart
integration_test/paid_benefits_server_test.dart
integration_test/support/paid_benefits_server_harness.dart.template
docs/DESIGN.md
docs/PAID_BENEFITS_APP_QA.md
```
