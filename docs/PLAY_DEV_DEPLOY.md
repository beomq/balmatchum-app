# Dev 내부 테스트 수동 배포

## 범위와 준비

`.github/workflows/deploy-dev.yml`은 `develop`에서 수동 실행하며 `play-dev`만
사용한다. 대상은 `com.beomq.balmatchum.dev`의 `internal`이다. 운영 앱 배포는
구현하지 않으며 prod release variant도 비활성이다.

기존 로컬 Dev flavor·서명 변경을 develop 기반 작업 공간에 가져왔다. 원본 앱
작업 공간의 미커밋 변경은 보존했다. 이후 통합할 때 같은 Dev 변경을 중복 적용하지 않는다.

환경 변수:

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `ANDROID_PACKAGE_NAME` = `com.beomq.balmatchum.dev`
- `PLAY_TRACK` = `internal`

환경 Secrets:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`: 첫 업로드와 같은 Dev PKCS12 키의 base64
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

alias는 Gradle에 `balmatchum-dev-upload`로 고정되어 별도 변수는 사용하지 않는다.
기존 `staging` Secrets는 원문을 읽을 수 없으므로 로컬 원본으로 등록해야 한다.
키·비밀번호를 문서, 채팅, Git에 넣지 않는다. `play-prod`에는 Dev 키를 등록하지 않는다.

## 실행 절차

1. 승인 후 변경을 커밋·push하고 PR/CI를 거쳐 `develop`에 반영한다.
   기본 브랜치 develop에 workflow가 있어야 Actions 수동 실행 버튼이 표시된다.
2. 첫 배포와 같은 키가 `play-dev`에 등록되어 있는지 확인한다.
3. Play Console에서 이미 사용한 가장 높은 versionCode를 확인한다.
4. Actions → Deploy Dev to Play internal → Run workflow에서 `develop` 선택.
5. 사용하지 않은 더 큰 `version_code`를 입력한다. 자동 증가가 아니므로 재실행에도
   Play 등록 상태를 먼저 확인한다. 로컬 검증용 번호 2는 실제 업로드에 예약되지 않았다.
6. 첫 출시 준비 전에는 `release_status=draft`로 업로드한다. 이 상태는 테스터에게
   배포되지 않는다. 앱 설정·테스터 구성이 완료되고 내부 출시를 승인한 뒤에만
   `completed`를 선택한다. draft 앱에서 completed는 Play가 거부할 수 있다.
7. Actions의 성공뿐 아니라 Play Console의 패키지·버전·트랙·상태를 확인한다.
   completed라면 참여 링크로 설치해 버전과 실행까지 확인한다.

검사 → 서명 AAB 빌드 → 7일 보관 artifact → OIDC 인증 → edit 생성 → AAB 업로드 →
트랙 변경 → validate → commit 순서다. 토큰은 빌드가 끝난 뒤 발급한다.
Google 서비스 계정 JSON 키는 필요 없다. 서명 파일은 임시 경로에 복원하고 종료 시 삭제한다.
한 번에 하나의 Dev 배포만 진행하며 진행 중인 배포를 새 실행으로 취소하지 않는다.
GitHub concurrency는 중간 대기 실행을 대체할 수 있으므로 일괄 배포 큐로 사용하지 않는다.

`SERVER_URL`은 아직 제공되지 않아 연결 버튼이 비활성인 최소 부팅 빌드다.
이 작업은 실제 산책 기능이나 서버 연동 완료를 의미하지 않는다.

## 실패 시 확인 순서

- 검사 실패: Analyze/Test 로그. 로컬 한글 경로의 Flutter 분석 오류는 원격 Linux
  분석 통과를 대신하지 않는다. 검사를 건너뛰어 배포하지 않는다.
- 서명 실패: play-dev의 세 Secret 존재 여부 → PKCS12 암호·alias → 기존 업로드 인증서.
- 인증 실패: develop 선택 → play-dev 환경 → OIDC 조건 → 서비스 계정 연결·Play 권한.
- 업로드 실패: 패키지와 versionCode 중복 → 앱 초기 등록 상태 → API 오류 본문.
- 확정 실패: 로그의 edit ID와 Play Console 상태를 확인한다. 검토 중인 변경은
  자동 취소하지 않는다. 네트워크 응답 유실은 실패 확정이 아니므로 자동 재시도하지 않는다.
- draft 성공: 테스터 설치 불가는 정상이다. 내부 테스트 출시와 테스터 참여를 따로 완료한다.

## 옆 pane 배포 검증 전달문

Dev 배포 테스트만 수행한다. 먼저 사용자 승인된 커밋·push·develop 통합 여부와
play-dev의 서명 Secrets를 확인한다. 이 문서와 workflow를 읽고 실제 실행 전
Play의 최대 versionCode 및 초기 출시 상태를 확인한다. 운영 앱·play-prod·main은
수정하지 않는다. 첫 실행은 draft 업로드 검증으로 제한하고, completed 출시는
사용자와 범위를 확인한다. 결과에는 Actions URL, 커밋 SHA, versionCode,
패키지, internal 트랙 상태, AAB 인증서 확인 결과와 설치 검증 여부를 남긴다.
실패 시 요청을 반복하기 전에 edit ID와 Play 반영 여부를 확인한다.

## 공식 근거

- https://github.com/google-github-actions/auth : service account WIF, access_token_scopes
- https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles/upload
- https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks/update
- https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit
