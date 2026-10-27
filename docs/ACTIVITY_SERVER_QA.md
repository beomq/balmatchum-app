# 인증 활동 실서버 네이티브 QA

## 검증 계약

`integration_test/authenticated_activity_server_test.dart`는 localhost:18080 격리 서버가
발급한 세션을 `importDevTestSession`으로 가져온다. 서버 인증 상태를 확인한 다음
`authenticatedAccountProvider`, `authenticatedMeetingControllerProvider`,
`authenticatedProductControllerProvider`를 사용한다. ProductRepository의 accountId가
현재 인증 계정인지 확인한다. 토큰은 출력하거나 이 문서에 저장하지 않는다.

프로필이 없으면 생성 client.profile.createProfile로 pug/활동친구/female/7000
프로필을 만든다. 기존 프로필은 바꾸지 않는다. 센서 입력만 available/5000으로
대체하고, ProductController.sync → 실제 StepUpload → 생성 HTTP client → 서버를
사용한다. 앱 Application Support의 steps-계정.json에서 generation/revision이 서버
응답과 일치하고 pending이 제거된 것을 확인한다.

실제 RecordsCalendarScreen에 월 5.0k를 표시하고 날짜 셀을 누른 뒤 실제
RecordDayScreen에 5,000걸음을 표시한다. 삭제 확인창의 확정 버튼으로 실제
ProductController.deleteDay를 호출한다. UI 삭제 상태와 서버 deleted/deletionVersion,
steps null/routes empty를 검증한다. 재동기화해도 tombstone이 유지되어야 한다.
마지막 PhotoScreen은 서버에서 복원한 실제 프로필의 이름과 품종 sprite를 사용하고
실제 asset 디코딩 완료를 확인한다.

## seam과 한계

- `--flavor dev`의 기본 라우터는 개발 컨트롤러를 선택하므로, 이 테스트는 인증
  provider의 컨트롤러와 실제 기록/사진 위젯을 직접 마운트한다. 달력 날짜 탭은
  실제 이벤트로 확인하되 GoRouter push/pop과 OAuth 로그인 UI는 검증하지 않는다.
- HealthKit 센서 결과만 5000 fixture다. 실제 센서 권한·기기 걸음 수·GPS와 Watch
  전송은 검증하지 않는다. Watch service는 null override로 제외한다.
- 보상/퀴즈/테마 fixture API는 호출하지 않는다. StepUpload의 stream generation
  조회에 필요한 getWallet만 사용한다. 인증 기록에서는 claim 버튼이 없어야 한다.
- 사진 선택/합성/저장/공유는 실행하지 않는다. 실제 서버 프로필과 asset의 연결,
  빈 사진 편집 화면까지만 검증한다.
- 테스트는 오늘 기록을 영구 삭제한다. 같은 계정·같은 날짜 재실행은 사전 조건에서
  실패하도록 했다. 새 격리 서버 계정을 발급하고 세션을 다시 주입해야 한다.
- HTTP는 실서버지만 격리 로컬 환경이다. 운영 OAuth, Android, 물리 기기, 다크모드,
  큰 글자 전체 행렬은 범위 밖이다. 사용자의 직접 확인/이해는 미확인이다.

## 재현과 장애 확인

모든 명령은 앱 워크트리에서 실행하고 각 셸에 다음 환경을 설정한다.

```sh
export RUN_TMP=/tmp/aqa15274
export TMPDIR="$RUN_TMP" NODE_COMPILE_CACHE="$RUN_TMP/node" BUN_RUNTIME_TRANSPILER_CACHE_PATH="$RUN_TMP/bun"
```

build에는 Watch companion 대상 혼동을 막기 위해 반드시 `-d`를 전달한다.
설치 후 `simctl get_app_container ... data`로 실제 컨테이너를 구하고 비공개 세션을
`Library/Application Support/dev-test-session.json`에 mode 600으로 설치한다.
실행은 `flutter test --no-uninstall`을 사용한다. drive에는 이 플래그가 없다.
HTTP/asset 완료는 동작 전에 등록한 Completer와 20초 timeout으로 기다린다.
고정 sleep과 상태 polling은 없다. pumpAndSettle은 HTTP 완료 후 프레임 정리에 쓴다.
화면 캡처는 각 의미 있는 상태에서 integration binding으로 찍고 앱 지원 디렉터리의
activity-qa에 PNG로 저장한다.

장애 시 세션 파일 존재/서버 인증 → SERVER_URL과 client override → 계정별 steps
generation/revision/pending → getDay tombstone → UI load callback 순으로 확인한다.
토큰이나 인증 헤더를 로그에 출력하지 않는다. 직접 확인은 새 격리 계정으로 아래
명령을 재실행하고 월/일/삭제 확인/삭제 완료/사진 프로필 PNG를 열어 비교한다.

