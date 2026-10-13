# 개발 휴대폰 위치 실험

진입 위젯: `PhoneLocationExperimentScreen`
(`package:balmatchum_app/features/location_experiment/location_experiment_screen.dart`).
위젯 자체가 `kDebugMode && appFlavor == 'dev'`일 때만 플러그인을 생성한다.
부모가 별도 진단 경로를 등록하며 로그인·산책 제품 흐름과 연결하지 않는다.

## 데이터와 판독

각 실행은 `experimentId`와 독립 복사된 `provenance`를 보존한다. 실험자가
simulator/physical 출처, 기기 모델, 앱 빌드를 입력하며 OS와 OS version은
런타임에서 읽는다. 입력값은 기기 attestation이 아니며 operator supplied로
명시한다. 표본의 `sequence`는 실행 안에서 0부터 증가한다. 배터리·gap을 비교할 때
실행 ID와 출처를 함께 확인하고 simulator 결과를 물리 기기 실측으로 해석하지 않는다.

간격(초), 거리 필터, 정확도, 백그라운드 요청, iOS 자동 정지와 실험 조건은
실험자 입력이다. Android 간격은 요청일 뿐 보장되지 않으며 iOS에는 이 간격을
전달할 API가 없다. gap 기준은 입력 간격이며 거리 필터·정지·OS 스케줄링으로
발생한 간격도 포함한다. 따라서 gap 수를 잃어버린 GPS 표본 수로 해석하지 않는다.

`LocationExperiment.start`는 권한·배터리 시작값을 저장하고 스트림을 구독한다.
표본마다 원본 UTC, 수신 UTC, Stopwatch 수신 경과 시간, 좌표·정확도·mocked,
권한/정밀도 및 배터리 출처를 저장한다. 충전·위치 서비스·lifecycle 이벤트,
종료 배터리/시간을 함께 보존한다. 모든 쓰기는 직렬화하고 파일 임시 쓰기+rename으로
교체한다. 저장 오류는 구독 중단과 화면 오류로 나타나며 손상 파일은 덮어써 초기화하지 않는다.

파일은 앱 Application Support의 `location-experiment.json`이며 서버 전송/로그 출력/
소스 저장은 없다. OS 백업 제외는 별도 네이티브 통합에서 판단해야 하며 이 구현은
암호화나 백업 제외를 보장하지 않는다. 보존/자동 삭제 정책을 만들지 않았다.

메트릭은 표본 수, 최대 관찰 gap, 입력 간격 초과 구간 수(첫 표본 전·종료 전 포함),
단조 경과 시간과 시작-종료 배터리 percentage point 차이를 제공한다.
OS 배터리 퍼센트는 에너지·GPS 원인별 소비량이 아니다. 관찰한 충전 상태가 모두
discharging일 때만 `observedDischargeOnly=true`이며 미관찰 구간의 충전을 증명하지 않는다.
프로세스 재시작은 기존 running 기록을 interrupted로 바꾸고 새 프로세스 이벤트의
elapsed를 null로 남긴다. 죽어 있던 시간·종료 배터리·마지막 gap은 미확인이다.
자동 재개·재시작 후 Stopwatch 결합은 없다.

권한은 시작/표본/foreground 복귀에서 확인한다. denied/deniedForever는 구독하지 않으며
복귀 시 철회는 종료한다. 플러그인 오류·stream 종료도 중단 이벤트가 된다.
백그라운드 정지 중 권한 철회는 OS가 오류를 주거나 다음 확인 때 발견하므로 즉시
검출을 보장하지 않는다. offline은 실험자 관찰 annotation이며 연결 검사가 아니다.
네트워크 요청 없이 좌표는 계속 로컬 저장된다.

## 부모에게 요청하는 네이티브 설정

Dev Debug 구성에만 권한·백그라운드 기능을 적용한다.

- iOS Info.plist: `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription` 설명. Dev Debug 전용
  `UIBackgroundModes` 배열에 `location`. 기존 다른 background 값은 보존한다.
  `BYPASS_PERMISSION_LOCATION_ALWAYS=1`을 이 실험 구성에 적용하지 않는다.
  iOS runtime Always 승격은 시스템 설정에서 실험자가 확인해야 하며
  requestPermission 결과 whileInUse를 Always로 표시하지 않는다.
