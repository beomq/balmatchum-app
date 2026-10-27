# 운영 걸음 보상 앱 통합

서버 `50c0eca`의 생성 client와 `PRODUCT_API.md`, `ADMOB_SSV_API.md`를 기준으로 한다.
운영 계정은 getDay/getWallet만 조회하며 fixture quiz/theme를 호출하지 않는다.
이 작업은 로컬 검증이며 라이브 광고, 결제, 콘솔 설정, 커밋, 푸시를 수행하지 않는다.

## 연결과 선택 이유

- `ProductRepository._records`가 실제 계정의 인증 객체와 헤더를 캡처한다.
  getWallet/claimDay/claimDayWithAd도 이 경계를 통과하며 응답 도착 시 인증 객체를
  다시 비교한다. 이전 계정의 성공 응답도 새 계정 화면에 반영하지 않는다.
- `ProductController`는 wallet과 오늘 기록을 서버에서 읽고, 수령 반환값의 amount만
  사용한다. 걸음당 포인트, 상한, 배수, 지급 구간을 앱에서 계산하지 않는다.
- `RewardPanel`은 무료 금액과 광고 총액을 각각 표시한다. 무료는 유예 중인 구간만,
  광고는 미수령 전체 기본분의 총 2배다. 무료 수령 후 최신 날짜를 다시 읽으며
  만료된 구간이 남으면 adRequired로 표시한다. 재조회 실패 시 완료 상태를 추정하지
  않고 추가 수령 버튼을 막아 재조회를 요구한다.
- 광고는 기존 createAdsController/showAdsSheet를 사용한다. 시트가 닫히면 취소되므로
  listener에서 verified와 일치하는 날짜/revision의 intent ID를 먼저 저장한다.
  시트 종료 후 별도 수령 버튼을 눌러야 claimDayWithAd를 호출한다.
  onUserEarnedReward나 verified 이벤트만으로 포인트를 지급하지 않는다.
- 홈은 오늘만, 과거는 기록 달력과 날짜 상세에서 받는다. 기존 지도 및 삭제 경로는
  유지한다. 부모가 router의 authenticated home/product와 day/rewardController를 조립했다.
- legacyPolicyExcluded는 운영 수령 대상으로 바꾸지 않고 fixtureLabel을 유지한다.

## 재시도와 한계

request ID는 controller 수명 동안 `(date, revision, intentId)` 키로 유지한다.
전송 실패/응답 유실은 같은 payload와 ID로 재시도하며 성공을 추정하지 않는다.
서버 ProductException은 확정 거절로 처리해 새 사용자 동작에는 새 ID를 사용한다.
staleProjection/adRequired/legacyPolicyExcluded는 각각 안내하고 최신 날짜를 읽는다.

request ID는 디스크에 저장하지 않는다. 앱 재시작 뒤에는 원래 request ID를 재생하지
못하므로 지갑과 날짜의 서버 상태를 다시 읽는다. 서버 revision과 기지급 slices가
중복 지급을 막으며 앱은 잔액 변화만으로 특정 요청 성공을 선언하지 않는다.
현재 단위 테스트는 같은 controller에서 응답 유실 재시도와 늦은 계정 응답 차단을
검증한다. 네이티브 테스트는 성공 경로와 실제 원장/SSV를 검증하며 프로세스 강제 종료
직전 응답 유실은 주입하지 않았다.

## 재현

앱 worktree와 서버 worktree를 각각 APP, SERVER로 지정한다. SERVER는 server 저장소
루트이며 서버 Dart package는 `$SERVER/server`이다. 모든 셸에서 짧은 임시 경로를 쓴다.

```sh
export RUN_TMP=/tmp/bm-reward TMPDIR=/tmp/bm-reward
mkdir -p "$RUN_TMP"
cd "$SERVER/server"
cp "$APP/integration_test/support/reward_server_harness.dart.template" "$RUN_TMP/reward_server_harness.dart"
cp test/test_utils/ad_test_keys.dart "$RUN_TMP/ad_test_keys.dart"
SERVERPOD_PASSWORD_database=local-disposable-test-only \
  dart --packages=.dart_tool/package_config.json "$RUN_TMP/reward_server_harness.dart"
```

호스트 Dart는 Flutter 3.47.5에 포함된 3.13.4를 사용했다. 하네스는 임시 PostgreSQL과
loopback API 18090/QA seam 18091을 시작한다. `REWARD_HARNESS_READY`가 준비 신호다.
QA seam은 테스트 세션과 공개 disposable ECDSA 키를 사용한 SSV 이벤트만 제공한다.
POST /capture는 네이티브 PNG를 RUN_TMP로 내보낸다. Flutter test의 앱 제거 후에도
증거를 유지하기 위한 테스트 전용 경로다.
운영 서버에 이 seam을 추가하지 않는다. template를 별도 실행하는 이유는 앱 package에
서버 의존성을 넣지 않기 위해서다. 재실행은 새 하네스를 시작한다.

