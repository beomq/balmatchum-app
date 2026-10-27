# 상품 통합 테스트 하네스

서버 커밋 `d2201ba06548256129447579a6f36b7c77812364`의
`server/bin/dev_product_harness.dart`가 필요하다. 생성 client 계약 변경은 없으므로
앱의 client pin은 바꾸지 않는다.

하네스의 개발 사용자 bootstrap은 development 모드, loopback 호스트,
DB 이름 `balmatchum_dev_test`에서만 fixture 시작 포인트 10P를 한 번 지급한다.
재접속해도 추가 지급하지 않으며 운영 보상 잔액에 합산하지 않는다.
50P 걸음 보상과 3P 배경 구매는 서로 다른 원장을 검증한다.

1. 서버 패키지에서 아래 하네스를 실행하고 `PRODUCT_HARNESS_READY`를 기다린다.
   매 반복마다 하네스를 종료하고 다시 실행해 새 임시 DB를 사용한다.
2. Dev 앱을 시뮬레이터에 설치한 뒤 출력된 비공개 세션 파일을 앱 컨테이너의
   `Library/Application Support/dev-test-session.json`으로 권한 0600으로 복사한다.
   파일 내용과 인증 토큰은 출력하거나 커밋하지 않는다.
3. 두 테스트를 아래 순서로 실행한다. `--no-uninstall`은 첫 테스트에서 저장한
   네이티브 인증을 두 번째 테스트의 새 프로세스에서 복원하기 위해 필요하다.

```sh
# 서버 패키지, Dart 3.13.4
SERVERPOD_PASSWORD_database=local-disposable-test-only \
  dart run bin/dev_product_harness.dart --mode=development

# 앱 패키지, Flutter 3.47.5
XCODE_XCCONFIG_FILE="$(pwd)/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter test integration_test/product_flow_test.dart \
  integration_test/product_restore_test.dart \
  --no-uninstall --flavor dev -d <simulator-id> \
  --dart-define=ADMOB_TEST_ADS=true \
  --dart-define=SERVER_URL=http://127.0.0.1:18080/
```

기대 결과는 두 테스트 성공이다. 구매·복원 후 fixture 잔액은 7P이며 운영 보상
잔액은 50P다. 실패하면 하네스 준비 신호 → 세션 가져오기 → 앱 연결 오류 →
서버 fixture 잔액 순서로 확인한다. 종료 시 직접 시작한 하네스·내장 PostgreSQL과
임시 파일만 정리한다. 이미 켜져 있던 시뮬레이터는 종료하지 않는다.
