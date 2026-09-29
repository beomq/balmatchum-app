# Apple 로컬 archive 검증 — 2026-09-29

## 판정

Prod 및 Dev iOS + watch 실서명 archive와 App Store Connect 형식의 **로컬 IPA export 성공**. 업로드·TestFlight·포털 변경은 하지 않았다. 초기 Prod 검증 당시 Dev watch 프로파일 누락으로 차단됐으나, 같은 날 사용자가 제공한 뒤 아래 Dev 후속 검증으로 해소했다. 원격 Apple CI 실행·CD는 여전히 미검증이다. secret-free CI 준비는 `APPLE_CI_PREP_20260929.md`에 별도 기록한다.

환경은 실행 당시 Xcode 27.0 (27A266a), 프로젝트 FVM Flutter 3.47.5이다. 이번 작업에서 SDK를 업그레이드하지 않았다. 기존 watch 최소 scaffold 및 브랜딩을 보존했다.

## 이번 변경

- `ios/Signing/ProdArchive.xcconfig`: 명시적으로 `-xcconfig`를 전달할 때만 수동 배포 서명. iphoneos/watchos별 프로파일 이름을 선택한다. 공유 scheme/Dev 설정에 연결하지 않는다.
- `ios/Signing/ExportOptions-Prod.plist`: `app-store-connect`, `destination=export`, manual signing, 두 번들 프로파일 매핑. 버전 자동 변경 비활성화.
- 이 문서.

기존 `ios/Runner.xcodeproj/project.pbxproj`는 작업 전 내용과 문자열 비교 결과 동일(`sharedProjectUnchanged: true`)이다. 기존 자산·watch 코드·scheme을 수정하지 않았다. `fvm flutter build ios --release --config-only --no-codesign`이 로컬 생성 Flutter 설정을 Prod release로 준비했다. 이후 Dev 실행 시 평소처럼 `fvm flutter run --flavor dev`로 해당 구성을 생성해야 한다.

## 로컬 서명 자료

안내받은 `Downloads/balmatchum_provision`은 없었고 실제 위치는 `~/Downloads/balmatchum_signing/apple/profiles`였다. p12·비밀번호·p8 내용은 열지 않았다. 기존 keychain 배포 신원을 재사용했다.

- Team: `Q4E6NKD9VN`
- Identity: `Apple Distribution: beomseok lee (Q4E6NKD9VN)`
- SHA-1: `854F9BAF7FF80F154488723861262200C0F9960D`
- 세 제공 프로파일의 만료: 2027-09-29 00:10:09 UTC, 모두 위 인증서 포함, `get-task-allow=false`.

| 대상 | 프로파일 | UUID |
| --- | --- | --- |
| Prod iOS | Balmatchum AppStore | 3668616f-7ada-49b3-a7d7-7812399d28a1 |
| Prod watch | Balmatchum Watch AppStore | dafee3c1-3551-400c-8213-30a8babe765c |
| Dev iOS | Balmatchum Dev AppStore | 18abfe57-528a-4915-8693-10eb09d3c823 |
| Dev watch | Balmatchum Dev Watch AppStore (후속 제공) | 7b5f832d-93ca-42f1-975e-6416f91a1d1b |

초기 검증에서는 Prod 두 프로파일만 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.mobileprovision`에 복사했다. 당시 제공 폴더와 두 설치 저장소에는 Dev watch 자료가 없었다. 후속 제공 이후 Dev 두 프로파일도 같은 UUID 경로에 설치했다.

## 실행 명령과 종료 코드

로그 루트: `/tmp/balmatchum-apple-20260929`.

```sh
fvm flutter build ios --release --config-only --no-codesign

xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/balmatchum-apple-20260929/Prod.xcarchive \
  -derivedDataPath /tmp/balmatchum-apple-20260929/DerivedData \
  -xcconfig ios/Signing/ProdArchive.xcconfig archive

xcodebuild -exportArchive \
  -archivePath /tmp/balmatchum-apple-20260929/Prod.xcarchive \
  -exportPath /tmp/balmatchum-apple-20260929/export \
  -exportOptionsPlist ios/Signing/ExportOptions-Prod.plist