## 실행 결과

2026-10-19, RUN_TMP `/tmp/aqa15274`, 실제 iOS simulator
`06C7AD47-C910-4D53-95C3-C1AD6283311B`, bundle `com.beomq.balmatchum.dev`.

```sh
fvm dart analyze integration_test/authenticated_activity_server_test.dart
fvm flutter build ios --simulator --debug --flavor dev \
  -d 06C7AD47-C910-4D53-95C3-C1AD6283311B \
  --target integration_test/authenticated_activity_server_test.dart \
  --dart-define=SERVER_URL=http://localhost:18080/
xcrun simctl install 06C7AD47-C910-4D53-95C3-C1AD6283311B build/ios/iphonesimulator/Runner.app
DATA=$(xcrun simctl get_app_container 06C7AD47-C910-4D53-95C3-C1AD6283311B com.beomq.balmatchum.dev data)
mkdir -p "$DATA/Library/Application Support"
install -m 600 "$PRIVATE_SESSION_FILE" "$DATA/Library/Application Support/dev-test-session.json"
fvm flutter test integration_test/authenticated_activity_server_test.dart \
  --flavor dev -d 06C7AD47-C910-4D53-95C3-C1AD6283311B --no-uninstall \
  --dart-define=SERVER_URL=http://localhost:18080/
```

`PRIVATE_SESSION_FILE`은 리드가 제공한 비공개 서버 세션 파일이다. 위 명령은 내용을
출력하지 않는다. Dart 분석 No issues found, exit 0. 시뮬레이터 build exit 0
(Xcode build 34.6초), install/컨테이너 조회/세션 주입 모두 exit 0.
통합 실행은 `01:01 +1: All tests passed!`, exit 0. 실행 중 재빌드도
Xcode build 32.5초로 완료했다. 실제 세션 import true와 서버 signedIn true,
계정 provider 일치, 실프로필 생성/복원, 5000 HTTP 업로드와 계정별 디스크 상태,
실제 월/일 UI, 삭제 확정과 tombstone, 재동기화 후 삭제 보존, 사진 프로필/asset
검증을 모두 통과했다. 전체 단위 테스트는 부모 소유라 이번 자식 작업에서 실행하지
않았으며 대상 Dart 분석과 네이티브 통합 실행을 수행했다.

캡처 5장은 모두 PNG 2853×2007이며 실제 시뮬레이터의 넓은 viewport다. 전부 직접
열어 빈 화면/누락 렌더링/텍스트·버튼 겹침이 없는지 확인했다.

| 캡처 | 실제 확인 | 판정 |
| --- | --- | --- |
| activity-server-month.png | 2026년 10월 19일 셀 5.0k, 달력 및 범례 표시 | PASS |
| activity-server-day.png | 5,000걸음, 포인트 정책 미준비, claim 버튼 없음 | PASS |
| activity-server-delete-confirm.png | 삭제 영향 문구와 취소/전체 삭제 버튼 분리 표시 | PASS |
| activity-server-deleted.png | 삭제 성공 안내와 걸음/GPS 없음 상태 | PASS |
| activity-server-photo-profile.png | 실제 생성 프로필 활동친구와 퍼그 asset, 선택 전 저장/공유 비활성 | PASS |

증거 디렉터리:
`/Users/beomseok/Library/Developer/CoreSimulator/Devices/06C7AD47-C910-4D53-95C3-C1AD6283311B/data/Containers/Data/Application/BB70426D-45AE-4970-8122-473BD1CF023D/Library/Application Support/activity-qa/`.
이는 시뮬레이터 로컬 산출물이며 앱 삭제 시 제거될 수 있다. 저장소에는 허용된 테스트와
문서만 추가했고 PNG를 추가하지 않았다.

기존 표시 발견: 인증 일별 UI에도 서버 응답의
`development-fixture-v1-not-production` 배지가 표시된다. 보상 상태는 인증 매핑으로
unconfigured이고 claim 버튼은 없으며, 테스트는 claim/quiz/theme fixture API를
호출하지 않았다. 배지 표시는 lib 변경 권한 밖이므로 수정하지 않았다. 따라서 UI의
fixture 표시가 없다는 주장이나 운영 보상 검증으로 해석하면 안 된다.

빌드가 해석한 `pubspec.lock`은 작업 시작 때부터 변경되어 있었고 현재도
balmatchum_client만 Git ref `93435c4cdd53c8b9f802007dccfe4899f8109ead`에서
`../../../server/.worktrees/full-feature-audit/client` path source로 바뀐 차이
(3 insertions, 5 deletions)다. 로컬 pubspec_overrides 조건을 사용했으며
pubspec.yaml/override/lib/unit test를 수정하지 않았다. 부모 변경은 보존했고
commit/push/deploy를 하지 않았다.