- iOS Release/Profile에는 `location` 모드를 추가하지 않는다. 빈 문자열 array item
  빌드 변수 치환 대신 Debug-dev 전용 plist를 `INFOPLIST_FILE`로 지정하거나 plist
  전처리 조건으로 key+array 전체를 포함한다. archive의 plist에서 모드 부재를 확인한다.
- Android `src/devDebug/AndroidManifest.xml`: `ACCESS_COARSE_LOCATION`,
  `ACCESS_FINE_LOCATION`, 백그라운드 시 `ACCESS_BACKGROUND_LOCATION`.
  API 31+ coarse/fine 동시 요청. API 29+ background 승격은 앱 설정에서 확인한다.
  foreground service의 `FOREGROUND_SERVICE` 및 `FOREGROUND_SERVICE_LOCATION`,
  service `foregroundServiceType=location`은 geolocator 플러그인 merged manifest를 검사한다.
- API 33+ `POST_NOTIFICATIONS` 선언·runtime 처리는 부모의 네이티브 진단 권한 경로에서
  필요하다. 현재 어댑터는 알림 권한을 요청/조회하지 않으며 `notChecked`로 기록한다.
  알림 권한 거부와 foreground service 동작은 별개이며 알림이 보일 것이라 단정하지 않는다.
  부모가 허용/거부를 확인한 후 실험 조건에 메모한다.

## 직접 확인 / 장애 순서

`fvm flutter run --flavor dev` Debug에서 진단 경로로 들어가 값을 입력한다.
정지/이동, foreground/background, 자동 정지 on/off, 정밀/근사, 거부/영구 거부,
설정에서 권한 철회 후 복귀, 비행기 모드 관찰, 충전 연결/해제, 프로세스 강제 종료 후
재진입을 각각 독립 실험으로 수행한다. 종료 후 메트릭과 로컬 원본 이벤트를 비교한다.
오류 시 화면 오류 → 네이티브 plist/merged manifest → 실제 runtime 권한 →
서비스 켜짐 → 파일 접근 → OS background 제한 순서로 확인한다.

실제 기기 배터리/좌표 gap/백그라운드 지속: **NOT RUN (사용자 유보)**.
사용자 이해·직접 검증: 미확인. 시뮬레이터는 에너지 실측 증거가 아니다.

## 공식 문서 확인 (2026-10-13)

- https://pub.dev/packages/geolocator (14.1.1): 권한·배경 모드·플랫폼별 Settings,
  고정 간격 비보장 및 accuracy 권한.
- https://pub.dev/packages/battery_plus (7.1.2): 퍼센트·상태 stream·save mode,
  Java 17 / Kotlin 2.2.0 / AGP 8.12.1 / Gradle 8.13 / iOS 13 최소.
- https://pub.dev/packages/path_provider (2.1.6): Application Support 경로,
  플랫폼 지원 및 테스트 주입.

공식 API의 동작과 코드의 관찰값을 구분하며 실기기 성공을 추정하지 않는다.

## 로컬 검증 증거

- `fvm flutter pub get`: exit 0, 공개 의존성 3개 고정 추가. 기존 path_provider는
  2.1.6 transitive에서 direct로 바뀌었고 기존 패키지 버전은 변경하지 않았다.
- `fvm dart analyze lib/features/location_experiment test/features/location_experiment`:
  No issues found. `fvm flutter analyze`는 한글 경로 LSP 초기화 JSON 파싱
  `FormatException: Unterminated string`으로 exit 255; 직접 Dart 분석으로 확인했다.
- `fvm flutter test`: 63 tests passed, exit 0 (실험 13개 포함).
  clock/store/sensor 주입, 고정 sleep 없음. 첫 실행 fake single-subscription stream의
  미구독 close 정체를 broadcast fake로 수정한 뒤 단일 실행 통과.
- `fvm flutter pub get --enforce-lockfile`, `git diff --check`: exit 0.
- 실제 진단 UI 표시/네이티브 빌드: 부모 통합 검증 담당, 이 단위에서는 NOT RUN.
  non-dev gate 위젯 테스트는 플러그인 미생성과 빈 화면을 검증했다.
