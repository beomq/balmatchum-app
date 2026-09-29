# 검증 전용 통합 브랜치

기준 origin/develop df463a1, 브랜치 chore/cicd-validation.
원본 chore/app-bootstrap dirty checkout은 수정하지 않고 별도 worktree에
Android/iOS 브랜딩, Watch와 embed target, 공개 Signing 설정, 관련 문서를 통합했다.
키·비밀번호·.qa·build·.omo·.worktrees는 게시 대상에서 제외했다.

Android signed build는 signing-validation 환경의 reviewer 승인 이후 Dev/Prod를
각각 빌드한다. Secret은 matrix의 명시적 이름으로 선택하며 flavor 간 fallback이 없다.
Dev와 Prod 고정 인증서, 패키지, 버전, 16KB ELF/ZIP을 검증한다.
Apple workflow는 owner 원본에서 해당 브랜치 push trigger만 추가했다.
기존 deploy-dev 및 upload_play_dev.sh는 원격 내용 그대로이며 실행하지 않는다.

리드가 환경의 정확한 branch policy, reviewer, admin bypass 금지와 Secret 6개 준비를
확인했다. 환경 승인 우회, main/develop merge, PR 생성, store upload는 허용되지 않는다.

로컬 actionlint/shellcheck/diff check/plutil은 통과했다. 통합 checkout의 잠금 설치,
Dart 분석, 테스트 5개와 format 11개 무변경을 확인했다. 원본 163개 파일의 SHA256은
통합 후 변동이 없었다. 원격 최종 SHA의 결과는 실제 실행 후 보고한다.

이 문서의 현재 branch/environment 계약이 이전 준비 문서의 main-only 제안보다 우선한다.
