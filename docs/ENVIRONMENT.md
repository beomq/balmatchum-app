# 앱 환경 설정과 서버 연결

현재 앱 설정은 `lib/app/dependencies.dart`의
`const String.fromEnvironment('SERVER_URL')` 한 가지입니다. 기본값은 빈 문자열이며
URL 미지정 시 Client를 만들지 않고 연결 버튼을 비활성화합니다. 설정된 경우도 앱 시작에
요청하지 않고 버튼에서만 `greeting.hello('Balmatchum')`을 호출합니다.

## 개발 기기별 예제

서버 담당자로부터 **실행 중인 API URL과 서버 revision**을 받으세요. 아래 58099는
과거 QA 포트 예시이며 상시 실행되는 서비스가 아닙니다. 앱 작업자는 다른 담당자의
서버를 시작/종료하거나 설정을 바꾸지 않습니다. `fvm flutter devices`에서 얻은 실제
ID를 변수에 넣습니다. 이 예제는 shell의 일반 환경변수를 앱이 직접 읽는 방식이 아니라
`--dart-define`으로 컴파일 설정을 전달하는 방식입니다.

iOS simulator에서 같은 Mac의 서버:

```sh
DEVICE_ID='여기에-iOS-simulator-ID'
SERVER_URL='http://127.0.0.1:58099/'
fvm flutter run -d "$DEVICE_ID" --dart-define=SERVER_URL="$SERVER_URL"
```

Android Studio emulator에서 개발 호스트의 서버:

```sh
DEVICE_ID='여기에-Android-emulator-ID'
SERVER_URL='http://10.0.2.2:58099/'
fvm flutter run --flavor dev -d "$DEVICE_ID" --dart-define=SERVER_URL="$SERVER_URL"
```

실기기의 localhost는 개발 Mac이 아닙니다. 실기기에서 접근 가능한 별도 API URL이
필요합니다. URL은 스킴과 마지막 `/`를 포함하고 환경별 올바른 호스트를 사용합니다.
설정 변경 후에는 기존 실행을 끝내고 새 인자로 다시 빌드/실행하세요.
Android HTTP 허용은 `android/app/src/debug/AndroidManifest.xml`에만 있습니다.
운영 HTTP 예외는 없습니다. Android dev/prod flavor와 Dev 서명은
[Android Dev 안내](ANDROID_DEV.md)를 따릅니다. iOS는 Runner(Prod)와 dev scheme을 사용합니다.

개발 호스트에서 생성 Client smoke:

```sh
fvm dart run tool/check_connection.dart http://127.0.0.1:58099/
```

iOS 실제 앱 연결 QA와 스크린샷(서버가 실행 중인 경우에만):

```sh
DEVICE_ID='여기에-iOS-simulator-ID'
SERVER_URL='http://127.0.0.1:58099/'
fvm flutter test integration_test/connection_test.dart -d "$DEVICE_ID" --dart-define=SERVER_URL="$SERVER_URL"
fvm flutter drive --driver=test_driver/connection_driver.dart --target=integration_test/connection_test.dart -d "$DEVICE_ID" --dart-define=SERVER_URL="$SERVER_URL"
```

예상 응답은 `Hello Balmatchum`입니다. drive 캡처는 Git 제외 `.qa/connection-success.png`에
저장됩니다. 호스트 CLI 성공과 실기기 성공을 구분해서 기록합니다.

## 공개 설정과 비밀값

`--dart-define`으로 컴파일한 값은 앱에서 추출 가능하다고 취급합니다. `SERVER_URL`은
공개 설정이지 인증 수단이 아닙니다. `.env`, define 파일, 난독화, CI secret을 거쳐 넣어도
앱 바이너리에 포함한 값이 비밀이 되지는 않습니다. 비밀번호, DB 자격 증명, 서버 키,
서비스 계정·서명용 private key를 Dart 코드·asset·define에 넣지 않습니다.
서버 비밀은 서버 측에서 관리하며 현재 앱은 인증/비밀 저장 기능을 구현하지 않았습니다.

PR·push CI(`ci.yml`, `apple-ci.yml`)는 운영 설정 없이 잠금 설치·포맷·분석·테스트·debug
APK·unsigned iOS 컴파일을 합니다. 운영 릴리스 빌드만 아래 공개 저장소 변수(Repository
variables, secret 아님)를 받습니다. 서명 자격 증명은 기존처럼 secret으로 따로 관리하며
로그·스크린샷에도 토큰과 개인 자료를 넣지 않습니다.

