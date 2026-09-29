# Android Dev 빌드와 서명 AAB

Android만 `dev` / `prod` flavor를 사용합니다. iOS와 Dart 제품 동작은 변경하지 않습니다.

| flavor | applicationId | 표시 이름 | release |
| --- | --- | --- | --- |
| dev | `com.beomq.balmatchum.dev` | 발맞춤 Dev | Dev upload PKCS12 필수 |
| prod | `com.beomq.balmatchum` | 발맞춤 | 비활성화: 별도 운영 서명 승인 필요 |

namespace와 MainActivity 패키지는 `com.beomq.balmatchum`을 유지합니다. Dev suffix는
설치 ID에만 적용됩니다. 명령에서 Android flavor를 명시합니다. CI는 비밀값 없이
`fvm flutter build apk --debug --flavor dev`로 debug key 빌드를 수행합니다.
release에 debug key fallback은 없으며 prod release variant 자체가 비활성화되어
Dev 환경변수를 전달해도 운영 ID의 release를 만들 수 없습니다.

## 비밀값을 노출하지 않는 빌드

키는 저장소 밖에 두고 팀의 승인된 비밀 전달 경로로 받습니다. 아래 경로는 현재
빌드 담당자 장비의 예시이며 다른 팀원은 승인된 자신의 절대 경로를 사용합니다.
alias는 `balmatchum-dev-upload`, 형식은 PKCS12입니다. Gradle은 다음 환경변수만 읽습니다.

- `BALMATCHUM_DEV_STORE_FILE`: 키 파일 절대 경로
- `BALMATCHUM_DEV_STORE_PASSWORD`: 저장소 비밀번호
- `BALMATCHUM_DEV_KEY_PASSWORD`: 키 비밀번호

현재 키는 두 비밀번호가 같습니다. 아래는 bash에서 저장소 루트 기준으로 실행합니다.
비밀번호를 명령 인자/로그/파일 diff에 넣지 않고 subshell 종료 시 환경을 제거합니다.
`set -x`, Gradle `--debug`, 전체 환경 덤프를 사용하지 않습니다.

```bash
(
  set +x
  export BALMATCHUM_DEV_STORE_FILE="$HOME/.balmatchum-signing/android-dev/balmatchum-dev-upload.p12"
  IFS= read -r BALMATCHUM_DEV_STORE_PASSWORD < "$HOME/.balmatchum-signing/android-dev/keystore-password.txt"
  export BALMATCHUM_DEV_STORE_PASSWORD
  export BALMATCHUM_DEV_KEY_PASSWORD="$BALMATCHUM_DEV_STORE_PASSWORD"
  fvm flutter build appbundle --flavor dev --release
)
```

출력: `build/app/outputs/bundle/devRelease/app-dev-release.aab`.
버전은 `pubspec.yaml`의 `0.1.0+1`(versionName 0.1.0 / versionCode 1)이며 이후 업로드 시
Play에 이미 사용된 versionCode 여부를 리드가 확인합니다. 이 명령은 업로드하지 않습니다.
서명 변수가 없으면 Dev release는 실패해야 합니다. prod release도 실패해야 합니다.
키를 `.env`, key.properties, tracked 파일, `--dart-define`에 넣지 않습니다.

기본 AAB는 SERVER_URL 미설정으로 연결 버튼이 비활성입니다. 별도 승인된 HTTPS 개발
API를 사용할 때만 `--dart-define=SERVER_URL=...`을 추가합니다. release에는 HTTP 예외가
없습니다. 앱에 컴파일되는 URL은 공개 설정이며 서명 비밀값과 별개입니다.

## 검증과 인계

```sh
fvm flutter analyze
fvm dart analyze
fvm flutter test
fvm flutter build apk --debug --flavor dev
shasum -a 256 build/app/outputs/bundle/devRelease/app-dev-release.aab
jarsigner -verify build/app/outputs/bundle/devRelease/app-dev-release.aab
```

한글 경로 Flutter 분석 제한은 [온보딩](ONBOARDING.md)을 따릅니다. bundletool의
`validate`, `dump manifest`, `dump resources`로 package/version/표시 이름을 확인합니다.
`keytool -printcert -jarfile <AAB>`의 SHA-256과 로컬 upload key의 인증서 SHA-256을
비교합니다. keytool 비밀번호는 `-storepass:env BALMATCHUM_DEV_STORE_PASSWORD`로 전달하고
비밀번호 자체를 인자로 쓰지 않습니다. 업로드 키의 자체 서명 인증서는 체인 신뢰 경고가
날 수 있으므로 암호학적 서명 검증 결과와 별도로 보고합니다.

AAB는 직접 설치하지 않습니다. 지원 기기에서 Dev APK를 실행해 표시·ID를 확인하고,
필요 시 bundletool로 AAB에서 APK set을 만들어 실행 검증합니다. AAB 절대 경로·SHA-256,
인증서 지문·버전·테스트 결과·미검증 항목을 리드에게 전달합니다. Play Console 쓰기,
앱 서명 키 관리, internal-test 업로드는 리드가 수행합니다. 이 문서는 운영 출시 승인이 아닙니다.

공식 근거: [Flutter Android flavors](https://docs.flutter.dev/deployment/flavors),
[Android 배포와 서명](https://docs.flutter.dev/deployment/android).
