# 인증 프로필 앱 검증

## 범위와 선택

`ServerpodProfileRepository`는 생성 client.profile만 호출한다. 인증 계정 provider가
계정별 파일 저장소와 FirstMeetingController를 조립한다. Dev 컨트롤러는 별도 기기
파일과 기존 클릭 모드를 유지한다. 프로필 firstMetAt과 revision은 서버에서만 가져온다.
생성/설정 요청은 ID·원본 payload·expectedRevision을 계정 파일에 먼저 기록한다.
응답 유실은 같은 요청을 재전송하며, 완료 후 getProfile로 최신 값을 읽는다.
staleRevision은 최신 값을 표시하고 자동 덮어쓰기 없이 사용자 재저장을 요구한다.
컨트롤러 폐기 또는 계정 변경 뒤의 비동기 결과는 화면에 게시하지 않는다.

프로필 삭제는 구현하지 않았다. production 프로필 화면에 개발 ProductController나
보상/가격 fixture를 연결하지 않았다. 기존 auth adapter의 logout 결과 중 localCleared를
기준으로 종료하며, 서버 revoke와 SDK logout의 성공은 별개다.

## 로컬 생성 클라이언트 차단 요인

검증 client: 서버 `2af799131d67b4cf1f88a8ca940f6b4497990259`, 경로 `client/`.
아직 원격에 없는 커밋이므로 pubspec의 공개 Git 핀은 변경하지 않았다.
untracked `pubspec_overrides.yaml`만 해당 sibling client로 연결한다. 이 override 및
path source로 해석된 lockfile은 커밋하면 안 된다. 서버 커밋 푸시 후 승인된 ref/path로
pubspec과 lockfile을 함께 갱신하고 clean checkout에서 pub get/검증해야 한다.
현재 공개 핀만으로 새 profile 타입을 컴파일할 수 없으며 릴리스 준비 완료가 아니다.
검증으로 생긴 path lock 변경은 원래 Git 잠금으로 복원했다. 로컬 pub get 재실행은
다시 path 잠금을 만들므로 해당 diff를 게시하지 않아야 한다.

## 재현 명령

아래 명령은 지정 앱 워크트리에서 실행한다. 최초 셸에서 작업 전용 디렉터리를 만든다.

```sh
RUN_TMP=$(mktemp -d /tmp/profile-lifecycle.XXXXXX)
export TMPDIR="$RUN_TMP" NODE_COMPILE_CACHE="$RUN_TMP/node" BUN_RUNTIME_TRANSPILER_CACHE_PATH="$RUN_TMP/bun"
fvm flutter pub get
fvm flutter test
fvm flutter analyze
fvm dart analyze
fvm flutter drive --driver=test_driver/first_meeting_driver.dart --target=integration_test/profile_settings_test.dart --flavor dev -d 06C7AD47-C910-4D53-95C3-C1AD6283311B
git diff --check
```

테스트는 고정 sleep 없이 Completer로 요청 시작·응답을 제어한다. 도메인 테스트는
응답 유실/재시작/동일 ID·payload, 최신 서버 복원, A/B 초안 격리, 늦은 조회·변경,
revision 충돌과 재확인 후 새 ID, 잘못된 입력을 확인한다. 위젯 테스트는 320/390/768
폭에서 설정 변경·실패·재시도·로그아웃 콜백을 검증한다. 네이티브 테스트는 repository
주입 seam의 UI QA이며 실서버 HTTP/OAuth 검증이 아니다. 캡처는 `.qa/profile-native-*.png`.

직접 확인: 인증 계정으로 로그인 → 첫 만남 완료 → 재시작 후 같은 친구 확인 → 홈 설정에서
이름/목표 변경 → 연결 실패 시 입력·재시도 유지 → 로그아웃 후 B로 로그인해 A의 친구나
입력이 보이지 않는지 확인한다. 다른 기기에서 수정한 후 저장하면 최신 값과 충돌 안내를
확인하고 변경을 검토한 뒤 다시 저장한다. 사용자 직접 검증/이해는 아직 미확인이다.

장애 확인 순서: 인증 계정과 헤더 → getProfile/revision → 계정 파일의 pendingMutation
ID/payload → 생성 클라이언트 핀 → 서버 migration. 응답 유실 시 pending 요청을 임의로
삭제하거나 새로운 ID로 대체하지 않는다.

## 2026-10-17 실행 결과

- 작업 RUN_TMP: `/tmp/profile-lifecycle.MgVWDU`. 모든 명령에 TMPDIR,
  NODE_COMPILE_CACHE, BUN_RUNTIME_TRANSPILER_CACHE_PATH를 export했다.
