# Android Prod 로컬 서명 — 2026-09-29

## 범위와 키 보관

로컬 upload key와 release AAB 검증만 승인됐다. Play 등록·업로드·배포는 하지 않는다.
Google Play가 배포 APK에 사용하는 app signing key와 이 upload key는 별개이며,
현재 Prod upload 인증서는 Play에 등록하지 않았다.

후보 조사는 저장소 ignored 키 파일, `~/.balmatchum-signing`, `~/.android`,
`~/Downloads/balmatchum_provision`으로 제한했다. 홈 전체 검색이 아니다.
Dev 키와 Android debug 키만 찾았으며 `beomseok.p12`는 Apple 자료이므로 사용하지 않았다.

새 경로:
- `~/.balmatchum-signing/android-prod/balmatchum-prod-upload.p12`
- `~/.balmatchum-signing/android-prod/keystore-password.txt`
- `~/.balmatchum-signing/android-prod/upload-certificate.pem` (공개 인증서)

디렉터리 700, 파일 600. 기존 키를 덮어쓰지 않았다. OpenSSL CSPRNG 48바이트를
비밀번호 파일에 직접 생성하고 keytool의 `-storepass:file`/`-keypass:file`로 전달했다.
비밀번호를 출력하거나 명령 인자·소스·문서에 포함하지 않았다. Keychain 대신 기존
Dev와 동일한 제한 권한 비밀번호 파일 방식을 사용했다. 파일 자체는 평문 비밀번호다.

alias `balmatchum-prod-upload`, RSA 4096 / SHA256withRSA, 유효기간 10,000일.
인증서 SHA-256:
`57:56:F9:5E:CB:29:10:82:0B:A1:DA:7A:CB:E3:23:44:A5:67:30:CB:6B:C2:92:4E:4F:1A:EB:6B:2B:C5:B6:EE`

## 빌드

`android/app/build.gradle.kts`에 기존 Dev와 별도의 `prodUpload` 설정을 추가했다.
`prodRelease` 비활성화를 제거하고 `preProdReleaseBuild`에 `validateProdSigning`을
연결했다. 세 Prod 환경값이 없으면 실패하며 Dev/debug fallback은 없다.
Dev 설정과 branding/watch/iOS는 변경하지 않는다.

아래는 bash에서 실행한다. `set -x`, 환경 전체 출력, Gradle debug 로그를 사용하지 않는다.

```bash
export BALMATCHUM_PROD_STORE_FILE="$HOME/.balmatchum-signing/android-prod/balmatchum-prod-upload.p12"
export BALMATCHUM_PROD_STORE_PASSWORD="$(< "$HOME/.balmatchum-signing/android-prod/keystore-password.txt")"
export BALMATCHUM_PROD_KEY_PASSWORD="$BALMATCHUM_PROD_STORE_PASSWORD"
fvm flutter build appbundle --release --flavor prod
unset BALMATCHUM_PROD_STORE_FILE BALMATCHUM_PROD_STORE_PASSWORD BALMATCHUM_PROD_KEY_PASSWORD
```

문제 발생 시 Prod 환경값 존재 여부(값 출력 금지) → 키 파일 권한/경로 → alias →
생성 플러그인 상태 → 빌드 로그 순서로 확인한다. 누락을 Dev 키로 우회하지 않는다.

## 검증 결과

산출물: `build/app/outputs/bundle/prodRelease/app-prod-release.aab` (47.9 MB).
SHA-256: `b377ac55d9b5f6aeeec69596319be3bbc591dd774d88dc8e136df34c1aa0d00b`.
package `com.beomq.balmatchum`, 표시명 `발맞춤`, versionName `0.1.0`, versionCode `1`,
minSdk 24, targetSdk 36. SERVER_URL 미지정 최소 앱이며 운영 서버 연결 검증은 아니다.

| 명령/검증 | 종료 | 결과 |
| --- | --- | --- |
| `:app:validateProdSigning` Prod 환경 없음 | 1 (예상) | 누락 차단 |
| `:app:preProdReleaseBuild` Dev 변수만 있음 | 1 (예상) | Prod 비밀 요구, fallback 없음 |
| `fvm flutter build apk --debug --flavor dev --no-pub` 모든 서명 변수 제거 | 0 | 성공 |
| `fvm flutter build appbundle --release --flavor prod` | 0 | 최종 서명 AAB |
| `fvm flutter test --no-pub` | 0 | 5개 통과 |
| `fvm flutter analyze --no-pub` | 255 | 기존 한글 경로 FormatException |
| `fvm dart analyze` | 0 | No issues found |
| `jarsigner -verify` / `keytool -printcert -jarfile` | 0 | 서명 확인, 공개 인증서 SHA256 일치 |
| bundletool 1.18.3 validate / dump manifest / dump config | 0 | 구조·패키지·버전·PAGE_ALIGNMENT_16K |
| bundletool build-apks (Prod 키, password file 입력) | 0 | universal APK 생성 |
| `llvm-readelf -lW` | 0 | 3 ABI, 6개 so의 모든 LOAD align >= 0x4000 |
| `zipalign -c -P 16 4` 파생 universal.apk | 0 | 16KB ZIP 정렬 |
| apksigner verify --print-certs | 0 | 파생 APK도 Prod 인증서 일치 |
| git diff --check | 0 | 형식 오류 없음 |

검증 파생 파일은 `.qa/android-prod-20260929/`에 있다. AAB 자체 ZIP offset은 설치
APK의 정렬 기준이 아니므로 bundle config와 AAB에서 만든 APK를 함께 검사했다.
16KB 기기 실행은 수행하지 않았다. 정적 정렬 통과를 런타임·Play 승인으로 주장하지 않는다.

첫 `--no-pub` release 빌드는 생성된 integration_test 등록과 release 의존성 불일치로
실패했다. pub 단계를 포함한 정상 Flutter 빌드로 재생성 후 통과했으며 생성 파일은
수동 수정하지 않았다. Kotlin LSP 미설치로 진단 불가, 실제 Gradle 컴파일로 검증했다.
jarsigner의 자체 서명 체인·타임스탬프 부재·POSIX 속성 미보호 경고는 남아 있다.

이번 source 변경은 `android/app/build.gradle.kts`의 Prod 설정/검증 task/variant 활성화,
문서 추가는 이 파일뿐이다. iOS pbxproj SHA256은 작업 전후
`ca3e63071d2f3ba94f84aa2bd2766678f660f5faef09c37f6a9a7b6da1e8a5b9`로 동일하다.
Dev 서명과 기존 미커밋 branding/watch 변경은 보존했다.

## 백업 상태

**외부 장치·오프디바이스 백업은 수행하지 않았다.** 로컬 암호화 PKCS12는 백업이 아니다.
키와 공개 인증서를 별도의 암호화 저장 매체에 복사하고, 비밀번호는 별도의 승인된
비밀 저장소에 보관한 뒤 복원 시 인증서 지문을 대조해야 한다. 이번 작업은 해당
외부 복사나 비밀 저장소 등록을 수행하지 않았다.

## 공식 근거

- https://support.google.com/googleplay/android-developer/answer/9842756
- https://developer.android.com/studio/publish/app-signing
- https://developer.android.com/guide/practices/page-sizes

Google Play 공식 도움말에서 upload/app signing key 분리 및 RSA 요구를 확인했다.
Android Developers 본문 fetch는 인증 리디렉션으로 제한되어 공식 검색 및
Context7 문서를 보완 사용했다.