```

각 명령은 `set -o pipefail` 및 `tee`로 로그를 저장했다. `-allowProvisioningUpdates`는 사용하지 않았다.

| 실행 | 종료 | 증거 |
| --- | --- | --- |
| Flutter config-only | 0 | `flutter-config.log`, monitor `mon_G20DPV2MKNHYA81X` |
| signed archive | 0 | `archive.log`, `ARCHIVE SUCCEEDED`, monitor `mon_07ZFEEAE33FWKGQ7` |
| IPA export | 0 | `export.log`, `EXPORT SUCCEEDED`, monitor `mon_TXMGHTDR5HKTRT9N` |
| archive `codesign --verify --deep --strict --verbose=2` | 0 | valid on disk / satisfies its Designated Requirement |
| 추출 IPA 동일 codesign 검사 | 0 | valid on disk / satisfies its Designated Requirement |
| export plist 및 Flutter privacy plist lint | 0 | OK |
| `git diff --check` | 0 | 오류 없음 |

AppIntents.framework 미사용으로 metadata extraction을 생략한다는 경고는 있다. 기능 코드 변경이 없어 단위 테스트를 추가하지 않았다.

## 산출물 및 패키지 검증

- Archive: `/tmp/balmatchum-apple-20260929/Prod.xcarchive`
- IPA: `/tmp/balmatchum-apple-20260929/export/balmatchum_app.ipa`
- IPA SHA-256: `d31d0fbd4486d06b7a05eb2b44200f2f046b09d3dab9506a33c6e686bd67f2db`
- 추가 export 근거: `export/DistributionSummary.plist`, `export/Packaging.log`, `export/ExportOptions.plist`.
- 추출 확인 위치: `ipa-check/Payload/Runner.app`.

archive와 IPA에서 모두 확인했다:

| 항목 | iOS | watch |
| --- | --- | --- |
| CFBundleIdentifier | com.beomq.balmatchum | com.beomq.balmatchum.watchkitapp |
| 버전 / 빌드 | 0.1.0 / 1 | 0.1.0 / 1 |
| 동반 ID | 해당 없음 | com.beomq.balmatchum |
| 배포 Team | Q4E6NKD9VN | Q4E6NKD9VN |
| embedded profile | Balmatchum AppStore | Balmatchum Watch AppStore |
| get-task-allow | false | false |

서명 entitlement의 application-identifier가 각 프로파일 및 `Team.BundleID`와 일치함을 assertion으로 검사했다. 버전은 기존 Flutter 생성 설정을 공유하며 export가 변경하지 않았다.

## Privacy manifest

archive와 IPA 모두 `Runner.app/Frameworks/Flutter.framework/PrivacyInfo.xcprivacy`가 있고 plist 문법 검사에 통과했다. tracking=false, 수집 데이터 목록 없음, FileTimestamp 이유 `0A2A.1`/`C617.1`, SystemBootTime 이유 `35F9.1`이다.

앱 자체와 최소 SwiftUI watch에는 별도 manifest가 없다. 현재 네이티브 진입 코드는 Flutter 연결과 빈 watch 화면뿐이다. 이번 결과는 SDK manifest 포함·문법 확인이며 앱 전체 개인정보 정책이나 App Store 서버 검증 통과를 뜻하지 않는다. 제품 기능·SDK를 추가할 때 required-reason API와 실제 데이터 수집을 다시 감사해야 한다. 검증 없이 임의의 수집/미수집 선언을 추가하지 않았다.

## 남은 Dev 및 원격 CD 작업

1. Dev watch 프로파일 제공 필요 항목은 후속 검증으로 완료됐다. Prod watch를 재사용하거나 watch를 제거하지 않았다.
2. `ios/Signing/DevArchive.xcconfig`, `ios/Signing/ExportOptions-Dev.plist`를 추가하고 `dev / Release-dev` 실서명 검증을 완료했다.
3. 후속 위임으로 `.github/workflows/apple-ci.yml`의 secret-free 컴파일 준비는 완료됐다. 원격 실행은 미확인이다. CD용 `.github/workflows/apple-deploy.yml`과 비밀 등록·업로드는 별도 리드 소유 작업이다.
4. Apple CI에는 프로젝트 고정 Flutter/FVM, 호환 Xcode와 iOS/watch SDK, 시뮬레이터 검증, 위 archive/export 명령, 두 번들 서명·버전·profile 검증과 privacy manifest 확인을 포함한다. 로컬 성공 환경은 Xcode 27.0이므로 runner 가용 버전을 확인해야 한다.
5. CD에는 임시 keychain과 명시적 프로파일 설치·정리, 승인된 p12/암호 및 각 환경의 두 프로파일 보관, 배포 인증서 일치 검사가 필요하다. 비밀 등록은 별도 승인 작업이다. 저장소에는 원본 서명 파일이나 로컬 절대 경로를 넣지 않는다.
6. 원격 업로드를 추가하려면 App Store Connect 앱/권한, API key ID·issuer·private key 보관, 버전/빌드 증가 정책, 환경 승인과 배포 대상 결정을 별도로 확인한다. export와 upload를 분리하고 기본은 업로드하지 않는다. API 키는 이번 로컬 archive/export에 필요하지 않았다.

문제 확인 순서: keychain 신원 → 프로파일 앱 ID/인증서/만료 → SDK별 archive 매핑 → 임베드 watch profile → export 매핑. 로컬 archive 성공은 TestFlight 처리·App Store 심사·실기기 실행·원격 CI 성공을 보장하지 않는다. 커밋·푸시·원격 설정·업로드는 하지 않았다.

## Dev 후속 검증 — 누락 프로파일 제공 이후

`~/Downloads/balmatchum_signing/apple/profiles/watch/dev/Balmatchum_Dev_Watch_AppStore.mobileprovision`의 인증서 SHA-1이 설치된 `854F9BAF7FF80F154488723861262200C0F9960D`와 일치했다. Team `Q4E6NKD9VN`, 만료 2027-09-29 00:10:09 UTC, `get-task-allow=false`도 확인했다. p12나 비밀키 내용은 읽지 않았다.

이번 후속 변경은 Dev opt-in 설정 두 파일과 이 보고서뿐이다. Prod 설정, 기존 브랜딩·watch·공유 project는 수정하지 않았다.

```sh
fvm flutter build ios --release --flavor dev --config-only --no-codesign --no-pub
xcodebuild -workspace ios/Runner.xcworkspace -scheme dev \
  -configuration Release-dev -destination 'generic/platform=iOS' \
  -archivePath /tmp/balmatchum-apple-dev-20260929/Dev.xcarchive \
  -derivedDataPath /tmp/balmatchum-apple-dev-20260929/DerivedData \
  -xcconfig ios/Signing/DevArchive.xcconfig archive
