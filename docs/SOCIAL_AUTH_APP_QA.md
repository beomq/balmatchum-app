# Google / Apple 앱 인증

## 구현 경계

`signInStarterProvider` → `SocialAuthService` → 설정 확인 → 하위 SDK 자격 증명
→ 생성 `googleIdp` / `appleIdp` endpoint → 기존 `ServerpodAuthSession.save` 순서다.
`saveAuthenticatedSession`을 거쳐 Watch 문맥을 비우고, 자격 증명 저장이 성공한
뒤에만 명시적 로그인 문맥을 활성화한다. Watch 코드는 이 작업에서 수정하지 않았다.

Serverpod 4.0.3의 `GoogleAuthController` / `AppleAuthController`는
`client.auth.updateSignedInUser`를 직접 호출하므로 사용하지 않는다.
Google은 사용자 클릭에서 초기화 Future를 기다린 뒤 `authenticate`를 호출한다.
lightweight 인증, 인증 이벤트를 통한 자동 로그인, 시작 시 SDK 초기화는 없다.
초기화 실패 Future는 버려 다음 사용자 클릭에서 다시 시도할 수 있다.

버튼은 기존 `social_signin_kit` 구성 그대로다. Kakao 위임과 dev 라우팅은 그대로이며,
Naver는 `configurationMissing`이다. 취소, 네트워크, SDK, 서버, 세션 저장 실패를
별도 결과로 반환하고 예외 본문이나 토큰을 로그에 남기지 않는다. Google 7.2.0의
`GoogleSignInExceptionCode`에는 network 전용 코드가 없으므로 알려지지 않은
SDK 오류는 임의로 취소/네트워크로 추정하지 않고 `sdkError`로 처리한다.

## 실제 설정

공통 Dart define:

- `SERVER_URL`: 생성 endpoint가 있는 서버의 base URL.
- `GOOGLE_SERVER_CLIENT_ID`: Google 웹 OAuth client ID, 서버 audience와 일치.
- `GOOGLE_CLIENT_ID`: iOS OAuth client ID. iOS에서 필수, Android에서는 사용하지 않음.
- `APPLE_SIGN_IN_ENABLED=true`: Apple 외부 등록·서버 설정 준비 후에만 설정.
- `APPLE_SERVICE_IDENTIFIER`: Android Apple 서비스 ID.
- `APPLE_REDIRECT_URI`: Android Apple HTTPS callback URL.

iOS Google은 실제 iOS client ID를 역순으로 만든 URL scheme을
`ios/Runner/Info.plist`의 `CFBundleURLTypes` → `CFBundleURLSchemes`에 추가해야 한다.
네이티브 `googleCallbackConfigured` 채널이 설치된 앱 plist에 이 scheme이
있는지 확인하며, 없으면 Google SDK 초기화조차 하지 않는다. 저장소 plist에는
가짜 ID, 빈 OAuth placeholder, 미확정 callback scheme을 추가하지 않았다.
`GIDClientID` / `GIDServerClientID`는 Dart에서 전달하므로 plist에 중복할 필요 없다.

iOS Apple은 `Runner/Runner.entitlements`의 `com.apple.developer.applesignin=Default`
를 일반 Debug/Profile/Release에 연결했다. 외부 App ID에서 Sign in with Apple을
켜고 일치하는 bundle ID와 유효한 provisioning profile / 팀 서명이 필요하다.
dev 빌드의 인증 우회와 entitlement는 변경하지 않았다.

Android Google은 Google Cloud에 실제 application ID와 debug/release SHA 인증서를
등록하고 동일 프로젝트의 웹 client ID를 전달해야 한다. 이 경로는
`google-services.json`을 사용하지 않아도 된다. Apple callback activity는 추가했으며
실제 HTTPS callback 서버가 Apple form POST를 안전하게 처리하고
`intent://callback?...#Intent;package=<실제 application ID>;scheme=signinwithapple;end`
형식으로 반환해야 한다. package와 callback은 외부 Apple 설정과 일치해야 한다.

서버 생성 계약을 직접 확인했다:

- `client.googleIdp.isConfigured()` / `client.appleIdp.isConfigured()`.
- Google `login(idToken: ..., accessToken: null)`.
- Apple `login(identityToken: ..., authorizationCode: ...,
  isNativeApplePlatformSignIn: iOS 여부, firstName: ..., lastName: ...)`.
- 반환 `AuthSuccess`만 세션 저장 대상으로 사용한다.

서버 사전 확인이 false이면 SDK 호출을 하지 않는다. 서버는 `googleClientSecret`
및 Apple `appleServiceIdentifier`, `appleBundleIdentifier`, `appleRedirectUri`,
`appleTeamId`, `appleKeyId`, `appleKey`와 서버 세션 설정이 필요하다.
Android는 서버의 `appleAndroidPackageIdentifier`도 필요하다. 비밀값은 앱에 넣지 않는다.

로컬 QA는 리드가 만든 `pubspec_overrides.yaml`의 생성 client 경로를 사용했다.
pubspec의 기존 Git ref는 변경하지 않았다. 출하 전 리드가 새 생성 endpoint를
포함한 서버 불변 ref를 승인·고정하고 override를 제거해야 한다.

## 검증과 직접 확인