- `fvm flutter pub get`: exit 0. 처음 override 상대 경로 오류(exit 66)는 수정했다.
- `fvm flutter test`: 전체 192 tests pass, exit 0. 기존 파일 저장소 테스트 포함.
- `fvm flutter analyze`: exit 255. 한글 경로의 분석 서버 통신이
  `FormatException: Unterminated string`으로 종료했다. 이를 성공으로 간주하지 않는다.
- `fvm dart analyze`: No issues found, exit 0 (Flutter analyze 대체 근거).
- `fvm flutter drive --driver=test_driver/first_meeting_driver.dart --target=integration_test/profile_settings_test.dart --flavor dev -d 06C7AD47-C910-4D53-95C3-C1AD6283311B`:
  Xcode build 및 테스트 exit 0. 실제 iPhone Duo 부팅 시뮬레이터에서 네이티브 UI 실행.
- `.qa/profile-native-home.png`, settings/retry/saved 총 4개 캡처를 열어 확인했다.
  기존 픽셀 아트·테마가 유지되고 입력·버튼·오류·로그아웃 겹침 없이 표시된다.
  네이티브 캡처는 현재 시뮬레이터 넓은 viewport이며 폰 폭은 위젯 320/390/768 검증이다.
- 실서버 인증 HTTP, 실제 OAuth 로그인, 다중 물리 기기, 다크모드/큰 글자 전체 행렬,
  Android 빌드는 이번 실행에서 검증하지 않았다. 공개 Git pin 문제도 위와 같이 남는다.
- 부모가 남긴 파일 저장소/테스트 변경은 보존했으며 commit/push/merge/deploy는 하지 않았다.

## 실제 서버 통합 검증

서버 `a23ac2a72a1ccae53b686619edc2297322fa4d24`의 격리 PostgreSQL 하네스가
발급한 세션을 개발 앱에 전달하고 아래 명령을 실행했다.

```sh
fvm flutter test integration_test/profile_server_test.dart --flavor dev -d 06C7AD47-C910-4D53-95C3-C1AD6283311B --no-uninstall --dart-define=SERVER_URL=http://localhost:18080/
```

결과는 `All tests passed!`, exit 0이다. 실제 인증·HTTP·계정 파일을 사용해
프로필 생성, 설정 UI 이름/목표 변경, 컨트롤러 재생성 후 복원, 서버 값 일치와
최초 만남 날짜 보존을 확인했다. OAuth 제공자 로그인과 앱 프로세스 종료 후
재시작 검증은 이 테스트에 포함하지 않았다. 로컬 client override 조건도 유지된다.
네이티브 빌드는 시뮬레이터 ID를 명시한 `fvm flutter build ios --simulator
--debug --flavor dev -d ... --target integration_test/profile_server_test.dart
--dart-define=SERVER_URL=http://localhost:18080/`로 exit 0을 확인했다.

이어 `account_delete_server_test.dart`를 같은 `flutter test --no-uninstall`
옵션으로 실행하여 `All tests passed!`, exit 0을 확인했다. 이전 프로세스가
저장한 실제 인증 세션과 프로필을 복원하고, 탈퇴 확인창 취소 후 실제 삭제
서비스를 호출해 서버 인증 상태 false, 앱 인증 null, 계정 프로필 파일 삭제를
확인했다. UI 확정 버튼과 처리 중 입력 차단은 별도 위젯 테스트에서 검증했다.
삭제 응답 유실 후 앱 재시작 복구와 Kakao 외부 unlink는 아직 검증 범위 밖이다.

최신 탈퇴 확인창은 `profile_settings_test.dart`의 네이티브 drive 실행으로
표시·확정 콜백을 검증했고 exit 0이었다. `.qa/profile-native-delete-confirm.png`를
직접 열어 문구와 취소/삭제 버튼이 겹치지 않는 것을 확인했다.
재개 상태 파일과 로그인 결과 안내 추가 후 전체197 테스트, Dart 분석,
페이저 없는 `git diff --check`가 exit 0으로 통과했다. 별도 인스턴스에서
서버 삭제를 반복하지 않고 정리하는 테스트를 포함한다. 실제 프로세스 종료를
주입한 재개 검증은 아직 실행하지 않았다.

후속 검증에서 `deletion_restart_test.dart`를 두 개의 별도 네이티브 테스트
프로세스로 실행했고 양쪽 모두 exit 0이었다. 첫 실행은 실제 서버 계정을
삭제하고 `deleted` 진행 파일·로컬 프로필·폐기된 세션을 남겼다. 두 번째
실행은 `--no-uninstall`로 이를 보존해 앱 시작 경로의
`resumePendingDeletion`을 호출했고, 인증 null·프로필 파일 없음·진행 파일
없음을 확인했다. 첫 실행에만 `--dart-define=PREPARE_DELETION=true`를 전달했다.
따라서 위의 프로세스 간 복구 미실행 항목은 이 후속 결과로 해소됐다.
