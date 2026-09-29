# 팀 개발과 리뷰 규칙

이 문서는 앱 저장소 안에서 완결되는 팀 기준입니다. 부모 `DEVELOPMENT.md`는 특정 로컬
배치의 참고 자료일 뿐 필수 문서나 추가 승인 체계가 아닙니다. 저장소 밖의 파일·서버·디자인은
각 담당자가 소유합니다. 앱 개발을 위해 부모 폴더를 Git 저장소로 만들지 않습니다.

## 신규 작업 흐름

1. [온보딩](ONBOARDING.md)을 완료하고 작업 범위·담당자·API 변경 여부를 확인합니다.
2. 작업 트리가 깨끗한지 확인한 뒤 최신 `origin/develop`에서 짧은 작업 브랜치를 만듭니다.
3. 작은 변경과 관련 테스트를 함께 작성하고 아래 QA를 실행합니다.
4. 승인된 게시 단계에서 PR을 `develop` 대상으로 열어 리뷰와 CI를 받습니다.
5. 리드와 병합을 조율합니다. `develop`은 깨진 기능이나 미검증 변경을 모으는 곳이 아닙니다.

아래 명령은 새 작업 시작 예시이며 문서를 읽는 것만으로 실행되는 명령이 아닙니다.
기존 수정이 있으면 먼저 담당자와 정리하고 임의로 stash/reset하지 않습니다.

```sh
git status --short
git fetch origin
git switch -c feat/short-description origin/develop
```

브랜치는 `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`와 소문자·하이픈 설명을 사용합니다.
Jira 번호는 요구하지 않습니다. 커밋은 `type: 한글 요약`, PR 본문은 변경 이유·검증·영향을
기록하고 `Co-Authored-By`를 넣지 않습니다. 스테이징은 파일명을 명시합니다.

`main`은 릴리스 PR과 버전 태그만을 위한 브랜치입니다. 릴리스 안정화와 다음 개발이
겹칠 때만 `release/*`를 선택적으로 사용합니다. 릴리스·병합·원격 보호 설정·배포는
리드와 조율하며 자동화 에이전트는 커밋·push·PR도 명시적 요청 없이 수행하지 않습니다.
브랜치 정책과 실제 GitHub 기본 브랜치/보호 설정 상태는 별개입니다.

## 코드 경계

- `lib/main.dart`와 `lib/app/`: 앱 조립, Riverpod 수명 관리, go_router 구성.
  `dependencies.dart`는 생성 Client를 만들고 provider 해제 시 close합니다.
- 객체 의존성은 생성자로 전달합니다. 화면은 직접 Client나 서버/DB 구현을 만들지 않습니다.
  현재 `BootstrapScreen`은 `GreetingCheck` 함수를 받고 테스트에서는 이를 대체합니다.
- `lib/features/<기능>/`: 기능별 코드. 복잡한 조정·복구 규칙이 있을 때만 use case를 둡니다.
  기능 없는 repository/DB/use case 계층을 미리 추가하지 않습니다.
- 서버 DTO는 생성 패키지를 사용합니다. 앱에서 수기 DTO·생성 코드 수정·자체 백엔드용
  Dio/Retrofit을 추가하지 않습니다. 테스트는 `test/`에 `lib/` 구조를 따라 둡니다.
- 비동기 테스트는 완료 이벤트를 관찰하고 상한을 둡니다. 고정 sleep으로 성공을 기다리지 않습니다.

## 생성 클라이언트 변경

서버 담당자가 생성과 계약을 소유합니다. 승인된 새 불변 commit과 그 commit 안의 패키지
경로를 함께 받아 `pubspec.yaml`의 Git ref/path를 동시에 변경합니다. 로컬 상대 path,
움직이는 브랜치 ref, 존재하지 않는 ref/path 조합을 최종 의존성으로 남기지 않습니다.

```sh
fvm flutter pub get
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
```

`pubspec.lock`의 resolved-ref/path와 diff를 확인해 의도치 않은 업그레이드를 배제합니다.
API가 바뀌면 앱 어댑터·테스트를 갱신하고 실제 서버 URL 및 실행 revision을 받아
[연결 smoke](ENVIRONMENT.md)를 수행합니다. 앱·클라이언트·서버 버전을 함께 기록합니다.
서버 clone은 설치 조건이 아니며 앱에서 서버를 임의 수정하거나 재생성하지 않습니다.
앱 소유 생성 코드가 생길 때만 생성 명령/결과 차이 검사를 CI에 추가합니다.

## 리뷰·QA 체크리스트

- [ ] 승인 범위만 변경했고 임시 식별자 `com.beomq.balmatchum`을 외부 등록하지 않았는가?
- [ ] 앱 시작에 네트워크 요청이 없고 DI 경계·자원 해제가 유지되는가?
- [ ] 포맷, 분석, 관련 테스트, 영향받는 빌드의 명령·종료 코드를 남겼는가?
- [ ] 화면 변경은 실제 화면에서 잘림/오류/상태를 확인하고 기기와 증거를 남겼는가?
- [ ] 계약 변경은 ref/path/lockfile을 함께 검증하고 실서버 결과 또는 차단 요인을 남겼는가?
- [ ] 공개 설정과 비밀값이 분리되고 diff/로그/QA 자산에 비밀·개인 자료가 없는가?
- [ ] CI 성공, 로컬 QA, 사용자 직접 검증을 구분했는가? 미실행 항목을 성공으로 적지 않았는가?

일반 CI는 모든 push/PR 및 수동 실행 트리거가 있으며 develop df463a1에서 통과했습니다.
새 통합 SHA의 원격 결과는 별도로 확인합니다. YAML actionlint 통과는 원격 실행
성공이 아니며 검증 전 CI가 녹색이라고 가정하거나 검사를 약화하지 않습니다.

## 후속 후보의 경계

현재 범위는 최소 초기화·연결·CI입니다. Sentry, Fastlane, 기능 공개 예약/feature flag,
강제 업데이트 최소 버전 정책, Jev TypeSafe는 논의 후보이며 설치·설정·구현 승인이 아닙니다.
인증·위치·보상 등 제품 기능, 운영 DB/비밀/배포 구성도 별도 과제입니다.
