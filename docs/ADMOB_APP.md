# AdMob 앱 통합

## iOS CI 설정

`apple-ci.yml`은 저장소 변수 `ADMOB_IOS_APP_ID_DEV`와
`ADMOB_IOS_APP_ID_PROD`를 각 Xcode 빌드에 전달한다.
`apple-upload.yml`은 선택한 GitHub environment의 `ADMOB_IOS_APP_ID`를
Fastlane에 전달한다. Archive 전 형식과 비샘플 ID를 검사하므로 값이 없으면
서명·업로드 전에 실패한다. 변수 등록과 실제 CI 실행은 아직 수행하지 않았다.
로컬 Fastlane Ruby 구문 검사만 통과했으며 원격 빌드 성공의 증거는 아니다.

## 호출 API와 소유권

`lib/features/ads/ads_session.dart`의 `createAdsController(Client)`는 현재 인증 객체와
인증 헤더를 한 번 캡처합니다. 생성 Client와 `ads.createIntent`/`ads.getIntent`만 사용합니다.
`ads.createIntent`의 마지막 필수 인자 `AdPlatform platform`은 `defaultTargetPlatform`에서
정합니다(iOS → `ios`, Android → `android`). 서버는 그 플랫폼의 adUnit을 반환합니다.
그 밖의 플랫폼은 광고 미지원이므로 createIntent를 호출하지 않고 failed로 끝납니다.
요청 중 계정이 바뀌면 controller를 취소하고, 캡처한 헤더를 새 계정 헤더로 교체하지 않습니다.
동일 계정의 인증 객체 교체도 안전하게 취소합니다. 닫은 뒤 새 controller를 만드세요.

```dart
final controller = await createAdsController(client);
if (controller == null) return; // 로그인 필요
try {
  if (!context.mounted) return;
  await showAdsSheet(
    context,
    controller: controller,
    purpose: 'dailyReward', // 또는 extraQuiz
    targetDate: day.date, // 서버 KST YYYY-MM-DD
    targetRevision: day.revision,
  );
} finally {
  controller.dispose();
}
```

화면 조립은 부모 증분에서 진행합니다. daily_activity/first_meeting/records는 이 통합에서
수정하지 않았습니다. `AdsSheet`를 직접 렌더링할 수도 있습니다. `showAdsSheet`는 닫힐 때
취소하며, controller 최종 dispose는 호출자가 소유합니다. 검증 결과가 필요한 부모는
시트가 닫히기 전 controller listener에서 `status == AdsStatus.verified`와 `intent.id`를
읽되, **실제 자격/보상 소비는 경제 서버 트랜잭션의 다음 증분**에서 처리해야 합니다.

흐름: native metadata 확인 → UMP 갱신/필수 양식/광고 허용 확인 → SDK init → 서버 create(실행 플랫폼)
→ 반환된 플랫폼별 adUnit load → 반환 userId/customData 그대로 SSV 설정 완료 → show → dismiss/dispose
→ 서버 상태 조회 한 번. 클라이언트 reward callback은 `clientRewardObserved`만 바꾸며
verified/포인트/entitlement를 만들지 않습니다. verified도 혜택 지급 완료라는 뜻은 아닙니다.

pending은 수동 확인 버튼이나 앱 resumed 이벤트에서 한 번 조회합니다. polling/timer/sleep은
없습니다. 로드 실패 재시도는 먼저 기존 intent를 조회하고 pending일 때만 같은 대상 create를
다시 호출합니다(서버 멱등성). expired/consumed/verified는 다시 광고를 로드하지 않습니다.

## 외부 공개 설정

SDK는 `google_mobile_ads: 9.1.0`에 고정했습니다(2026-10-19 pub.dev 최신).
App ID와 ad unit ID는 다른 값입니다. 가짜 운영 ID를 넣지 않았습니다.

- Android: `ADMOB_ANDROID_APP_ID` 환경변수를 Gradle에 전달합니다. 기본 빈 문자열.
  `MobileAdsInitProvider`를 manifest merge에서 제거하여 미설정 앱도 Dart까지 진입합니다.
  실제 metadata는 `balmatchum/ads_config` → `appId`로 읽습니다.
