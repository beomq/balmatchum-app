# Android CI/CD 통합 준비 — 2026-09-29

## 결론과 범위

읽기 전용 GitHub API와 로컬 파일 비교를 완료했다. 기존 workflow, iOS, pubspec,
공유 checkout은 변경하지 않았다. 이번 신규 파일은 이 문서뿐이다.
후속 승인으로 신규 `.github/workflows/validate-prod-build.yml`과
`tool/verify_prod_bundle.sh`를 로컬 구현했다. 기존 workflow는 수정하지 않았다.
원격 실행은 아직 하지 않았으며 기존 파일 통합은 리드 조율 이후다.

로컬: `chore/app-bootstrap`, `d30874069ac684ccbeaac2c2a21710424e8263aa` + dirty.
원격 develop: `df463a1afbac7cb8f51e3a431980e84ca6edec9c`.
원격 성공은 로컬 branding/watch/Prod signing 변경의 검증이 아니다.

## 경로별 현재 검증과 미완료

| 경로 | 확인된 증거 | 남은 검증 |
| --- | --- | --- |
| 일반 CI | ci.yml push/PR/manual, CI 36297475795 success, 16단계 모두 success | 통합된 새 SHA의 PR CI |
| Dev signed build/CD | deploy-dev.yml manual/develop 전용, CD 36303845066 success, 21단계 모두 success | 새 SHA의 Dev 서명 빌드; 업로드는 별도 승인 |
| Prod signed build | 로컬 AAB 서명·패키지·16KB 통과 | 새 workflow 정적 검사와 승인된 원격 실행 |
| Prod Play upload | workflow 없음, 등록/업로드 미수행 | 현재 범위 밖, 별도 제품/Play/배포 승인 |
| iOS/watch CI/CD | 원격 등록 workflow 두 개에 Apple job 없음 | Apple owner 독점 담당; 이 문서에서 통과 주장 안 함 |

원격 Dev workflow는 버전 코드 >1, package com.beomq.balmatchum.dev, internal,
draft를 검사하고 upload 스크립트도 같은 조건을 강제한다. 자동 rollout은 없다.
단, manual 실행은 실제 Play write를 수행하므로 단순 검증 목적으로 실행하면 안 된다.

- https://github.com/beomq/balmatchum-app/actions/runs/36297475795
- https://github.com/beomq/balmatchum-app/actions/runs/36303845066

## 실제 조회 명령과 결과

`gh api repos/beomq/balmatchum-app/...` GET으로 다음을 조회했다(성공):
`branches/develop`, `actions/workflows`, 위 두 `actions/runs/{id}`와 `/jobs`,
`compare/d308740...develop`, 각 변경 파일의 `contents/{path}?ref=df463a1...`,
`environments/play-prod`, `/secrets`, `/variables`, `/deployment-branch-policies`,
`environments/play-dev/secrets`, `environments/staging/secrets`, `actions/secrets`.
비밀값을 조회하거나 등록하지 않았다.

- 등록 workflow: ci.yml, deploy-dev.yml, 두 개만 active.
- play-prod: Secrets 0, Variables 이름은 ANDROID_PACKAGE_NAME, GCP_SERVICE_ACCOUNT,
  GCP_WORKLOAD_IDENTITY_PROVIDER, PLAY_TRACK. 값의 정확성 및 클라우드 IAM은 미검증.
- play-prod: main branch만 허용, reviewer beomq, admin bypass 불가,
  prevent_self_review=false. develop은 현재 branch protection 비활성.
- repository Secrets 0. play-dev에는 Android 서명 Secret 3개가 있다.
  staging에도 별도 Secrets가 있으나 Prod로 재사용하지 않는다.

## 원격 대비 파일 충돌 목록

기준 d308740→원격 develop의 변경 파일 9개를 현재 로컬과 내용 비교했다.

