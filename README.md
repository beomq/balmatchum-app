# balmatchum_app

발맞춤 Android/iOS 앱 초기 기반입니다. 앱 이름과 명시적인 서버 연결 확인 버튼을 표시합니다.

로컬 저장소 루트는 `/Users/beomseok/Desktop/프로젝트/Flutter_앱/balmatchum/app`입니다.
공유 기준은 `../DEVELOPMENT.md`, 서버와 디자인은 각각 `../server`, `../design`이며
앱 작업 범위가 아닙니다. GitHub 원격 이름 `balmatchum-app`과 Dart 패키지
`balmatchum_app`, 앱 식별자는 로컬 디렉터리 이름과 별개로 유지합니다.

## 실행과 검증

프로젝트 로컬 SDK는 `.fvmrc`의 Flutter **3.47.5**, 포함된 Dart **3.13.4**입니다.
전역 SDK를 변경하지 않습니다. FVM이 설치된 환경에서 이 디렉터리에서 실행합니다.

```sh
fvm use 3.47.5 --skip-pub-get
fvm flutter pub get --enforce-lockfile
fvm dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug
fvm flutter run -d <device-id>
```

Android 빌드에는 Android SDK 및 JDK 17 이상이 필요합니다. iOS는 macOS/Xcode가
필요하며 서명 없는 시뮬레이터 검증은 `fvm flutter build ios --simulator --debug`로
실행합니다. 실제 기기 서명/스토어 등록은 이 초기화의 범위가 아닙니다.

## 구조와 선택 이유

- `lib/main.dart`: `ProviderScope`와 앱 조립 진입점입니다.
- `lib/app/router.dart`: Riverpod가 `GoRouter`를 만들고 해제합니다.
- `lib/app/dependencies.dart`: 생성 Client를 생성·해제하고 `greeting.hello`를 주입합니다.
- `lib/app/app.dart`: 라우터를 생성자로 받는 앱입니다. 객체 의존성은 생성자로 전달하고,
  Riverpod는 조립과 상태 수명 관리에 사용합니다.
- `lib/features/bootstrap/presentation/bootstrap_screen.dart`: 단일 중립 화면입니다.
- `test/app/app_test.dart`: 실제 앱 조립, 주입된 라우터, `/` 화면 표시를 함께 검증합니다.

feature-first로 기능별 코드를 모읍니다. 아직 도메인 규칙이 없으므로 빈 repository,
service, use case 계층을 만들지 않았습니다. use case는 여러 의존성을 조합하거나
재사용할 도메인 규칙이 생길 때만 도입합니다. 제품 기능, 인증, 위치 SDK는 없습니다.

## 미확정 식별자와 서버 연동

**`com.beomq.balmatchum`은 승인되지 않은 임시 로컬 식별자입니다.** Android namespace,
applicationId, iOS bundle identifier에만 적용했습니다. OAuth/스토어/Firebase 등의
외부 식별자를 등록하지 않았고 개발팀 ID도 저장하지 않습니다. 확정 시 Android Gradle,
MainActivity 패키지, iOS Xcode 설정을 함께 검토해야 합니다.

서버 담당자가 Serverpod **4.0.3**으로 생성하는 `balmatchum_client`가 공식 계약입니다.
Git URL `https://github.com/beomq/balmatchum-server.git`, 불변 ref
`cfd8fd24d7d676841d5fce9dff2911df2c224d3c`, 경로 `client/`를
pubspec과 lockfile에 고정했습니다. 자체 백엔드용 Dio/Retrofit, 수기 DTO는 없습니다.
서버 로컬 구조는 `../server/{server,client}`이며, 위 커밋에서 Git 패키지 경로도
`client/`입니다. 이후에도 리드가 전달한 불변 ref와 경로를 함께 갱신합니다.
화면은 생성 Client 대신 `GreetingCheck` 함수 경계를 생성자로 받습니다. 조립 위치만
Client를 알고 있으므로 위젯 테스트는 네트워크 없이 응답/실패를 주입할 수 있습니다.
Jev TypeSafe는 향후 QA 실험 후보이며 현재 의존성이 아닙니다.

### 명시적 연결 확인

서버 URL은 기본값 없이 `SERVER_URL` 빌드 인자로 전달합니다. URL이 없으면 버튼을
비활성화하며, 앱 시작 시에는 네트워크를 호출하지 않습니다. 버튼을 누를 때만
`greeting.hello('Balmatchum')`을 호출하고 서버의 `Greeting.message`를 표시합니다.
요청 중 중복 실행을 막고 실패하면 재시도 가능한 오류를 표시합니다. 자동 재시도는 없습니다.

이전에 검증한 리드 소유 테스트 서버 API는 `http://127.0.0.1:58099/`입니다.
최종 pin 검증 시 이 주소는 연결 거부 상태였습니다. 아래 명령을 재실행하려면 리드가
제공하는 실행 중인 API URL을 사용해야 합니다. 서버 생성/시작/종료는 앱 작업자가 수행하지 않습니다.

