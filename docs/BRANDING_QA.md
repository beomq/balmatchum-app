# 네이티브 아이콘과 시작 화면 검증 — 2026-09-28

## 구현 원칙

- Prod 원본: `AppIcons (5)`, `balmatchum_splash.png`.
- Dev 원본: `AppIcons_dev`, `balmatchum_dev_splash.png`.
- Downloads 원본을 변경하지 않고 앱 내부 자산을 사용한다.
- 배경은 제공된 launcher 아이콘의 모서리에서 측정한 `#FFF4E3`다.
- Prod splash는 실제 투명 PNG다. Dev splash는 외곽이 불투명 근검정이므로
  가장자리와 연결된 max(R,G,B)<45 픽셀만 투명화했다. 내부 어두운 윤곽은 유지했다.
  Dev의 하단 표기는 자르지 않았다. 원본의 거친 경계를 임의로 다시 그리지는 않았다.

## Android

- `main/res`는 Prod, `dev/res`는 동일 이름의 Dev 자산으로 override한다.
- API 26 이상 adaptive launcher는 크림 배경과 제공 foreground를 사용한다.
- Android 12 미만은 중앙 bitmap launch background이며 가로세로 비율을 유지한다.
- Android 12 이상은 별도 system splash icon을 사용한다. 1152px 캔버스에
  640px 전체 이미지를 중앙 배치해 원형 마스크 안전 영역을 확보했다.
- `MainActivity`는 API 31 이상에서 공식 exit listener의 `remove()`로 앱 제어
  종료 전환만 제거한다. 지연 시간, 별도 Flutter splash, 중복 Activity는 추가하지 않았다.
- 런처에서 창으로 확대되는 시스템 전환은 OS/런처 제어이며 모든 기기에서 제거할 수 없다.
  `windowSplashScreenAnimationDuration=0`으로 해결됐다고 주장하지 않는다.
- `am start -n`만 사용하면 Android가 아이콘을 생략하는 경우를 확인했다.
  MAIN/LAUNCHER intent와 실제 런처 아이콘 탭도 별도로 녹화했다.

공식 근거:
- https://developer.android.com/develop/ui/views/launch/splash-screen
- https://developer.android.com/develop/ui/views/launch/splash-screen/migrate

공식 문서의 배경 없는 아이콘 규격은 288dp 캔버스와 192dp 원형 안전 영역이다.
단순 XML 크기만 줄였을 때 OS가 확대하여 Dev 표기를 잘라내는 것을 재현했고,
실제 PNG 여백을 적용한 후 전체 표기가 보이는 것을 확인했다.

## iOS 구성

- 기존 `Runner` scheme과 Debug/Release/Profile은 Prod로 유지한다.
- `dev` shared scheme과 Debug-dev/Release-dev/Profile-dev를 추가했다.
- `APP_DISPLAY_NAME`: Prod `발맞춤`, Dev `발맞춤 Dev`.
  `Info.plist`의 `CFBundleDisplayName`은 이 설정을 참조하며 별도
  `InfoPlist.strings` override는 없다.
- bundle ID는 Prod `com.beomq.balmatchum`, Dev `com.beomq.balmatchum.dev`.
- `AppIcon`/`AppIconDev` 및 `LaunchScreen`/`LaunchScreenDev`를 구성별로 선택한다.
  패키지 선택 결과는 `.qa/branding-20260928/package-selection.json`에 있다.
- launch storyboard는 중앙 정렬, 정사각형 제약, `scaleAspectFit`으로 전체 그림을
  유지하고 `LaunchBackground` named color를 사용한다. iOS 최소 타깃은 15.0이다.
- iOS 전체 지원 버전·iPad·실기기 QA를 수행했다는 뜻은 아니다.
- `fvm flutter build ios --simulator --debug`와
  `fvm flutter build ios --simulator --debug --flavor dev` 모두 성공했다.
  한글 이름 변경 후 재빌드도 성공했다.
- 최종 패키지와 iPhone 17 Pro / iOS 26.4 `simctl listapps` 모두
  Prod `발맞춤`, Dev `발맞춤 Dev` 및 기존 bundle ID를 확인했다.
  `.qa/branding-20260928/name-verification.json`이 정확한 결과다.
- `plutil`, `xmllint`, 두 storyboard의 `ibtool` 검증은 종료 0.
- Apple 공식 문서:
  https://developer.apple.com/documentation/xcode/configuring-your-app-icon/
  https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen/

## 변경 위치와 직접 확인