- iOS: 외부 xcconfig/Xcode build setting `ADMOB_IOS_APP_ID`를 설정합니다.
  Info.plist와 별도 Info-Debug-dev.plist 모두 이 값을 참조하며
  `GADDelayAppMeasurementInit=true`입니다. dev 전용 plist도 반드시 유지해야 합니다.
  실제 네이티브 확인에서 SDK 9.1.0은 AppID 누락 시 Dart 진입 전
  `GADInvalidInitializationException`으로 종료했습니다. 지연 플래그만으로 방지되지 않아
  Xcode build phase에서 누락/형식 오류를 명시적인 빌드 오류로 차단합니다.
  Android 및 주입된 SDK 경계의 미설정 상태는 missingConfiguration으로 표시합니다.
- 테스트 AppID는 명시적 dev/debug 설정에서만 허용합니다. Dart
  `--dart-define=ADMOB_TEST_ADS=true`가 필요하며 release/prod에서는 거절합니다.
  테스트 adUnit도 서버가 공식 ID를 반환해야 합니다. 앱이 다른 ID로 바꾸지 않습니다.
- UMP 양식 실패는 failed, 광고 비허용은 consentRequired입니다. 필요한 개인정보 옵션
  진입 버튼을 시트에서 제공합니다. 콘솔의 개인정보 메시지와 SSV URL은 별도 외부 설정입니다.

Android 공식 테스트 설정:

```sh
ADMOB_TEST_ADS=true fvm flutter run --flavor dev \
  --dart-define=ADMOB_TEST_ADS=true
```

iOS 공식 테스트 설정(명시적 opt-in 전용 파일, 기본 설정에 include하지 않음):

```sh
RUN_TMP=/tmp/bm-ads
mkdir -p "$RUN_TMP"
export RUN_TMP TMPDIR="$RUN_TMP"
XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter test integration_test/ads_native_test.dart --flavor dev \
  --dart-define=ADMOB_TEST_ADS=true -d 06C7AD47-C910-4D53-95C3-C1AD6283311B
```

이 smoke는 공식 테스트 광고 로드와 실제 네이티브 SSV 옵션 설정/해제만 확인합니다.
공식 공용 테스트 unit으로 실제 서버 SSV 수신 성공을 증명할 수 없습니다.

## 재현과 장애 확인

```sh
fvm flutter test test/features/ads
fvm dart analyze --format machine lib/features/ads test/features/ads \
  integration_test/ads_sheet_test.dart integration_test/ads_native_test.dart test_driver/ads_driver.dart
fvm flutter build apk --debug --flavor dev
RUN_TMP=/tmp/bm-ads TMPDIR=/tmp/bm-ads \
  XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/AdMobTest.xcconfig" \
  fvm flutter drive --flavor dev --dart-define=ADMOB_TEST_ADS=true \
  --driver=test_driver/ads_driver.dart --target=integration_test/ads_sheet_test.dart \
  -d 06C7AD47-C910-4D53-95C3-C1AD6283311B
```

시트 통합 테스트의 서버/광고 수명주기는 주입한 fake이며 실제 시트/네이티브 앱에서
pending→verified 표시와 닫기 동작을 확인합니다. 미설정 경계는 iOS 자체 기동 제약 때문에
metadata 채널을 빈 값으로 주입합니다. 실제 SDK 테스트는 별도 `ads_native_test.dart`입니다.

한글 경로 `fvm flutter analyze`는 LSP JSON 길이 파싱 오류(exit 255)가 있었으므로
`fvm dart analyze --format machine`과 언어 서버 진단을 사용했습니다. 경고를 suppress하지 않습니다.
기존 local `pubspec_overrides.yaml` 서버 client path는 보존했습니다. 이 파일로 설치한 lock은
path override 상태이므로 부모가 최종 Git client ref/path/lock 재설치를 확인해야 합니다.
pubspec과 lock의 승인 서버 ref는 af08b3fb034a541693ae6b93e9e1187b05aa6b32(`source: git`)입니다. pubspec과 lock은 머지된 서버 develop 커밋을 Git 소스로 고정하며 `pubspec_overrides.yaml`은 커밋하지 않습니다.

