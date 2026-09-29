# balmatchum_app

발맞춤 Flutter Android/iOS 앱입니다. 현재 범위는 최소 초기화, 명시적 서버 연결 확인,
테스트와 CI이며 제품 기능은 없습니다.

이 저장소만 clone하면 개발·단위/위젯 테스트·빌드할 수 있습니다. 부모 디렉터리의
문서나 서버/디자인 checkout은 필수가 아닙니다. 생성 서버 클라이언트는 고정 Git
의존성으로 설치됩니다. 실제 연결 확인에만 별도로 실행 중인 서버가 필요합니다.

## 처음 참여하는 팀원

1. [온보딩](docs/ONBOARDING.md): clone, 도구 설치, 잠금 의존성, 테스트와 빌드.
2. [환경 설정](docs/ENVIRONMENT.md): `SERVER_URL`, 기기별 실행, 공개 설정과 비밀값 경계.
3. [팀 개발 규칙](docs/TEAM.md): 코드 경계, 클라이언트 갱신, 브랜치·리뷰·QA.
4. 자동화 에이전트도 [AGENTS.md](AGENTS.md)와 위 저장소 내부 문서를 따릅니다.
5. [Android Dev AAB](docs/ANDROID_DEV.md): Dev flavor, 전용 서명, 번들 검증과 인계.

## 현재 기준

- Flutter **3.47.5** / Dart **3.13.4**, 프로젝트 로컬 FVM. 전역 SDK 변경 없음.
- Riverpod + 생성자 DI + feature-first + go_router.
- Serverpod **4.0.3** 생성 `balmatchum_client`: [pubspec.yaml](pubspec.yaml)의 불변 ref와
  패키지 경로, [pubspec.lock](pubspec.lock)의 resolved-ref를 함께 관리합니다.
- 개발은 `develop`에서 짧은 작업 브랜치 → PR/CI → `develop`.
  `main`은 릴리스 PR·버전 태그용입니다. 검증되지 않은 변경의 병합은 허용하지 않습니다.
- `com.beomq.balmatchum`은 **미확정 로컬 식별자**입니다. 외부 등록/서명/배포는 별도 결정입니다.

## 검증 상태와 한계

이전 로컬 검증에서 잠금 설치, Dart 분석, 위젯 테스트 5개, Android debug 빌드,
iOS 생성 클라이언트 실제 연결을 확인했습니다. 버전별 상세 근거는
[SETUP_REPORT.md](SETUP_REPORT.md)의 날짜별 기록을 참고하세요. 과거 성공은 현재 서버
가용성이나 새 변경의 QA를 대신하지 않습니다. 사용자 직접 검증은 별도입니다.

- Flutter 3.47.5의 `flutter analyze`는 한글 절대 경로에서 SDK 분석 서버 JSON 오류로
  종료 코드 255가 발생했습니다. [온보딩의 대응 절차](docs/ONBOARDING.md)를 따릅니다.
- 원격 develop df463a1의 CI와 Dev draft 배포는 통과했습니다. 현재 통합 브랜치의
  Android 서명 빌드와 Apple compile 결과는 별도로 확인하며 과거 성공으로 대체하지 않습니다.
- 마지막 실제 서버 점검에서 `127.0.0.1:58099`는 연결 거부였습니다. 연결 QA 전에
  서버 담당자에게 현재 API URL과 실행 revision을 확인하세요.

원격: https://github.com/beomq/balmatchum-app.git (PUBLIC).
로컬 부모 `balmatchum`은 Git 저장소가 아니며 앱·서버·디자인 저장소는 독립적입니다.
clone 폴더 이름은 자유이며 Dart 패키지 이름 `balmatchum_app`과는 별개입니다.
