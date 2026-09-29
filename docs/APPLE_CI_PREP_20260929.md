# Apple secret-free CI 준비 — 2026-09-29

## 결과와 범위

새 `.github/workflows/apple-ci.yml`을 추가했다. `pull_request`와 `workflow_dispatch`에서 Prod/Dev 두 matrix job이 실제 iOS release 및 종속 watch 타깃을 비서명 컴파일한다. 배포 프로파일·p12·API key는 필요하지 않으며 upload 단계가 없다. 기존 Android workflow와 iOS 파일은 이번 작업에서 수정하지 않았다.

`actionlint 1.7.7 .github/workflows/apple-ci.yml` 종료 0, `git diff --check` 종료 0이다. Go 설치 시도는 로컬 Go 부재로 127이었고, 공식 Darwin ARM64 release 바이너리를 `/tmp/balmatchum-apple-ci-tools`에 받아 검사했다. YAML language server는 미설치이며 저장소 의존성을 추가하지 않았다.

**원격 workflow는 아직 실행하지 않았다.** 로컬 Xcode 27.0 archive/IPA 성공은 별도 문서 `APPLE_ARCHIVE_CHECK_20260929.md`의 증거이며 hosted CI 통과 증거로 사용하지 않는다. 로컬에는 Xcode 26.3이 없어 이 runner 조합의 실제 컴파일 성공은 첫 원격 실행에서 확인해야 한다.

## 공식 runner 근거

2026-09-29 읽은 GitHub 공식 runner-images 문서:

- https://github.com/actions/runner-images/blob/main/README.md
- https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md

확인한 ARM64 이미지 버전은 `20260907.0337.1`, OS는 macOS 15.7.9다. 공식 라벨 표에서 `macos-15`는 ARM64이며, 다음 설치 항목이 명시돼 있다.

| 항목 | 선택 |
| --- | --- |
| runner | `macos-15` |
| Xcode | 26.3 (17C529) |
| DEVELOPER_DIR | `/Applications/Xcode_26.3.app/Contents/Developer` |
| iOS SDK | iphoneos26.2 |
| watchOS SDK | watchos26.2 |
| 제공 simulator runtime | iOS 26.2, watchOS 26.2 |

기본 Xcode는 16.4이므로 기본값을 사용하지 않는다. workflow가 Xcode 26.3과 두 SDK 26.2를 검사하며 이미지에서 제거되거나 달라지면 실패한다. 자동으로 다른 Xcode를 선택하거나 빌드를 건너뛰지 않는다. hosted 이미지 자체는 불변 pin이 아니므로 이미지 갱신 후 설치 경로를 재확인해야 한다. Xcode 27 availability는 전제하지 않았다.

저장소 `.fvmrc`의 Flutter 3.47.5를 읽고 기존 CI와 같은 flutter-action + FVM 4.0.1 방식으로 선택한다. 로컬 고정 SDK의 `packages/flutter_tools/lib/src/macos/xcode.dart`는 최소 Xcode 15, 권장 16을 선언하므로 26.3은 도구의 최소 조건을 충족한다. 이것은 hosted 컴파일 실행 증거는 아니다.

## 수행하는 검증

1. `fvm flutter pub get --enforce-lockfile`로 고정 의존성을 가져온다. Git 의존성 ref 접근 불가 시 실패하며 비밀 토큰으로 우회하지 않는다.
2. Prod는 기존 `Runner / Release`, Dev는 `dev / Release-dev`를 사용한다. 각 job이 독립된 checkout에서 Flutter config-only를 생성한다.
3. `xcodebuild ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`를 실행한다. Runner의 기존 watch dependency와 embed 단계도 함께 실행된다. opt-in 배포 서명 xcconfig는 사용하지 않는다.
4. 실제 iOS/watch 실행 파일과 watch Assets.car의 존재를 확인한다. iOS bundle ID, watch `.watchkitapp` ID, WKCompanionAppBundleIdentifier, 두 버전 필드의 일치를 검사한다.

서명 실패를 무시하거나 `continue-on-error`로 바꾸지 않는다. `fail-fast: false`는 두 구성을 각각 끝까지 확인하기 위한 설정이며 실패한 job의 판정을 바꾸지 않는다. 권한은 contents read, checkout 자격 증명 저장은 비활성화했다. PR 코드를 권한 높은 pull_request_target에서 실행하지 않는다.

## 증명하지 않는 것과 남은 실행

- 이 workflow는 컴파일·링크·자산 컴파일·watch 임베드 및 메타데이터 일치를 검사한다.
- 서명·프로파일·IPA export·TestFlight·App Store 검증, 시뮬레이터 UI 실행, 실기기 동작은 검사하지 않는다.
- 누락된 Dev watch 배포 프로파일과 무관하게 비서명 컴파일은 실행 가능하다. Dev 배포 archive 차단은 여전히 남아 있다.
- 커밋·push·원격 workflow 등록/실행은 하지 않았다. 리드가 승인된 게시 후 두 matrix job의 실제 로그와 종료 상태를 확인해야 한다. manual 이벤트는 workflow가 기본 브랜치에 등록된 뒤 사용할 수 있다.
- 실패 시 runner Xcode/SDK 검사 → Flutter pin·의존성 접근 → Flutter config-only → iOS/watch 컴파일 → 임베드 메타데이터 순으로 확인한다.

이번 변경 파일은 `.github/workflows/apple-ci.yml`과 이 문서뿐이다. 원격 CD workflow, secrets 등록, 기존 Android workflow 변경은 포함하지 않는다.
