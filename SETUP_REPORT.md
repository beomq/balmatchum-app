# 앱 초기화 결과

2026-09-26, wc-app. 앱 저장소만 초기화했습니다. 현재 로컬 루트는
`/Users/beomseok/Desktop/프로젝트/Flutter_앱/balmatchum/app`입니다.

이 문서의 아래 초기화 기록은 서버 연동 전 결과입니다. 현재 상태는 이어지는
가장 마지막의 `최종 정책과 서버 pin 갱신` 절을 우선합니다.

## 구현

- FVM 로컬 Flutter 3.47.5 / Dart 3.13.4, Android/iOS `balmatchum_app`.
- Riverpod 3.4.3, go_router 18.0.1. ProviderScope에서 라우터를 조립하고 앱 생성자로
  주입합니다. feature-first 단일 bootstrap 화면이며 제품 기능과 네트워크 연결은 없습니다.
- `.github/workflows/ci.yml`: 잠금 의존성, 포맷, analyze, test, Android debug 빌드.
  앱 소유 Dart 생성 코드가 없어 별도 generation check는 없습니다.
- `README.md`, `AGENTS.md`에 경계, 재현 명령, 서버 연동 대기와 임시 식별자를 명시했습니다.

## 검증 증거

| 명령 | 종료 코드 | 결과 |
| --- | --- | --- |
| `fvm flutter --version` | 0 | Flutter 3.47.5 / Dart 3.13.4 |
| `fvm flutter pub get --enforce-lockfile` | 0 | 잠금 파일로 해결 |
| `fvm dart format --output=none --set-exit-if-changed lib test` | 0 | 5개 파일, 변경 0 |
| `fvm flutter analyze` | 255 | 한글 경로의 SDK LSP 초기화 오류, README에 원인 기록 |
| `fvm dart analyze` | 0 | No issues found! |
| `fvm flutter test` | 0 | 위젯 테스트 1개 통과 |
| `fvm flutter build apk --debug` | 0 | app-debug.apk 생성 |
| `fvm flutter build ios --simulator --debug` | 0 | Runner.app 생성 |
| `plutil -lint ios/Runner/Info.plist ios/Runner.xcodeproj/project.pbxproj` | 0 | 두 설정 정상 |
| `xcrun simctl install …` / `xcrun simctl launch … com.beomq.balmatchum` | 0 | iPhone 17 Pro에서 실행 |

`lib/` 4개 및 `test/` 1개 Dart 파일의 LSP 진단 0건. YAML은 Bun YAML parser로
해석을 확인했습니다. YAML/Kotlin 언어 서버는 설치되지 않아 해당 LSP 검사는 못 했으며,
Android 실제 빌드는 통과했습니다. GitHub Actions의 원격 실행은 푸시 전이라 미검증입니다.

화면 직접 확인: iPhone 17 Pro 시뮬레이터 1206x2622에서 중앙 이름만 표시되고 잘림/겹침이
없습니다. 증거는 Git 제외 경로 `.qa/bootstrap-iphone17pro-ready.png`입니다.
처음 캡처 `.qa/bootstrap-iphone17pro.png`는 실행 전환 장면이므로 판정 근거가 아닙니다.
Android는 연결된 기기가 없어 설치/화면 검증을 하지 않았습니다. 실기기·서명·릴리스 빌드,
사용자 직접 확인은 미검증입니다. 기본 Xcode 테스트 스텁은 실행하지 않았습니다.

## 결과 경로

- Android: `build/app/outputs/flutter-apk/app-debug.apk`
- iOS: `build/ios/iphonesimulator/Runner.app`
- 앱 진입점: `lib/main.dart`
- 라우터 및 생성자 DI: `lib/app/router.dart`, `lib/app/app.dart`
- 화면: `lib/features/bootstrap/presentation/bootstrap_screen.dart`
- 테스트: `test/app/app_test.dart`

## Git 및 대기 사항

- 브랜치 `chore/app-bootstrap`, origin `https://github.com/beomq/balmatchum-app.git`.
- 커밋 0, 스테이징 없음, 푸시/배포 없음. 원격 ref 조회 결과 비어 있음.
- `com.beomq.balmatchum`은 미확정 로컬 식별자입니다. 외부 식별자 등록 없음.
  Flutter 생성기가 넣은 개발팀 설정은 앱 프로젝트에서 제거했습니다.
- Serverpod 4.0.3 생성 `balmatchum_client` 통합은 리드의 불변 서버 revision 대기입니다.
  DTO와 자체 HTTP 계층은 만들지 않았습니다.
