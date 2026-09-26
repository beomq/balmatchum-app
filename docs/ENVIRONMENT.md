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
fvm flutter run -d "$DEVICE_ID" --dart-define=SERVER_URL="$SERVER_URL"
```

실기기의 localhost는 개발 Mac이 아닙니다. 실기기에서 접근 가능한 별도 API URL이
필요합니다. URL은 스킴과 마지막 `/`를 포함하고 환경별 올바른 호스트를 사용합니다.
설정 변경 후에는 기존 실행을 끝내고 새 인자로 다시 빌드/실행하세요.
Android HTTP 허용은 `android/app/src/debug/AndroidManifest.xml`에만 있습니다.
운영 HTTP 예외나 환경별 flavor는 구성하지 않았습니다.

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

현재 CI는 secret 없이 잠금 설치·포맷·분석·위젯 테스트·debug APK 빌드를 합니다.
서버 URL도 넘기지 않습니다. 앞으로 공개 URL을 CI 변수로 전달하는 것과 서명/배포용
자격 증명을 secret으로 관리하는 것은 별도 설계입니다. 후자는 승인된 필요가 생길 때만
권한과 노출 범위를 정하고, 공개 PR에 비밀을 제공하지 않습니다. 현재 secrets 등록,
서명/배포 구성은 하지 않습니다. 로그·스크린샷에도 토큰과 개인 자료를 넣지 않습니다.

근거: [Flutter의 앱 내 비밀값·난독화 한계](https://docs.flutter.dev/deployment/obfuscate),
`lib/app/dependencies.dart`, `tool/check_connection.dart`, `integration_test/connection_test.dart`.