```sh
fvm dart run tool/check_connection.dart http://127.0.0.1:58099/
fvm flutter run -d <ios-simulator-id> --dart-define=SERVER_URL=http://127.0.0.1:58099/
fvm flutter test integration_test/connection_test.dart -d <ios-simulator-id> --dart-define=SERVER_URL=http://127.0.0.1:58099/
fvm flutter drive --driver=test_driver/connection_driver.dart --target=integration_test/connection_test.dart -d <ios-simulator-id> --dart-define=SERVER_URL=http://127.0.0.1:58099/
```

Android emulator는 호스트 별칭 `http://10.0.2.2:58099/`를 사용합니다. 실기기의
`127.0.0.1`은 개발 Mac이 아니므로 접근 가능한 서버 주소를 별도로 전달해야 합니다.
Android의 HTTP 허용은 debug manifest에만 있으며 운영용 HTTP 예외는 없습니다.
이 연결은 로그인/위치/제품 기능이 아닌 개발용 명시적 확인입니다.
`flutter drive`는 테스트가 끝나기 전 성공 화면을 `.qa/connection-success.png`에 보존합니다.
이 실서버 검사는 로컬 opt-in이며, CI의 위젯 테스트는 서버 없이 실행됩니다.

## 브랜치와 PR 정책

최종 승인된 개발 흐름은 **기능 브랜치 → PR → `develop`**입니다. 브랜치는 `feat/<설명>`,
`fix/<설명>`, `chore/<설명>` 형태를 사용하고 개발 PR의 대상은 `develop`으로 지정합니다.
`main`은 릴리스 전용이며 일반 개발 변경을 직접 반영하지 않습니다.

앱에는 아직 최초 커밋이 없습니다. 초기 Git 구성과 기반 브랜치 준비는 리드가 조율하며,
이를 위해 임의의 `main` 커밋이나 릴리스 커밋을 만들지 않습니다. 커밋·푸시·PR 생성은
각각 명시적 승인 후 진행합니다. 이후 서버 클라이언트 ref/path 변경도 리드가 조율합니다.

## CI와 생성 코드

`.github/workflows/ci.yml`은 포맷, analyze, test, Android debug APK 빌드를 실행합니다.
모든 push와 PR에서 실행하며 브랜치 정책 변경 때문에 트리거를 제한하지 않습니다.
공개 저장소 PR에서도 비밀값 없이 실행하며 APK는 배포하지 않습니다.
SDK 버전은 `.fvmrc`에서 읽고, 의존성은 커밋 대상 `pubspec.lock`으로 고정합니다.
현재 앱 소유 Dart 생성 코드가 없으므로 허위 generation check나 build_runner를 넣지
않았습니다. Flutter가 만드는 플랫폼 등록 파일은 SDK 빌드가 관리합니다. 앱에서 실제
생성 코드를 도입하면 해당 생성 명령과 대상 경로의 변경 검사도 CI에 함께 추가합니다.
서버 생성 클라이언트는 서버 저장소의 생성 검사와 고정 revision으로 관리합니다.

## 직접 확인과 장애 확인 순서

앱 시작 시 네트워크 요청은 없어야 합니다. URL을 지정해 실행하고 Check connection을
누르면 `Hello Balmatchum`이 표시되어야 합니다. 자동 QA와 사용자 직접 확인은 별개이고,
사용자 확인은 아직 미완료입니다. 연결 실패 시 서버 실행 여부와 URL, 기기별 호스트 주소를
먼저 확인한 뒤 `tool/check_connection.dart`로 같은 클라이언트의 응답을 확인합니다.
문제가 있으면 `.fvmrc`와 `fvm flutter --version` → `pub get --enforce-lockfile` →
`test/app/app_test.dart` 및 `flutter analyze` → Android SDK/JDK 또는 Xcode 순서로
확인합니다. 실기기·서명·릴리스·운영 서버 연결은 이 기반 검증만으로 보장하지 않습니다.

### 로컬 한글 경로에서의 SDK 분석 문제

Flutter 3.47.5의 `fvm flutter analyze`는 현재 한글 절대 경로에서 분석 서버 초기화 중
`FormatException: Unterminated string`으로 종료 코드 255가 발생했습니다. SDK의
`packages/flutter_tools/lib/src/dart/analysis.dart:157`이 LSP `Content-Length`에
UTF-8 바이트 수 대신 문자열 길이를 사용하는 것이 확인됩니다. SDK를 수정하거나
경고를 숨기지 않았습니다. 같은 프로젝트의 `fvm dart analyze`는 종료 코드 0,
`No issues found!`로 통과했습니다. CI는 ASCII checkout 경로에서 원래의
`fvm flutter analyze`를 유지합니다. GitHub에서의 실제 CI 실행은 아직 미검증입니다.

원격 저장소: https://github.com/beomq/balmatchum-app.git (PUBLIC).
이 초기화는 커밋/푸시/배포를 포함하지 않습니다. 비밀값과 가족 자산을 넣지 않습니다.

공식 문서: [Riverpod ProviderScope](https://riverpod.dev/docs/concepts2/containers),
[go_router 예제](https://pub.dev/packages/go_router/example).
