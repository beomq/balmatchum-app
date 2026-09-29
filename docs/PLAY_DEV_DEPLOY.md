# Play 자동 draft 업로드

## 대상과 활성화

- `deploy-dev.yml`: develop push → play-dev → com.beomq.balmatchum.dev / internal.
- `deploy-prod.yml`: main push → play-prod → com.beomq.balmatchum / internal.
- 두 경로 모두 draft 업로드만 수행한다. 테스터 rollout, completed release와 심사 제출은
  자동화하지 않는다. 최종 출시는 사람이 Play Console에서 별도로 결정한다.
- 현재 구현 브랜치는 chore/cicd-validation이다. 이 브랜치 push는 Play 업로드를 하지 않는다.
  **develop 병합은 별도 승인 필요**하며 이 작업에서 병합하지 않는다. Prod 경로도 main에
  승인된 변경이 반영돼야 활성화된다. 검증을 위해 환경 branch trust를 확장하지 않는다.

## 버전 코드 정책

빌드 전에 Play의 bundles, APKs, 모든 tracks에 나타나는 최대 versionCode를 조회하고
그 값보다 1 큰 코드를 선택한다. 재실행도 다시 조회하므로 이미 확정된 업로드 코드를
재사용하지 않는다. 수동 recovery 입력은 조회한 최대값보다 커야 한다.
코드는 2100000000 미만이어야 하며 한도에 도달하면 실패한다.

확인된 Dev 이력은 초기 코드 1과 run 36303845066의 draft 코드 2다.
이 값을 다음 코드로 고정하지 않고 실행마다 Play를 조회한다. Prod의 로컬 코드 1은
Play 업로드 이력이 아니며 다음 사용 가능 번호의 근거가 아니다.

GitHub 실행은 앱별 concurrency로 직렬화한다. 다만 Play Console의 수동 업로드는
이 잠금에 참여하지 않으므로 원자적 예약을 보장할 수 없다. 업로드 직전에 다시 조회해
경쟁을 발견하면 중단한다. 그 이후 경쟁이나 과거 삭제되어 API에 보이지 않는 코드도
Play가 중복을 거부한다. 이런 경우 현재 Console 기록을 확인한 뒤 더 큰 수동 recovery
코드로 새 실행을 시작한다. 업로드/commit 응답 유실 때는 상태 확인 없이 재시도하지 않는다.
모든 변경 주체를 통제하지 않고 절대적인 무충돌을 약속하지 않는다.

## 환경 구성

각 환경은 다음 공개 Variables를 사용한다: ANDROID_PACKAGE_NAME, PLAY_TRACK,
GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT.
서명 Secrets는 ANDROID_UPLOAD_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
ANDROID_KEY_PASSWORD이며 각 앱 전용 키를 사용한다. 키 원문은 출력하거나 artifact에 넣지 않는다.

리드는 Prod 변수와 전용 서명 Secret 3개 준비를 확인했다. **Prod 최초 Play 앱 등록,
첫 바이너리 수동 등록 필요 여부, 서비스 계정 API 접근은 별도 확인 대상**이다.
서명 빌드 성공은 Play 등록/업로드 성공이 아니다. Apple 준비 상태와도 별개다.
2026-09-29 조사 시 원격 main 브랜치도 없었다. main 생성·통합과 Prod 최초 등록 및
API 권한 확인이 남아 있어 Prod 경로는 준비된 구현이지 현재 운영 중인 자동화가 아니다.

## 실행과 복구

검사 → OIDC 조회 토큰 → 버전 선택 → 서명 빌드 → AAB 보관 → 새 OIDC 토큰 →
버전 재확인 → binary 업로드 → literal draft 트랙 변경 → validate → commit 순서다.
commit은 changesNotSentForReview=true 및 ERROR_IF_IN_REVIEW를 사용한다.
검토 중 변경을 자동 취소하거나 심사 제출로 전환하지 않는다.

수동 workflow_dispatch는 해당 앱의 허용 브랜치에서만 복구용으로 사용할 수 있다.
실패 시 ref/package/track → 환경과 OIDC → Play 등록/권한 → 사용된 버전 코드 →
서명 순으로 확인한다. 성공 로그의 정확한 versionCode와 Console draft 상태를 확인한다.
draft 성공은 설치 또는 공개 출시 완료가 아니다.

공식 근거:
- https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit
- https://developers.google.com/android-publisher/tracks