- Android: `android/app/src/main/kotlin/com/beomq/balmatchum/MainActivity.kt`,
  `android/app/src/main/res`의 launcher·launch drawable·버전별 theme,
  `android/app/src/dev/res`의 Dev override.
- iOS: `ios/Runner.xcodeproj/project.pbxproj`, `dev.xcscheme`,
  `ios/Runner/Info.plist`, 두 launch storyboard와 `Assets.xcassets`.
- 기존 다른 dirty 변경은 보존했다. 커밋·push·배포·SDK 업그레이드는 하지 않았다.
- Android는 `fvm flutter run --flavor dev` 또는 `--flavor prod`,
  iOS는 기존 Runner(Prod) 또는 `--flavor dev`로 선택한다.
- 이름이나 자산이 다르면 먼저 선택한 flavor/scheme, 패키지의
  applicationId/CFBundleIdentifier 및 label/CFBundleDisplayName,
  설치 앱을 순서대로 확인한다. OS가 관리하는 launch snapshot과 런처 전환을
  앱 자체의 추가 splash나 지연으로 혼동하지 않는다.

## 현재 실행 증거

- `fvm flutter build apk --debug --flavor dev`: 종료 0.
- `fvm flutter build apk --debug --flavor prod`: 종료 0.
- `fvm flutter test`: 5개 통과.
- `fvm flutter analyze`: 종료 255, 기존 한글 경로의 analysis server JSON
  `FormatException: Unterminated string` 재현.
- `fvm dart analyze`: 종료 0, No issues found.
- Kotlin LSP 미설치. Kotlin 검증은 실제 Gradle 컴파일로 수행했다.
- APK applicationId는 각각 `com.beomq.balmatchum.dev`, `com.beomq.balmatchum`.
  두 패키지 동시 설치 및 서로 다른 launcher 표시를 확인했다.
- 각 APK 내부 `branding_splash.png` 바이트가 해당 flavor 자산과 일치했다.
- 한글 표시 이름 추가 요청: Android 기존 flavor 설정은 이미 Prod `발맞춤`,
  Dev `발맞춤 Dev`였다. `aapt dump badging`으로 두 최종 APK의
  `application-label`과 package ID를 확인했고, 설치된 앱 서랍에서도 확인했다.
  증거: `.qa/branding-20260928/android11-korean-launcher-names.png`.
- Android 14/API 34 Small Phone: Dev/Prod light/dark cold start 확인.
  `.qa/branding-20260928/android14-{dev,prod}-{light,dark}.png`
- Android 11/API 30 ARM64 Pixel 5 전용 AVD를 설치해 Dev/Prod light/dark
  cold start와 전체 이미지·Dev 표기 보존을 확인했다.
  `.qa/branding-20260928/android11-{dev,prod}-{light,dark}.{png,mp4}`
  Android 11의 시스템 상하단 검정 영역은 녹화에서 별도로 보이며 이미지 잘림이 아니다.
- Android 12/13/15/16 개별 버전과 제조사 실기기는 검증하지 않았다.
- 런처 탭 녹화:
  `.qa/branding-20260928/android14-dev-launcher-dark.mp4`
  `.qa/branding-20260928/android14-prod-launcher-light.mp4`
- 빌드·테스트 통과가 모든 제조사 런처나 모든 OS 버전 검증을 뜻하지 않는다.
  사용자 직접 확인과 이해 완료도 대신 선언하지 않는다.

## 실패·중간 산출물의 구분

- 사용자가 iOS 앱을 직접 열어 로고와 splash가 모두 올바르다고 확인했다.
  사용자 시각 승인으로 기록하며 기기·OS·flavor·light/dark 범위를 추정하지 않는다.
  최신 지시에 따라 중복 iOS 재캡처와 미관 수정은 종료했다.
- 자동 iOS cold-start 캡처는 전환 중간 또는 잘못된 앱이 포함되어 있으므로
  포괄적인 cold-start 통과 증거로 주장하지 않는다. 사용자 직접 확인과 별개다.

- `prod-launch-screen-immediate.png`는 잘못 탭한 AimBe Lab 화면이다.
  Balmatchum 시작 화면 검증으로 인정하지 않는다. 해당 앱을 수정하지 않는다.
- `android-before.mp4`, `android-current.mp4`,
  `android14-dev-launcher-light.mp4`는 교체 전 또는 안전 영역 수정 전 중간 기록이다.
  최종 성공 증거로 사용하지 않는다.
- `android14-prod-light.mp4`는 MAIN/LAUNCHER 없는 adb 시작에서 아이콘이
  생략된 기록이다. 최종 라이트 증거는 `android14-prod-launcher-light.mp4`다.