장애 확인 순서: native 실제 AppID → dev/test 모드 일치 → UMP 실패/허용 상태 → create의
configurationMissing → 반환 adUnit/SSV 메타데이터 → load/show 실패 → 서버 pending과 SSV
프록시/콘솔/서명 로그. nonce나 인증 헤더를 로그에 기록하지 마세요.

실제 SSV 검증에는 승인된 앱/광고 unit, 개인정보 메시지, 공개 HTTPS callback 프록시,
AdMob 콘솔 등록과 기기 시청이 필요합니다. 이 작업에서는 콘솔/배포/라이브 광고를 변경하거나
실행하지 않습니다. 사용자 이해와 직접 검증은 자동 테스트 결과와 별개로 미확인입니다.

공식 근거:
- https://developers.google.com/admob/flutter/quick-start
- https://developers.google.com/admob/flutter/privacy
- https://developers.google.com/admob/flutter/rewarded
- https://pub.dev/packages/google_mobile_ads/versions/9.1.0
- 서버 `docs/ADMOB_SSV_API.md`

## 이번 실행 증거 (2026-10-19)

- 광고 전용 회귀: controller 순서/중복 dismiss/one-shot dispose/실패/늦은 콜백,
  실제 Google SDK 채널 SSV payload, UMP 순서, create/get 고정 헤더를 실행했습니다.
- `fvm flutter test test/features/ads`: 23 passed, exit 0. 최종 광고 대상
  `fvm dart analyze --format machine ...`: 진단 없음, exit 0.
- 외부 공식 샘플 AppID를 opt-in한 iOS `flutter drive`: exit 0, 실제 앱에서 시트 호출,
  pending/verified/미설정 경계 표시와 닫기 통과. 실제 캡처를 열어 겹침/overflow가 없음을
  확인했습니다. 캡처는 `/tmp/bm-ads/ads-screenshots/ads-{pending,verified,missing-config}.png`입니다.
  `ads_sheet_test.dart`는 전체 AdsStatus를 390/1440 너비, light/dark, 2배 글꼴에서
  layout exception 없이 표시하는지 확인합니다. 해당 조합의 네이티브 스크린샷 전수 검토는
  수행하지 않았습니다.
- Android `fvm flutter build apk --debug --flavor dev`: exit 0,
  `build/app/outputs/flutter-apk/app-dev-debug.apk`. 네이티브 광고 실행은 Android 기기 부재로
  미실행입니다. 기존 플러그인의 Built-in Kotlin 이전 안내가 출력되었으며 변경하지 않았습니다.
- 전체 `fvm flutter test`: 236 passed, 3 test-file compile failures(exit 1).
  기존 daily_activity fixture의 `DailyRecord.gracePolicyStatus`,
  `policyVersion` 필수 인자 누락이며 `authenticated_records_router_test.dart`도 같은 fixture를
  import합니다. 병렬 서버 경제 변경과 연결된 기존 테스트로, 소유 범위 밖이라 수정하지 않았습니다.
- `git diff --check`와 두 Info.plist/project.pbxproj `plutil -lint`: 통과.
- iOS 첫 두 실행은 누락 AppID의 SDK 조기 예외를 확인한 실패 실행입니다. 이를 빌드 게이트로
  차단했으며 실제 설정이 없는 일반 iOS 빌드는 명시적으로 실패하도록 했습니다.
- `ads_native_test.dart`를 외부 `AdMobTest.xcconfig`와 명시적 dev test define으로 실행:
  Xcode build 성공, **1 passed, exit 0**. 실제 Google SDK의 UMP 준비 → 공식 iOS rewarded
  test unit 로드 → SSV userId/customData 설정 → dispose가 통과했습니다.
  광고를 show하거나 라이브 광고/경제 보상을 지급하지 않았습니다. 실제 Google SSV callback은
  여전히 승인된 콘솔/공개 callback 등록이 필요한 외부 검증 한계입니다.
