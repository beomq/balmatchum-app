# 인증 퀴즈 앱 통합

서버 계약은 `89200d0`의 `docs/QUIZ_ENGINE_API.md`이다. 인증 화면은 생성
`client.quiz` API만 사용하고 기존 dev `DailyQuizScreen`과 product fixture 경로는
그대로 둔다. 운영 검토 완료 문항·프리미엄·결제를 만들지 않는다.

## 데이터와 인증 경계

- `QuizRepository._request`는 매 작업 시작 시 인증 객체와 헤더를 캡처하고 별도
  Client에 고정한다. 헤더 준비 후와 응답 후 동일 인증 객체인지 검사한다.
  getToday/answer/unlockExtra/listHistory/review 모두 같은 경계를 사용한다.
- `authenticatedQuizControllerProvider`는 계정별 수명이며 router의 완료된 인증
  프로필만 /quiz에 접근한다. 화면 밖에서 돌아온 이전 계정 결과도 반영하지 않는다.
- `QuizController`는 응답 유실 시 원래 payload와 requestId를 closure에 보관한다.
  선택 변경·신규 광고·추가 mutation을 막고 같은 요청 확인 버튼만 제공한다.
  확정 ProductException/AdException 이후에는 최신 상태 조회를 요구한다.
- 광고는 기존 createAdsController/showAdsSheet를 사용한다. 시트 close의 cancel
  전에 verified 이벤트에서 purpose/date/revision이 일치하는 인텐트를 저장한다.
  이후 명시적 추가 문제 열기로만 unlockExtra를 호출한다. SDK 보상 신호만으로
  지급하거나 문제를 발급하지 않는다. unlock 응답 재생 후 getToday로 재조회한다.

## 지급 기록과 화면

최초 제출은 정오답과 관계없이 서버 정책상 2P이다. DTO의 awardedPoints는 그 발급의
누적 지급 기록이며 이 호출의 신규 지급량이 아니다. 앱은 저장 확인과 기존 지급
기록을 표시하고 재전송·복습에 신규 지급 표현을 사용하지 않는다. 현재 API는 새 지급
여부를 반환하지 않으므로 동시 기기에서 먼저 제출한 상황까지 신규 2P로 단정할 수 없다.

빈 뱅크 contentUnavailable과 소진 exhausted를 구분한다. 조건은 제출 전에 표시하고
해설·출처·정답·검토 정보는 서버 제출 응답 뒤 표시한다. 출처는 선택·복사 가능하다.
이력은 최대 30개씩 마지막 assignmentId를 다음 커서로 사용하고 review로 다시 읽는다.
testFixture 라벨과 운영 지갑 제외 안내를 유지한다.

## 실행 환경과 재현

자기 실행 전용 임시 경로를 만든다. 아래 환경은 모든 실행 명령에 적용한다.

```sh
RUN_TMP=$(mktemp -d /tmp/bm-quiz.XXXXXX)
export RUN_TMP TMPDIR="$RUN_TMP" NODE_COMPILE_CACHE="$RUN_TMP/node"
export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$RUN_TMP/bun"
export CLANG_MODULE_CACHE_PATH="$RUN_TMP/clang" SWIFT_MODULECACHE_PATH="$RUN_TMP/swift"
```

하네스 template를 RUN_TMP/quiz_server_harness.dart로 복사하고 두 상대 import를
서버 test/test_utils/ad_test_keys.dart와 quiz_fixture.dart의 실제 위치로 연결한다.
서버 package에서 고정 Flutter 3.47.5에 포함된 Dart 3.13.4와
`--packages=.dart_tool/package_config.json`으로 실행한다. disposable DB 비밀번호는
`SERVERPOD_PASSWORD_database=local-disposable-test-only`이다.
서버 작업 트리 소스는 수정하지 않는다. 하네스는 test 모드, 격리 PostgreSQL,
loopback API18100/seam18101을 사용하며 `QUIZ_HARNESS_READY`가 준비 신호다.

```sh
XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter test integration_test/quiz_server_test.dart --flavor dev \
  --dart-define=ADMOB_TEST_ADS=true -d 06C7AD47-C910-4D53-95C3-C1AD6283311B
fvm flutter test --reporter expanded
fvm flutter analyze
fvm dart analyze --format machine
```

## 한계와 장애 확인

requestId는 controller 수명 동안 보존한다. 앱 종료 후에는 서버 상태를 재조회하며
원래 요청 ID를 디스크에서 복구하지 않는다. 서버의 발급·정답 idempotency가 중복
지급을 막는다. 실제 Google 광고 표시·Google발 SSV·물리 기기·운영 배포는 별개다.
로컬 네이티브 테스트는 광고 표시만 fake이며 실제 HTTP API, 서명 검증, 트랜잭션을
사용한다. 사용자 직접 검증·이해는 에이전트 QA와 별개이며 미확인이다.

문제 발생 시 현재 인증/헤더 → getToday의 date/extraRevision → 광고 purpose와
verified → 원래 requestId/payload → 최신 getToday/history 순서로 확인한다.

## 2026-10-19 실행 증거

- 실행 경로 `/tmp/bm-quiz.mNd1fK`는 mktemp로 만들었다. TMPDIR, Node/Bun,
  Clang/Swift module cache 환경을 각 검증 명령에 전달했다.
- 전체 `fvm flutter test --reporter expanded`: 298 passed, exit 0.
  최종 대비·안내 보완 후 퀴즈/라우터 영향 테스트 31 passed, exit 0.
- 변경 퀴즈 파일·통합 테스트 포맷 검사: 7 files, 0 changed, exit 0.
  해당 경로 `fvm dart analyze --format machine`: 진단 없음, exit 0.
  편집기 LSP의 퀴즈 폴더도 진단 없음이다.
- `fvm flutter analyze`: 기존 한글 경로 출력의 JSON `FormatException:
  Unterminated string`, exit 255. 전체 직접 Dart 분석 exit 0에는 기존
  reward_panel.dart 117/142, reward_server_test.dart 171의 중괄호 lint 3개가
  남았다. 이 범위 밖 파일을 수정하거나 경고를 억제하지 않았다.
- 후속 통합에서 리드가 위 보상 경로의 중괄호 lint 3곳을 수정했다.
  전체 `fvm dart analyze --fatal-infos --format machine`은 진단 없이 exit 0이었다.
- 초기 새 위젯 테스트는 선택 직후 pump 없이 비활성 제출 버튼을 탭해 1개
  실패했다. 선택 변경 렌더를 pump하고 제출 버튼을 표시한 뒤 통과했다.
- 390/1440 × light/dark × 5 상태(contentUnavailable/exhausted/freeRequired/
  adRequired/issued) × top/end = 40개 widget PNG를 생성했다.
  네이티브 결과에서 답안 선택지의 disabled 색 대비가 낮아 onSurface로 보완했다.
  테스트 렌더의 MaterialIcons fallback 사각형과 강제 dark의 기존 공통 home 아이콘
  낮은 대비는 공유 ProductTopBar의 범위 밖 한계다. 운영 앱에는 현재 light 테마만
  구성되어 있다. 독립 QA 하위 에이전트는 nesting depth 제한으로 실행 불가였다.

### 실제 네이티브 흐름

iOS simulator `06C7AD47-C910-4D53-95C3-C1AD6283311B`에서 AdMobTest.xcconfig와
ADMOB_TEST_ADS=true를 명시했다. 첫 실행 Xcode build 38.9초, 1 passed, exit 0.
최종 화면 보완 후 새 격리 DB에서 다시 실행: Xcode build 48.3초,
1 passed, exit 0. 최종 10개 네이티브 캡처를 직접 열어 확인했다.
완료 후 이 작업이 시작한 하네스와 그 프로세스 트리를 종료했다.
테스트는 실제 AuthServices 발급 세션과 test 모드의 명시적 testFixture 뱅크만 쓴다.

| 관찰 | 결과 |
| --- | --- |
| 빈 뱅크 getToday | contentUnavailable, 제출/광고 없음 |
| 무료 문항 발급 | fixture 라벨·조건 표시, 제출 전 해설/출처 없음 |
| 오답 제출 | answerIndex 1, correctIndex 0, 기존 지급 2P, 운영 wallet 0 |
| 남은 뱅크가 본 ID뿐인 상태 | 추가 exhausted, 빈 뱅크와 구분 |
| 실제 서명 SSV verified | extra 미발급, wallet 0 유지 |
| 광고 시트 close | verified 인텐트 유지, 별도 열기 버튼 |
| 명시적 unlockExtra | extra 발급, intent consumed |
| 추가 정답 제출 | 지급 기록 2P, 운영 wallet 0 유지 |
| 이력 → 복습 | 무료/추가 두 발급 표시, review 읽기, 신규 지급 없음 |

캡처는 `quiz-empty-bank/free-question/wrong-answer/exhausted/verified-ad/
explicit-unlock/extra-question/extra-answer/history/review.png`이다. 화면과 서버
상태를 함께 검증했다. 실제 네이티브 화면은 직접 마운트했고 GoRouter 보호/진입은
위젯 회귀로 검증했다. 테스트용 내부 세션을 운영 로그인으로 간주하지 않는다.

### 서버 계약 관찰

추가 API 오류는 발견하지 않았다. 빈 뱅크의 extraStatus는 freeRequired이므로
무료 문항 자체가 없을 때는 아직 제출할 수 없는 상태에 맞춰 안내한다.
awardedPoints만으로 이번 호출이 새로 지급했는지 구분할 수 없다. 신규 지급 알림이
필요하면 서버가 replay 여부 또는 신규 지급량을 별도로 제공해야 한다. 현재 화면은
저장 확인과 과거 지급 기록만 말하며 잔액 차이로 지급을 추정하지 않는다.
