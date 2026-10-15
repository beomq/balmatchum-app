# 개발 서버 통합 검증

개발 사용자와 경제 수치는 운영 계정·정책이 아닌 일회용 검증 fixture다.
서버의 `docs/DEV_TEST_USER.md`, `docs/PRODUCT_API.md`를 따른다.

## 네이티브 실행

1. 서버에서 `bin/dev_product_harness.dart --mode=development`를 실행한다.
2. 출력된 비공개 `session.json`을 Dev 앱의 Application Support에
   `dev-test-session.json` 이름으로 복사한다. 파일 권한은 0600으로 유지한다.
3. 다음 명령을 순서대로 실행한다. 각 테스트는 별도 앱 프로세스로 실행된다.

```sh
fvm flutter test integration_test/product_flow_test.dart --no-uninstall --flavor dev -d <simulator-id> --dart-define=SERVER_URL=http://127.0.0.1:18080/
fvm flutter test integration_test/product_restore_test.dart --no-uninstall --flavor dev -d <simulator-id> --dart-define=SERVER_URL=http://127.0.0.1:18080/
```

첫 테스트는 새로운 서버 DB가 필요하다. 센서 입력만 5,000걸음으로 주입하고,
`--no-uninstall`로 테스트 종료 시 앱과 저장 데이터 삭제를 막는다.
실제 인증·HTTP·기기 저장·라우터·화면 버튼을 사용한다. 개발 수치 기준 5P를
수령하고 cloudy 배경을 3P에 구매·적용한다. 두 번째 테스트는 세션 가져오기
파일이 없어도 보안 저장소의 인증과 서버의 잔액 2P·적용 배경을 복원하는지 검사한다.
기존 Dev 온보딩이 있으면 유지하고, 없으면 테스트 친구를 생성한다.

실제 HealthKit 측정, 물리 Watch, 운영 경제 정책은 이 테스트의 검증 대상이 아니다.
실패하면 서버 프로세스 → 세션 유효성 → 앱 연결 오류 → 서버 기록 순서로 확인한다.
토큰을 로그나 Git에 넣지 않는다.

## Watch 포함 iOS 빌드

```sh
fvm flutter build ios --simulator --debug --flavor dev -d <simulator-id>
```

Flutter 3.47.5는 Watch 동반 앱을 감지해야 `-sdk iphonesimulator` 강제 지정을
생략한다. `ios/BalmatchumWatch/Info.plist`는 실제 Watch 빌드의 입력이면서
Flutter의 `<target>/Info.plist` 탐색 경로다. `COMPANION_BUNDLE_IDENTIFIER`는
Runner에서는 해당 flavor의 앱 식별자, Watch에서는 동반 iPhone 식별자로 치환된다.
로그에 `Watch companion app found.`가 있어야 한다. 이 설정을 xcconfig에만
숨기면 공유 Swift 패키지가 watchOS용으로만 해석되어 iOS import가 실패할 수 있다.
