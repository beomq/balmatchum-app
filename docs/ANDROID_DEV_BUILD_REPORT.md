# Android Dev AAB 검증 기록 — 2026-09-26

기반 브랜치 `chore/app-bootstrap`, 기반 커밋 `d308740`의 기존 수정은 보존했습니다.
현재 변경은 미커밋이며 브랜치 전환/push/Play 쓰기를 하지 않았습니다. 기존 QA 기록은
변경하지 않고 새 `.qa/android-dev-20260926/`에 증거를 저장했습니다.

## 최종 산출물

```text
/Users/beomseok/Desktop/프로젝트/Flutter_앱/balmatchum/app/build/app/outputs/bundle/devRelease/app-dev-release.aab
```

- AAB SHA-256: `6dc5743f9bdb31603ce7c6a1da6189ebebf58f8ac60e9f28c5e645962c01d115`
- package: `com.beomq.balmatchum.dev`
- label: `발맞춤 Dev`
- versionName: `0.1.0`, versionCode: `1`
- minSdk: `24`, targetSdk: `36`
- SERVER_URL 미지정: 연결 버튼 비활성, 제품 기능 없음
- release manifest에 INTERNET 권한 포함, HTTP 예외 없음

업로드 키와 AAB 인증서의 SHA-256은 동일합니다.

```text
66:A0:5B:5D:16:02:AA:26:80:DA:A0:60:36:42:19:C7:B1:A7:54:68:BA:D0:EA:39:61:FC:3B:96:9A:7B:94:B7
```

alias `balmatchum-dev-upload`, 주체 `CN=Balmatchum Dev Upload`, 2048-bit RSA /
SHA256withRSA. 비밀값은 shell 환경변수/도구의 password-file 입력으로만 전달했습니다.
인증서 공개 지문만 기록하며 private key와 비밀번호는 출력하거나 저장소에 넣지 않았습니다.

## 실행 결과

| 검증 | 종료 코드 | 결과 |
| --- | --- | --- |
| `fvm flutter analyze --no-pub` | 255 | 기존 한글 경로 SDK JSON 오류 |
| `fvm dart analyze` | 0 | No issues found |
| `fvm flutter test` | 0 | 5개 통과 |
| `fvm dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver` | 0 | 11개 변경 없음 |
| `fvm flutter build apk --debug --flavor dev` | 0 | 비밀값 없이 Dev debug 빌드 |
| `fvm flutter build appbundle --flavor dev --release` | 0 | 최종 Dev 키 서명 AAB 생성 |
| bundletool 1.18.3 validate / manifest / resources | 0 | 번들 구조, package, 버전, label 확인 |
| `jarsigner -verify <AAB>` | 0 | jar verified |
| `keytool -printcert -jarfile <AAB>` / 로컬 keytool 인증서 조회 | 0 | SHA-256 일치 |
| `:app:validateDevSigning` — 환경변수 없이 | 1 (예상) | 비밀 설정 누락 차단 |
| `:app:bundleProdRelease --dry-run` | 1 (예상) | prod release task 없음 |
| bundletool build-apks + apksigner verify | 0 | 최종 AAB 유래 APK, Dev 인증서 일치 |
| adb install / am start -W | 0 | Android API 34 arm64 emulator-5580 실행 정상 |
| aapt badging | 0 | 발맞춤 Dev, package/version/SDK 확인 |
| git diff --check / iOS·lib·test·pubspec 무변경 검사 | 0 | 요청 범위 유지 |

첫 Gradle 빌드는 AGP의 resValues 기본 비활성으로 실패했으며 `buildFeatures.resValues`
활성화 후 두 빌드 모두 통과했습니다. 첫 AAB 점검에서 기존 INTERNET 권한이 debug에만
있던 것을 발견해 main manifest에 추가하고 최종 AAB/debug를 다시 빌드했습니다.

jarsigner는 자체 서명 인증서 체인, 타임스탬프 부재, ZIP POSIX 속성 미보호 경고를
출력했습니다. 서명 자체는 검증됐고 로컬 upload key와 일치하나 공개 CA 체인 검증 통과를
의미하지는 않습니다. Kotlin/YAML LSP가 설치되지 않아 그 진단은 불가했으며 실제 Gradle
빌드로 설정을 검증했습니다. 원격 CI는 이번 작업에서 실행하지 않았습니다.

## 화면과 한계

기존 앱이 없는 QA 에뮬레이터에서 debug APK를 먼저 확인하고, 서명이 다른 debug 설치만
제거한 뒤 최종 AAB에서 생성한 upload-key 서명 universal APK를 설치했습니다.
`.qa/android-dev-20260926/release.png`의 720x1280 화면을 직접 확인했습니다. 앱 제목,
비활성 연결 버튼과 URL 미설정 안내가 잘림/겹침 없이 표시됩니다. 표시 이름은 앱 manifest
리소스와 aapt에서 검증했습니다. 실제 사용자 검증·Play 배포 테스트 통과를 대신하지 않습니다.

운영 ID는 `com.beomq.balmatchum`으로 유지하며 prod release variant는 비활성입니다.
Dev release에 debug 서명 fallback이 없고 debug APK의 Android Debug 지문은 Dev upload
지문과 다릅니다. Play 내부 테스트 업로드, versionCode 중복/Play 정책 확인, 스토어 등록은
리드가 수행합니다. 이번 산출물은 서버가 설정되지 않은 최소 부팅 검증용입니다.

재현: [Android Dev 안내](ANDROID_DEV.md).
