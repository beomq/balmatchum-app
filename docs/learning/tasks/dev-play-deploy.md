# Dev Play 배포 연결 — 2026-09-27

## 요청과 구현

사용자는 Dev 서명 연결·수동 배포 워크플로 구현을 요청했고, 실제 배포 테스트는
옆 pane에 맡기도록 지정했다. 사용자 이해·직접 설치 확인은 미확인이다.
커밋·push·PR·develop 통합·Play 업로드는 실행하지 않았다.

기준: origin/develop `275cd9f`, 작업 브랜치 `feat/dev-play-deploy`.
원본 `chore/app-bootstrap`의 미커밋 변경은 보존했다. 배포에 필요한 기존 Dev
Gradle·manifest 구성만 별도 worktree에 반영했다.

수동 실행, develop 제한, play-dev 환경, Dev/internal 대상 검사, 분석·테스트,
서명 AAB 빌드, artifact 보관, 빌드 후 OIDC 토큰 발급, Play edit 업로드·검증·확정을
구현했다. Fastlane 의존성을 추가하지 않고 공식 REST API를 사용한다.
versionCode는 사용자가 미사용 값을 지정하며 첫 실행은 draft가 기본이다.
운영 릴리스는 비활성이고, 검토 중 변경 자동 취소·실패 쓰기 자동 재시도는 하지 않는다.

## 검증 근거

| 명령·검사 | 결과 |
| --- | --- |
| fvm flutter pub get --enforce-lockfile | 0 |
| fvm dart format 검사 | 0, 11개 파일 변경 없음 |
| fvm flutter test | 0, 5개 통과 |
| fvm flutter analyze | 255, 기존 한글 경로 LSP JSON FormatException 재현 |
| fvm dart analyze | 0, 기존 tool/check_connection.dart:16 avoid_print info 1개 |
| fvm flutter build appbundle --flavor dev --release --build-number=2 | 0, 46.8 MB |
| jarsigner -verify | 0, jar verified; 자체 서명·타임스탬프·POSIX 경고 별도 |
| bundletool 1.18.3 validate / dump manifest | 0, com.beomq.balmatchum.dev, versionCode 2 |
| keytool 인증서 조회 | 이전 업로드 보고서의 SHA-256과 일치 |
| actionlint 1.7.12 | 0, 두 workflow 검사; shellcheck 미설치로 별도 실행 안 함 |
| bash -n / git diff --check | 0 |
| curl 함수 대체 로컬 계약 검사 | 정상 흐름과 운영 패키지 차단 통과; 실제 HTTP 검증 아님 |

인증서 SHA-256:
`66:A0:5B:5D:16:02:AA:26:80:DA:A0:60:36:42:19:C7:B1:A7:54:68:BA:D0:EA:39:61:FC:3B:96:9A:7B:94:B7`

Kotlin/YAML/Bash LSP가 설치되어 있지 않아 LSP 검사는 실행하지 못했다.
대신 실제 Gradle 빌드, actionlint, bash 문법 검사로 확인했다.
빌드 시 CupertinoIcons 폰트 관련 기존 경고도 출력되었다. 제품 UI 코드는 변경하지 않았다.

## 남은 연결과 권한

- GitHub 조회로 play-dev의 변수 4개와 develop 제한을 확인했다. Secrets는 없음.
- 동일한 로컬 Dev 키 파일의 존재와 빌드 서명을 확인했다. 새 환경에 등록할 승인 요청 중.
- 실제 OIDC 교환, Play 업로드, 원격 CI 및 사용자 설치는 미검증이다.
- cmux 실행 파일은 있지만 소켓 연결이 거부되어 옆 pane에 전달하지 못했다.
  사용자에게 세션/pane 정보를 질문했고 전달문은 PLAY_DEV_DEPLOY.md에 준비했다.
- 현재 develop은 원본 bootstrap 브랜치의 후속 문서·CLI 수정까지 포함하지 않는다.
  기존 avoid_print 개선 커밋을 이 작업에서 임의로 포함하지 않았다.

실행·장애 확인 순서와 옆 pane 전달문: [Dev 배포 안내](../../PLAY_DEV_DEPLOY.md).

## 실행 인계 후 확인 — 2026-09-27

사용자가 `진행`으로 play-dev 서명 Secrets 등록과 커밋·push·PR·CI 확인·develop
병합을 승인했다. wc-app이 단독 실행하며 Dev/internal/draft만 테스트한다.
completed 출시, 테스터 배포, 운영 및 서버 변경은 범위 밖이다.

- play-dev에 `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_PASSWORD`를 기존 로컬 키에서 등록했다. 비밀 원문은 출력하지 않았다.
- staging의 Secrets 이름·updated_at과 play-prod의 빈 목록은 등록 전후 동일했다.
- Play Console의 Dev 앱 모든 App Bundle 목록은 총 1개, versionCode 1이었다.
  앱은 임시 상태, internal 버전도 임시이며 번들은 비활성이다. 다음 후보는 2다.
- 재실행한 Flutter 테스트는 5개 통과했다. 기존 avoid_print 진단을 재현하고
  원본 브랜치 d308740의 동일한 stdout.writeln 수정을 이 worktree에 적용했다.
  이후 Dart 분석은 진단 없음, LSP 진단 없음, 포맷 11개 변경 없음이었다.
- 로컬 versionCode 2 AAB의 jarsigner 검증과 공개 인증서 지문 일치를 확인했다.
  원격 CI와 실제 OIDC·Play 업로드는 아직 실행 전이다.

핵심 흐름은 deploy-dev.yml의 대상 검사 → 분석·테스트 → 서명 빌드 → OIDC →
upload_play_dev.sh의 edit 생성·업로드·트랙 변경·검증·확정이다. draft 성공은
테스터 설치 가능 상태를 뜻하지 않으며 사용자 이해·직접 설치는 미확인이다.