| 파일 | 판정/처리 |
| --- | --- |
| `.github/workflows/ci.yml` | 로컬과 원격 동일. 원격 유지; 수정 필요 없음 |
| `.gitignore` | 내용 충돌. 원격 gha-creds-*.json + 로컬 *.pfx, keystore-password.txt 합집합 필요 |
| `android/app/build.gradle.kts` | 의미 변경 겹침. 원격 Dev 유지 + 로컬 prodUpload/Prod 검증 task/Prod 비활성화 제거만 반영 |
| `android/app/src/main/AndroidManifest.xml` | 로컬과 원격 동일. 중복 패치 금지 |
| `tool/check_connection.dart` | 로컬과 원격 동일. 원격 유지 |
| `.github/workflows/deploy-dev.yml` | 원격에만 있음. 그대로 보존 |
| `tool/upload_play_dev.sh` | 원격에만 있음. 그대로 보존 |
| `docs/PLAY_DEV_DEPLOY.md` | 원격에만 있음. 그대로 보존 |
| `docs/learning/tasks/dev-play-deploy.md` | 원격에만 있음. 그대로 보존 |

이는 충돌 예상 목록이지 merge 실행 결과가 아니다. 그 외 로컬 미커밋 branding,
watch, README/온보딩 변경은 이 트랙에서 이동·게시하지 않는다. 특히 ios/Watch와
watch embed target은 Apple owner 통합 대상으로 남긴다.

## 재사용한 현재 로컬 증거

`shasum -a 256 build/app/outputs/bundle/prodRelease/app-prod-release.aab` 종료 0:
`b377ac55d9b5f6aeeec69596319be3bbc591dd774d88dc8e136df34c1aa0d00b`.
직전 검증 기록과 동일하므로 재빌드하지 않았다.
현재 `android/app/build.gradle.kts` SHA256:
`1b76a1b7dd30005acb730501df0387a43e7cbb06c75efbb279590fb789fff5fd`.
`git diff --check` 종료 0.

직전 실제 실행 결과는 [Prod 로컬 검증](ANDROID_PROD_LOCAL.md)에 보존:
Prod 빌드0, Dev secret-free debug0, Prod missing/Dev-only 차단1(예상), 테스트5개/0,
Dart analyze0, Flutter analyze255(한글 경로), bundletool/서명/16KB ELF/ZIP0.
package com.beomq.balmatchum, version 0.1.0(1). 16KB 기기 실행과 Play 승인은 미검증.

## 안전한 게시 계획 — 아직 실행하지 않음

리드 승인 후 최신 원격 develop에서 **별도 깨끗한 checkout**의
`chore/android-prod-build-validation` 브랜치를 사용한다. 현재 dirty checkout은
checkout/rebase/reset하거나 통째로 복사하지 않는다. 게시 시 원격 SHA를 재확인한다.

정확한 이 트랙 파일 allowlist:
1. `android/app/build.gradle.kts`: 위 Prod delta만 적용.
2. `.gitignore`: 세 패턴 합집합만 적용(기존 사용자 변경이므로 리드 승인 후).
3. 신규 `.github/workflows/validate-prod-build.yml`: 아래 계약으로 구현.
4. `docs/ANDROID_PROD_LOCAL.md`: 로컬 증거/키 보관 한계.
5. `docs/ANDROID_CICD_PREP_20260929.md`: 본 계획.

최종 CI는 현재 요청된 branding까지 포함한 통합 SHA를 검증해야 한다.
서명 설정만 게시한 SHA로 범위를 축소하지 않는다. 아래 목록은 이동·게시 승인이 아니다.

Android 통합 inventory:
- `android/app/src/main/kotlin/com/beomq/balmatchum/MainActivity.kt`
- `android/app/src/main/res/drawable/launch_background.xml`, `drawable/splash_icon.xml`
- `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/drawable-xxxhdpi/`의 branding_splash.png,
  branding_splash_safe.png, launcher_foreground.png
- `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `android/app/src/main/res/values/colors.xml`, `values/styles.xml`,
  `values-night/styles.xml`, `values-v31/styles.xml`, `values-night-v31/styles.xml`
- `android/app/src/dev/res/drawable-xxxhdpi/`의 같은 세 PNG 및
  `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
- `docs/BRANDING_QA.md`, `docs/ANDROID_PROD_LOCAL.md`, 본 문서,
  신규 workflow와 `tool/verify_prod_bundle.sh`
- Manifest는 원격과 동일하므로 유지. `.gitignore` 충돌은 위 합집합으로 조율.