xcodebuild -exportArchive \
  -archivePath /tmp/balmatchum-apple-dev-20260929/Dev.xcarchive \
  -exportPath /tmp/balmatchum-apple-dev-20260929/export \
  -exportOptionsPlist ios/Signing/ExportOptions-Dev.plist
```

로그 루트는 `/tmp/balmatchum-apple-dev-20260929`다. 각 실행은 pipefail + tee로 보존했다.

| 검사 | 종료 | 증거 |
| --- | --- | --- |
| Dev Flutter config-only | 0 | `flutter-config.log`, `mon_JZKJ43J3K0V2X4E1` |
| 실제 서명 archive | 0 | `archive.log`, ARCHIVE SUCCEEDED, `mon_9Y0N4T1J3P9S6KGK` |
| 로컬 IPA export | 0 | `export.log`, EXPORT SUCCEEDED, `mon_JMGPDRKQEY23BKH4` |
| archive 및 추출 IPA codesign deep/strict 검사 | 0 | valid on disk / satisfies its Designated Requirement |
| Dev export plist·포함 Flutter privacy manifest lint | 0 | OK |

- Archive: `/tmp/balmatchum-apple-dev-20260929/Dev.xcarchive`
- IPA: `/tmp/balmatchum-apple-dev-20260929/export/balmatchum_app.ipa`
- SHA-256: `58a9f684d73c74d5085a9185c8da8c4413fabafddab2abb7f99302e6fd7595ea`
- 추출 검사: `/tmp/balmatchum-apple-dev-20260929/ipa-check/Payload/Runner.app`

archive와 IPA 모두 iOS `com.beomq.balmatchum.dev`, watch `com.beomq.balmatchum.dev.watchkitapp`, 동반 ID `com.beomq.balmatchum.dev`로 일치했다. 두 표시 이름은 `발맞춤 Dev`, 버전은 `0.1.0 (1)`이다. 실제 embedded profile UUID는 각각 `18abfe57-528a-4915-8693-10eb09d3c823`, `7b5f832d-93ca-42f1-975e-6416f91a1d1b`이다. 서명 Authority는 두 번들 모두 Apple Distribution: beomseok lee (Q4E6NKD9VN)이다. application-identifier·Team·get-task-allow=false·버전을 assertion으로 대조했다.

Flutter PrivacyInfo.xcprivacy는 archive와 IPA에 모두 포함됐고 앞선 Prod와 같은 tracking=false, 빈 수집 목록, FileTimestamp/SystemBootTime 사유를 확인했다. 이는 원격 App Store 개인정보 검증 통과가 아니다.

생성 설정 영향: `ios/Flutter/Generated.xcconfig`와 Flutter 생성 환경은 현재 **Dev release (`FLAVOR=dev`)**를 가리킨다. 의도적으로 그대로 두었으며 Prod로 전환할 때 위 Prod config-only 명령을, Dev 디버깅 시 `fvm flutter run --flavor dev`를 실행한다. 생성 파일을 수기 편집하거나 공유 scheme을 변경하지 않았다. 원격 업로드·포털 갱신·커밋·푸시는 하지 않았다.