```sh
cd "$APP"
XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter test integration_test/reward_server_test.dart --flavor dev \
  --dart-define=ADMOB_TEST_ADS=true -d 06C7AD47-C910-4D53-95C3-C1AD6283311B
fvm flutter test --reporter expanded
fvm flutter analyze
fvm dart analyze --format machine
fvm flutter test test/features/daily_activity/reward_panel_test.dart \
  --dart-define=REWARD_RENDER=true --reporter expanded
```

## 확인된 증거

- 전체 단위/위젯 테스트: 272 passed, exit 0. 고정 헤더 wallet/free/ad 요청,
  늦은 계정 응답, fixture 차단, 응답 유실 ID 재사용, 부분 무료 이후 광고 잔여,
  시트 취소와 verified 이전 캡처, 명시적 수령, 기존 지도/라우터 회귀를 포함한다.
- `fvm flutter analyze`: 기존 한글 경로 LSP JSON 파싱 오류 exit 255 재현.
  `fvm dart analyze --format machine`: 전체 진단 없음, exit 0.
  편집기 LSP는 이전 DTO/파일 캐시를 반환하므로 이 결과와 구분한다.
- RewardPanel의 eligible/adRequired/settled/legacyPolicyExcluded/pending/futureDate를
  390/1440 너비와 light/dark의 24개 캡처로 확인했다. 겹침/잘림 없음.
  dark 테스트의 초기 fallback 폰트가 사각형으로 렌더링되어 Pretendard를 명시한 뒤
  다시 캡처했다. 운영 앱의 새 다크 테마를 추가한 것은 아니다.
- 증거와 로그는 `/tmp/bm-reward`에 있다.

## 네이티브 최종 결과

`integration_test/reward_server_test.dart`: iOS simulator
`06C7AD47-C910-4D53-95C3-C1AD6283311B`, Xcode build 35.2초,
1 passed, exit 0. 로그 `native-verified.log`.
명시적 AdMobTest.xcconfig와 ADMOB_TEST_ADS=true를 전달했다.

실제 로컬 서버가 만든 과거 70단위 만료 + 새 20단위 유예 기록에 대해 다음을 통과했다.

| 화면/서버 상태 | 확인 | 결과 |
| --- | --- | --- |
| 달력 과거 날짜 | 9,000걸음과 받을 포인트 표시, 날짜 탭 | PASS |
| 최초 상세 패널 | 무료 20P, 광고 총 180P | PASS |
| 무료 수령 뒤 | wallet 20, adRequired, 무료 버튼 없음, 광고 140P | PASS |
| 실제 서명 SSV verified | 지갑은 여전히 20P, 자동 지급 없음 | PASS |
| 시트 닫기 | 검증 intent 보존, 별도 140P 수령 버튼 | PASS |
| 명시적 광고 수령 뒤 | wallet/granted 160P, settled, intent consumed | PASS |

네이티브 캡처 6개를 직접 열어 겹침/잘림이 없음을 확인했다:
`reward-calendar.png`, `reward-mixed-free.png`, `reward-expired-remains.png`,
`reward-ssv-verified.png`, `reward-explicit-ad-claim.png`, `reward-settled.png`.
이 네이티브 테스트는 달력과 실제 RewardPanel을 직접 마운트한다. 전체 GoRouter 경로와
오늘 홈 주입은 `authenticated_records_router_test.dart`의 단위/위젯 회귀로 검증했다.
실제 네이티브 Google SDK 시청/Google발 callback과 물리 센서는 실행하지 않았다.

최초 네이티브 시도는 달력 재조회에서 같은 Completer를 두 번 완료한 테스트 오류로
실패했다. 한 번만 완료하는 guard로 수정했다. 두 번째 시도에서는 실제 무료 수령과
adRequired/140P 잔여를 확인했으나 QA가 만든 transaction_id가 base64url여서 실제
SSV 검증기가 거절했다. 서버가 요구하는 hex로 수정했고 앱/서버의 검증을 완화하지 않았다.

## 외부 SSV 한계와 장애 확인

로컬 테스트는 SDK 표시 부분만 fake이며 실제 생성 HTTP client, PostgreSQL,
raw HTTP SSV listener, ECDSA 검증, intent 소비와 지급 transaction을 사용한다.
Google 서버의 실제 서명키 전달·콘솔·공개 HTTPS 프록시·라이브 광고를 증명하지 않는다.
공식 공용 테스트 광고 unit만으로 운영 SSV 수신까지 증명할 수도 없다.

장애 시 인증 계정/헤더 → getDay 정책·revision·무료/광고 금액 → intent verified 및
대상 날짜/revision → claim 오류 코드 → wallet/원장 slices 순서로 확인한다.
직접 확인은 새 하네스에서 무료 20P → 남은 광고 140P → verified만으로 잔액 불변 →
명시적 수령 뒤 잔액 160P와 consumed를 확인한다. 사용자 직접 검증과 이해는 미확인이다.