Apple owner 통합 inventory: `ios/Runner.xcodeproj/project.pbxproj`,
`ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme`, `ios/Runner/Info.plist`,
두 LaunchScreen storyboard, AppIcon/AppIconDev/LaunchImage/LaunchImageDev/
LaunchBackground asset catalog, `ios/Watch`와 embed target. 이 트랙에서는 수정하지 않는다.

### 신규 Prod build-only workflow 계약

- `workflow_dispatch`만, push/PR 자동 서명 없음. `contents: read`, OIDC 권한 없음.
- 현재 play-prod의 main-only 정책에 맞춰 main에서만 signed job 실행. 브랜치 정책을
  몰래 확장하지 않는다. develop PR에서는 secret-free CI만 검증한다.
- environment play-prod의 승인 이후만 secret 접근. runner 임시 파일 umask077,
  env로 secret 전달, set +x, 키 파일 trap 정리. 키/비밀번호는 artifact 제외.
- JDK17, 저장소 .fvmrc/FVM4.0.1, 잠금 의존성, format/analyze/test 후 Prod AAB 빌드.
- package/version/cert 지문(expected Prod SHA256)/jarsigner/bundletool validate,
  PAGE_ALIGNMENT_16K, 모든 .so LOAD 정렬, 파생 APK zipalign 검증.
- artifact는 AAB와 공개 검증 결과만, 짧은 보관 기간. Play auth/upload step 없음.
- 구현 후 actionlint와 shellcheck(해당 shell) 및 fixture의 누락 secret/잘못된 ref
  차단 검사. 원격 실행 전까지 YAML만으로 통과라고 하지 않는다.

Prod environment에 필요한 **Secret 이름만**:
- `ANDROID_UPLOAD_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

각각 workflow에서 Prod 전용 keystore와 BALMATCHUM_PROD_* 환경으로 연결한다.
alias는 balmatchum-prod-upload로 코드에 고정. Play service account JSON/OIDC는
build-only에 필요 없다. Dev/staging 값을 복사하지 않는다.

## 남은 권한 게이트

1. 리드의 통합 파일/기존 .gitignore 변경 승인 및 별도 게시 checkout 준비 승인.
2. commit/push/PR 승인, 새 SHA CI 확인; merge는 별도 승인.
3. play-prod Secret 등록 별도 승인(이번에는 미수행).
4. 실제 원격 증명은 main-only 정책에 관한 리드 결정 및 별도 dispatch/environment 승인 대기.
   CI 시험만을 위해 main 릴리스를 만들지 않는다. 현재 정책은 그대로 유지한다.
5. Play 앱/인증서 등록, versionCode 정책, 업로드/배포는 이후 별도 승인.

로컬 키 외부 백업은 여전히 미수행이다. 원격 Secret 등록도 백업을 대신하지 않는다.
이번 작업에서 network write, workflow dispatch, 업로드, commit/push는 하지 않았다.

## 로컬 구현 검증 결과

- 신규 workflow: manual/main-only/play-prod, contents read만. OIDC·Play 업로드 없음.
  잠금 설치/format/analyze/test/Prod 빌드 후 전용 verifier 호출, AAB와 공개 결과만 보관.
- bundletool 1.18.3 다운로드는 기존 검증 바이너리의 SHA256으로 확인한다.
- verifier: package/version, 고정 Prod 인증서, jarsigner, bundletool validate/config,
  모든 ELF LOAD, 파생 APK ZIP 정렬·서명을 검사한다. 비밀번호는 임시600 파일로
  전달하고 EXIT trap으로 제거한다. 첫 env: 방식은 bundletool 미지원으로 실패해 수정했다.
- actionlint 1.7.12, shellcheck 0.11.0, bash -n: 모두 종료0.
- preflight fixture: develop ref →1, main+누락 keystore →1, main+세 입력 →0.
- 기존 최종 Prod AAB에 새 verifier 실제 실행 →0. package 0.1.0(1), 예상 인증서,
  6 ELF, 16KB ZIP 통과. 앱 재빌드 없이 기존 AAB를 재사용했다.
- YAML/Bash LSP 미설치. 위 전용 정적 검사와 실제 실행으로 검증했다.
- 실제 GitHub runner 실행 및 환경 정책 통과는 미검증이며 로컬 성공과 구분한다.
