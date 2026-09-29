# watchOS 아이콘 통합 검증 — 2026-09-28

## 범위와 구성

- 기존 `ios/Runner.xcodeproj`에 단일 SwiftUI `BalmatchumWatch` 타깃을 추가했다. 실행 화면은 검정 배경뿐이며 제품 기능은 없다.
- Debug/Release/Profile은 `발맞춤`, iOS `com.beomq.balmatchum`, watch `com.beomq.balmatchum.watchkitapp`이다.
- 각 `-dev` 구성은 `발맞춤 Dev`, iOS `com.beomq.balmatchum.dev`, watch `com.beomq.balmatchum.dev.watchkitapp`이다.
- `Watch.xcconfig`가 기존 `Flutter/Generated.xcconfig`를 포함한다. 제품 버전과 빌드 번호는 iOS와 같은 `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER`에서 가져온다. 검증한 패키지는 모두 `0.1.0 (1)`이다.
- 두 구성 모두 제공된 `AppIcon` 하나를 사용한다. PNG 17개의 SHA-256은 Downloads 원본과 동일하다. 원본은 수정하지 않았다.
- 최소 watchOS는 10.0이다. 독립 실행 제품으로 선언하지 않으며 `WKCompanionAppBundleIdentifier`로 각각의 iOS 앱에 연결한다.

## 실행 결과

Xcode 26.4.1 (17E202), watchOS 26.4 Simulator (23T240b), Apple Watch Series 11 (46mm)에서 확인했다.

| 검사 | 결과 |
| --- | --- |
| `plutil -lint ios/Runner.xcodeproj/project.pbxproj` | 종료 0 |
| `git diff --check` | 종료 0 |
| `xcrun --sdk watchsimulator swiftc -parse-as-library -typecheck -target arm64-apple-watchos10.0-simulator ios/Watch/WatchApp.swift` | 종료 0 |
| watch `Debug-dev`, `-sdk watchsimulator ARCHS=arm64 CODE_SIGNING_ALLOWED=NO` | 종료 0 |
| iOS `dev` scheme, `Debug-dev`, generic iOS Simulator, 서명 비활성화 | 종료 0 |
| iOS `Runner` scheme, `Debug`, generic iOS Simulator, 서명 비활성화 | 종료 0 |
| Dev/Prod watch 앱 `simctl install`, `simctl launch` | 모두 성공, PID 반환 |
| 패키지 Info.plist 및 Assets.car | AppIcon 연결, 동반 ID·이름·버전 일치 |
| Dev/Prod 임베드 watch Assets.car `cmp` | 동일 |

초기 watch 빌드는 런타임 부재로 65, iOS scheme은 70으로 실패했다. `xcodebuild -downloadPlatform watchOS`가 종료 0으로 완료된 뒤 해결됐다. SDK 업그레이드는 하지 않았다.

첫 iOS 임베드 빌드는 `Thin Binary`와 순환 의존성이 생겨 65로 실패했다. 추가한 `Embed Watch Content`를 `Thin Binary` 앞으로 이동한 뒤 두 구성 모두 성공했다.

SourceKit 단독 파일 진단은 `main attribute cannot be used in a module that contains top-level code`를 표시하지만 실제 watch 타깃 컴파일과 명시적 `-parse-as-library` 타입 검사는 통과한다. JSON용 Biome은 설치돼 있지 않으며 추가 설치하지 않았다. JSON은 파싱 및 actool 컴파일로 확인했다. 빌드에는 AppIntents.framework를 사용하지 않아 metadata extraction을 생략한다는 경고가 있다. 기능 로직이 없어 별도 단위 테스트를 추가하지 않았다.

## 시각 확인과 재현

최종 런처 캡처: `/tmp/balmatchum-watch-evidence-20260928/watch-grid.png`.
런처 하단에 Dev/Prod의 동일한 발바닥 아이콘 두 개가 표시된다. 제공 원본과 같은 그림이며 원형 마스크 안에서 잘리지 않는다. 임시 전환 프레임은 최종 근거로 사용하지 않았다.

재현할 때 Xcode에서 `dev` 또는 `Runner` scheme을 빌드하면 `Runner.app/Watch/BalmatchumWatch.app`이 생성된다. watch 시뮬레이터에 설치하고 Simulator의 Device > Home으로 앱 목록을 열어 확인한다. 문제 발생 시 watch 런타임 설치 여부 → 빌드 단계 순서 → 패키지 Info.plist의 동반 ID/버전 → Assets.car의 AppIcon 순서로 확인한다.

실기기 서명·프로비저닝·배포·Release archive는 검증하지 않았다. 사용자의 직접 확인도 미확인이다. 기존 미커밋 브랜딩 변경은 보존했고 커밋·푸시·원격 등록은 하지 않았다.

## 변경 파일

- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Watch/WatchApp.swift`
- `ios/Watch/Watch.xcconfig`
- `ios/Watch/Assets.xcassets/Contents.json`
- `ios/Watch/Assets.xcassets/AppIcon.appiconset/Contents.json`
- 같은 appiconset의 `48.png`, `55.png`, `58.png`, `66.png`, `80.png`, `87.png`, `88.png`, `92.png`, `100.png`, `102.png`, `108.png`, `172.png`, `196.png`, `216.png`, `234.png`, `258.png`, `1024.png`
- `docs/WATCH_ICON_QA.md`

## 공식 근거

- https://developer.apple.com/documentation/watchos-apps/migrating-to-a-single-target-watchos-app
- https://developer.apple.com/documentation/bundleresources/information-property-list/wkcompanionappbundleidentifier

단일 타깃은 코드·자산 위치를 한곳으로 유지한다. 동반 ID는 iOS의 CFBundleIdentifier와 같아야 한다. 설치된 Xcode의 기존 iOS 앱용 watch 템플릿도 `.watchkitapp` 접미어를 사용한다.
