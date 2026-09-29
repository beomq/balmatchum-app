# 신규 팀원 온보딩

## 준비

Git, FVM 4.0.1(CI와 같은 버전), Android Studio/Android SDK 및 JDK 17을 준비합니다.
iOS 빌드는 macOS와 Xcode가 필요합니다. FVM 설치는
[공식 안내](https://fvm.app/documentation/getting-started/installation)를 따릅니다.
이미 FVM이 있으면 전역 Flutter 버전을 바꾸지 않습니다.

아래는 새 clone 기준입니다. 한글 경로의 알려진 분석 문제를 피하려면 ASCII 이름의
상위 경로를 선택하세요. 기존 작업 디렉터리에는 clone 명령을 다시 실행하지 않습니다.

```sh
git clone --branch develop https://github.com/beomq/balmatchum-app.git balmatchum-app
cd balmatchum-app
fvm --version
fvm use 3.47.5 --skip-pub-get
fvm flutter --version
fvm flutter doctor -v
fvm flutter pub get --enforce-lockfile
```

Flutter 3.47.5 / Dart 3.13.4가 나와야 합니다. 첫 실행은 SDK·패키지 다운로드에
네트워크가 필요합니다. `pub get`은 서버 저장소의 생성 클라이언트를 Git에서 받으므로
형제 서버 checkout이나 부모 `DEVELOPMENT.md`가 필요하지 않습니다. 잠금 설치 실패를
`pub upgrade`나 lockfile 삭제로 우회하지 말고 pubspec/ref와 오류를 담당자에게 전달합니다.

## 기본 QA와 실행

저장소 루트에서 실행합니다. 기본 테스트·빌드는 실행 중인 서버나 비밀값이 필요 없습니다.

```sh
fvm dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug --flavor dev
fvm flutter devices
```

Android 기기를 선택한 뒤 `fvm flutter run --flavor dev -d "기기-ID"`로 실행합니다.
iOS는 flavor 없이 기존 `fvm flutter run -d "기기-ID"`를 사용합니다. `SERVER_URL`을 지정하지
않으면 연결 버튼이 비활성화되는 것이 정상입니다. [서버 연결 예제](ENVIRONMENT.md)를
따르면 명시적 버튼 동작까지 확인할 수 있습니다.

macOS의 iOS 컴파일 확인:

```sh
fvm flutter build ios --simulator --debug
```

산출물은 `build/app/outputs/flutter-apk/app-dev-debug.apk`,
`build/ios/iphonesimulator/Runner.app`입니다. debug APK는 배포용 릴리스가 아닙니다.
실기기 서명·스토어 등록은 이 절차에 포함되지 않습니다.
Android Dev 서명 AAB는 [전용 빌드 안내](ANDROID_DEV.md)를 따릅니다.

## 알려진 분석 제한과 장애 확인 순서

한글 절대 경로에서 `fvm flutter analyze`가 `FormatException: Unterminated string`,
종료 코드 255로 실패한 기록이 있습니다. Flutter 3.47.5 SDK의
`packages/flutter_tools/lib/src/dart/analysis.dart:157`에서 LSP Content-Length를
UTF-8 바이트 수가 아닌 문자열 길이로 계산하는 코드가 확인됐습니다.

이 경우 `fvm dart analyze`로 보완 검사하고 **두 명령의 결과를 모두** 보고합니다.
보완 분석 통과를 원래 명령 통과로 적지 않습니다. SDK 패치·버전 변경·경고 억제는
하지 않습니다. CI의 `fvm flutter analyze`도 그대로 유지합니다.

장애는 SDK 버전 → 잠금 의존성 → 분석/테스트 → Android SDK/JDK 또는 Xcode →
기기별 서버 URL 순으로 확인합니다. [팀 리뷰 체크리스트](TEAM.md)를 사용해 명령,
종료 코드, 기기, 실패 원인과 미검증 범위를 PR에 남깁니다.

## 근거

- 저장소: `.fvmrc`, `pubspec.yaml`, `.github/workflows/ci.yml`, `test/`.
- CLI: `fvm flutter run --help`, `fvm flutter pub get --help`.
- [Flutter 설치](https://docs.flutter.dev/install),
  [pub get와 lockfile](https://dart.dev/tools/pub/cmd/pub-get).