## 운영 릴리스 설정

`tool/release_app_config.sh ios|android OUT.json`이 유일한 입력 지점입니다. 환경 변수를
검사해 하나라도 없거나 형식이 틀리면 빌드 전에 실패하고, 통과하면 `--dart-define-from-file`용
JSON을 씁니다. 네이티브 값은 같은 JSON에서 파생합니다.

- Android: Gradle이 Flutter의 `dart-defines`를 해석해 Kakao `AuthCodeHandlerActivity`의
  `kakao{키}://oauth` 스킴을 manifest에 넣습니다. `prodRelease`는
  `validateProdReleaseAppConfig`에서 `SERVER_URL`·Kakao·Google 서버 클라이언트가 없으면
  실패합니다. `tool/verify_android_bundle.sh`는 prod AAB의 Kakao 스킴도 검사합니다.
- iOS: fastlane prod archive가 JSON에서 `KAKAO_URL_SCHEME`, `GOOGLE_REVERSED_CLIENT_ID`
  빌드 설정을 넘겨 `Info.plist`의 `CFBundleURLTypes`를 채우고, `Generated.xcconfig`의
  `DART_DEFINES`와 archive plist를 다시 대조합니다(`tool/apple/app_config.rb`).
  설정이 없는 빌드는 `*.kakao-unconfigured`, `*.google-unconfigured` 자리표시 스킴을 쓰며
  앱은 해당 로그인을 숨깁니다.
- Apple 로그인은 iOS에서만 켭니다(entitlement만 필요). Android는 `APPLE_*`를 넘기지 않아
  숨겨집니다. Naver는 서버 경유라 앱 값이 없습니다.
- Dev 빌드(`deploy-dev.yml`, Apple dev target, `apple-ci.yml`)는 이번 변경에서 운영 설정을
  받지 않으며 동작이 그대로입니다.

| 저장소 변수 | 필수 | 형식 예 | 받는 곳 |
|---|---|---|---|
| `SERVER_URL_PROD` | iOS·Android | `https://balmatchum-prod.api.serverpod.space/` (https, 끝 `/`) | Serverpod Cloud 운영 API URL |
| `KAKAO_NATIVE_APP_KEY_PROD` | iOS·Android | 소문자 hex 32자 | Kakao Developers > 앱 > 플랫폼 키 > 네이티브 앱 키 |
| `GOOGLE_SERVER_CLIENT_ID_PROD` | iOS·Android | `718306004190-<id>.apps.googleusercontent.com` | Google Cloud Console > API 및 서비스 > 사용자 인증 정보 > 웹 애플리케이션 클라이언트 |
| `GOOGLE_IOS_CLIENT_ID_PROD` | iOS | 같은 프로젝트 번호의 iOS 클라이언트 ID | 같은 화면에서 iOS 유형, 번들 ID `com.beomq.balmatchum`으로 생성 |

Google iOS 클라이언트는 웹 클라이언트와 같은 Cloud 프로젝트여야 ID 토큰 대상이 서버
클라이언트로 발급되므로 스크립트가 프로젝트 번호 일치를 검사합니다. 아직 만들지 않았다면
iOS prod archive는 이 변수 누락으로 실패합니다. Android OAuth 클라이언트(패키지
`com.beomq.balmatchum` + Play 앱 서명 SHA-1과 업로드 키 SHA-1)는 앱 값이 없고 콘솔에서만
등록하며, 없으면 Google 로그인이 런타임에 `configurationMissing`으로 실패합니다.
Kakao 콘솔에는 Android 패키지·키 해시와 iOS 번들 ID가 등록되어 있어야 합니다.

로컬에서 운영 값으로 빌드하려면 같은 변수 이름(접미사 `_PROD` 없이)을 환경에 넣고 JSON을
생성해 전달합니다. iOS 네이티브 스킴까지 확인하려면 xcodebuild에 두 빌드 설정을 직접
넘기거나 fastlane prod 경로를 사용합니다.

```sh
SERVER_URL=... KAKAO_NATIVE_APP_KEY=... GOOGLE_SERVER_CLIENT_ID=... \
  bash tool/release_app_config.sh android /tmp/app-config.json
fvm flutter build appbundle --release --flavor prod --dart-define-from-file=/tmp/app-config.json
```

근거: [Flutter의 앱 내 비밀값·난독화 한계](https://docs.flutter.dev/deployment/obfuscate),
`lib/app/dependencies.dart`, `tool/check_connection.dart`, `integration_test/connection_test.dart`.