- Android 빌드가 필요한 로컬 SDK Build-Tools 36.0.0을 자동 설치했습니다.
  전역 Flutter SDK 선택은 변경하지 않았습니다.
- 기존 walk_companion, 서버, 공유 계약, 다른 pane/session은 수정하거나 중단하지 않았습니다.

장애 확인 순서와 직접 실행 절차는 README를 따릅니다. 사용자 이해/직접 검증은 별도이며
이 자동 검증으로 완료를 대신 선언하지 않습니다.

## 서버 연결 추가 검증

2026-09-26 후속 승인에 따라 생성 클라이언트를 연결했습니다.

- 서버 Git: `https://github.com/beomq/balmatchum-server.git`
- 서버/클라이언트 불변 ref: `c923309b196d6f2d1ed2530a86d9052e574ab7e0`
- 패키지 경로: `balmatchum/balmatchum_client`, 패키지 버전 `0.0.0`
- Serverpod client/serialization: `4.0.3`; 앱 `0.1.0+1`, 아직 미커밋
- 실제 검증 API: `http://127.0.0.1:58099/` (리드 소유 테스트 모드 서버)
- Android emulator 인자: `--dart-define=SERVER_URL=http://10.0.2.2:58099/`

`lib/app/dependencies.dart`가 Client의 생성/해제를 소유하고 `greeting.hello`를
`GreetingCheck` 경계로 화면 생성자에 전달합니다. 앱 시작 시 호출하지 않으며 버튼을
누를 때만 요청합니다. URL 미지정은 버튼 비활성, 진행 중 중복 호출 방지,
실패 후 명시적 재시도를 제공합니다. 서버 DTO는 작성하거나 수정하지 않았습니다.

| 후속 검증 | 종료 코드 | 결과 |
| --- | --- | --- |
| `fvm dart run tool/check_connection.dart http://127.0.0.1:58099/` | 0 | 실제 생성 Greeting 수신 |
| `fvm dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver` | 0 | 11개 파일 변경 0 |
| `fvm flutter test` | 0 | 5개 테스트 통과 |
| `fvm flutter build apk --debug --dart-define=SERVER_URL=http://10.0.2.2:58099/` | 0 | APK 생성 |
| `fvm flutter test integration_test/connection_test.dart -d A2BE61A6-1005-46A7-802E-2114F8794260 --dart-define=SERVER_URL=http://127.0.0.1:58099/` | 0 | 실제 iOS 버튼 → Client → 서버 응답 통과 |
| `fvm flutter analyze --no-pub` | 255 | 기존 SDK 한글 경로 오류 재현 |
| `fvm dart analyze` | 0 | 연동 후 분석 통과 |
| `fvm flutter pub get --enforce-lockfile` | 0 | 불변 Git revision 잠금 검증 |
| `fvm flutter drive --driver=test_driver/connection_driver.dart --target=integration_test/connection_test.dart -d A2BE61A6-1005-46A7-802E-2114F8794260 --dart-define=SERVER_URL=http://127.0.0.1:58099/` | 0 | 실제 응답 재검증 및 성공 화면 캡처 |

CLI에서 확인한 실제 응답:

```text
message: Hello Balmatchum
author: Serverpod
timestamp: 2026-09-26T02:16:19.799186Z
```

위젯 테스트는 주입 경계의 Completer로 시작 시 무요청, 진행 중 중복 방지, 응답 표시,
실패/재시도, URL 미설정, 화면 제거 후 완료를 확인합니다. iOS 통합 테스트는 실제
Client 호출을 유지한 관찰 경계로 시작 시 호출 0회, 버튼 클릭 후 호출 1회와
`Hello Balmatchum`을 확인합니다. 고정 sleep 없이 완료 이벤트와 15초 상한을 사용합니다.

공유 `../DEVELOPMENT.md`를 읽고 앱 소유 파일만 변경했습니다. 서버 세션 시작/종료나
서버 코드 수정은 하지 않았습니다. 커밋/푸시/배포 없음. 임시 식별자는 그대로 미확정입니다.
Android 실제 네트워크/화면, 실기기, 원격 CI, 사용자 직접 확인은 미검증입니다.

화면 증거 `.qa/connection-success.png`를 직접 확인했습니다. 1206x2622 iPhone 17 Pro
화면 중앙에 앱 이름, Check connection 버튼, 실제 `Hello Balmatchum` 응답이 표시되고
겹침/잘림이 없습니다. 초기 테스트 종료 후 simctl 캡처는 홈 화면이어서 폐기 판정했고,
테스트 내부 takeScreenshot으로 확보한 실제 성공 화면을 최종 증거로 사용합니다.
`test_driver/connection_driver.dart`는 해당 스크린샷을 Git 제외 `.qa/`에 저장합니다.
리드의 테스트 서버는 중단하지 않았으며 앱 연결 QA는 완료되어 리드가 정리할 수 있습니다.