- `fvm flutter test --no-pub test/features/auth`: 최종 54개 통과, 종료 0.
  서버 preflight 이후 설정 소실 `LoginException` 회귀를 마지막에 추가했다.
- `fvm flutter test --no-pub`: 225개 통과, 종료 0.
- `fvm dart analyze lib/features/auth test/features/auth lib/app/dependencies.dart integration_test/social_auth_unconfigured_test.dart`: 문제 없음, 종료 0.
- `fvm flutter analyze`: 분석 서버 초기 JSON 처리 `FormatException: Unterminated string`,
  종료 255. ASCII symlink 작업 경로도 동일. 위 FVM Dart 분석은 통과했다.
- `plutil -lint`로 entitlement, Info.plist, pbxproj 문법 통과.
- `fvm flutter build apk --debug --flavor prod --no-pub`: 종료 0,
  `build/app/outputs/flutter-apk/app-prod-debug.apk` 생성. 최초 flavor 미지정 실행은
  Gradle 완료 후 Flutter의 APK 경로 탐색이 실패했으며 prod 지정으로 해결했다.
- `fvm flutter test --no-pub integration_test/social_auth_unconfigured_test.dart -d 06C7AD47-C910-4D53-95C3-C1AD6283311B`:
  iOS 네이티브 Xcode 빌드 44.6초 완료, 실화면 버튼 테스트 1개 통과, 종료 0.
  Google/Apple/Naver 설정 누락에서 로그인 화면 유지·미인증·재클릭 가능 및
  Kakao 기존 미연결 상태를 확인했다.
- 네이티브 빌드에서 GoogleSignIn iOS 9.2.0을 포함하는 Swift Package.resolved가
  두 Xcode workspace 경로에 생성되었다. 기존 미추적 `ios/Runner.xcodeproj/-Xcc/`
  는 이 작업에서 생성하거나 수정하지 않았다.

`social_auth_test.dart`는 두 제공자의 성공/취소/서버 실패/저장 실패, 설정 누락,
중복 클릭, Google 초기화 대기와 실제 `ServerpodAuthSession` + Watch 서비스의
clear → persist → activate 순서를 검증한다. 저장 실패 시 인증 상태와 Watch가
활성화되지 않는다. 고정 sleep이나 타이밍 기반 성공 조건은 없다.

직접 확인: OAuth define 없이 일반 앱 실행 → Google/Apple/Naver 버튼 각각 클릭 →
설정 미준비 상태가 표시되고 로그인 화면에 머물러야 한다. Kakao는 기존 미연결
결과다. 설정 후 실패하면 Dart define → iOS URL scheme / entitlement 또는 Android
등록 인증서 → 서버 `isConfigured` → 로그인 서버 결과 → 기기 저장 순서로 확인한다.
실제 공급자 계정 OAuth 성공은 자격 증명 없이 검증하지 않았다.

서버 증분 `f64f5945`의 `docs/SOCIAL_AUTH_API.md`와 계약을 대조했다.
현재 서버에는 Apple Android/web callback route가 없으므로 Android Apple은
외부 HTTPS callback을 구현·등록·검증하기 전에는 활성화하지 않는다.
`APPLE_SIGN_IN_ENABLED`만 켜서는 Android SDK에 진입하지 않고 서비스 ID와
HTTPS redirect도 모두 필요하지만, URL 존재 여부만으로 callback 동작을 보장하지 않는다.
서버 4.0.3 Apple의 nonce 검증 및 재연결 refresh token 갱신 제한도 그대로이며
전체 Apple 운영 준비 완료를 의미하지 않는다. 상세 제한은 서버 문서를 따른다.

스크린샷 보존 명령:
`fvm flutter drive --no-pub --driver=test_driver/social_auth_driver.dart --target=integration_test/social_auth_unconfigured_test.dart -d 06C7AD47-C910-4D53-95C3-C1AD6283311B`.
종료 0. `/tmp/bm-auth/auth-screenshots/auth-google-unconfigured.png`,
`auth-apple-unconfigured.png`, `auth-naver-unconfigured.png` 세 실화면을 직접 열어
네 버튼·설정 미준비 안내가 잘리지 않고 표시됨을 확인했다.
이 캡처는 시뮬레이터의 가로 2853×2007 물리 픽셀 화면이며 세로 실기기 OAuth나
다크 모드 화면 검증을 대신하지 않는다. 기존 320×480 큰 글자 위젯 회귀는 통과했다.
별도 시각 검토자 두 명의 실행은 하네스의 하위 작업 중첩 한도(depth 1)로 거부되었다.
위 화면 평가는 구현자의 직접 확인이며 독립 리뷰 완료로 표시하지 않는다.

## 근거

- https://github.com/serverpod/serverpod_docs/blob/main/versioned_docs/version-4.0.0/06-concepts/04-authentication/02-setup.md
- 로컬 `serverpod_auth_idp_flutter-4.0.3` controller/service 소스 및
  `serverpod_auth_idp_client-4.0.3` endpoint 계약.
- https://pub.dev/packages/google_sign_in/versions/7.2.0
- https://pub.dev/packages/google_sign_in_ios/versions/6.3.8
- https://pub.dev/packages/sign_in_with_apple/versions/8.2.0