## 로컬 디렉터리 이동

사용자 확정 구조에 따라 앱 저장소 전체를 `balmatchum/balmatchum-app`에서
`balmatchum/app`으로 이동했습니다. 새 절대 루트는
`/Users/beomseok/Desktop/프로젝트/Flutter_앱/balmatchum/app`입니다.
README와 AGENTS의 로컬 구조 안내도 갱신했습니다. 부모/서버/디자인 파일은 수정하지 않았습니다.

이동 직전과 직후 1,906개 항목의 상대 경로, inode, 크기, 심볼릭 링크 대상이 모두
일치했습니다. `.git`, 미커밋 파일, `.qa/connection-success.png`, 기존 APK 및
무시된 빌드 데이터를 보존했습니다. 원래 디렉터리는 남아 있지 않습니다.
SDK 연결은 `/Users/beomseok/fvm/versions/3.47.5`를 그대로 가리킵니다.

| 새 루트 검증 | 종료 코드 | 결과 |
| --- | --- | --- |
| `fvm flutter --version` | 0 | Flutter 3.47.5 / Dart 3.13.4 |
| `fvm flutter pub get --enforce-lockfile` | 0 | 기존 잠금 의존성 유효 |
| `fvm dart analyze` | 0 | 통과 |
| `fvm flutter test` | 0 | 5개 통과 |

GitHub 원격 `https://github.com/beomq/balmatchum-app.git`, 브랜치
`chore/app-bootstrap`, Dart 패키지 `balmatchum_app`, 임시 앱 식별자는 유지했습니다.
커밋 0, 스테이징/푸시 없음. 이동을 막는 차단 요인은 없습니다.

서버 새 구조의 불변 커밋은 아직 미수신입니다. 현재 유효한
`c923309b196d6f2d1ed2530a86d9052e574ab7e0` + `balmatchum/balmatchum_client` 쌍을
유지했고, 리드가 새 ref와 `client/` 경로를 전달할 때 함께 변경해야 합니다.
이동 후 빌드 재실행·실서버 재호출은 하지 않았으며 기존 산출물과 검증 기록을 보존했습니다.

## 최종 정책과 서버 pin 갱신

사용자가 기능 브랜치 → PR → `develop`, `main` 릴리스 전용 정책을 최종 승인했습니다.
README/AGENTS에 확정 정책을 반영했으며 CI의 전체 push/PR 트리거는 변경하지 않았습니다.
초기 Git 구성은 리드가 조율합니다. 커밋/푸시/PR 생성은 하지 않았습니다.

서버 Git 의존성과 lockfile을 다음 쌍으로 함께 갱신했습니다.

- URL: `https://github.com/beomq/balmatchum-server.git`
- ref 및 resolved-ref: `cfd8fd24d7d676841d5fce9dff2911df2c224d3c`
- pubspec path: `client/`, lockfile 정규화 path: `client`

| 검증 | 종료 코드 | 결과 |
| --- | --- | --- |
| `fvm flutter pub get` | 0 | Git 의존성 1개 변경 |
| `fvm flutter pub get --enforce-lockfile` | 0 | 새 불변 ref/path 잠금 확인 |
| `fvm flutter analyze --no-pub` | 255 | 기존 한글 경로 SDK JSON 초기화 오류 |
| `fvm dart analyze` | 0 | 통과 |
| `fvm flutter test` | 0 | 5개 통과 |
| `fvm dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver` | 0 | 11개 파일 변경 없음 |
| 이전/새 Git 캐시의 클라이언트 `lib/`에 `diff -rq` | 0 | 생성 API 코드 동일 |
| `fvm dart run tool/check_connection.dart http://127.0.0.1:58099/` | 255 | Connection refused |

앱 `lib/` 6개 파일 LSP 진단은 0건입니다. 생성 코드가 이전 실서버 검증본과 동일함을
확인했지만 이것을 새 서버의 실응답 성공으로 간주하지 않습니다. 기존 서버는 중단된
상태로 추정되며 관찰된 사실은 해당 URL의 연결 거부입니다. 새 pin의 실서버 smoke에는
리드가 실행 중인 API URL을 제공해야 합니다. 앱 담당은 서버를 시작/수정/종료하지 않았습니다.
추가 앱 코드·화면 변경은 없으며 이전 APK와 화면 검증은 이전 pin 기준의 기록입니다.
