# 저장된 개인 경로와 네이버 지도

`flutter_naver_map: 1.4.4`를 고정한다. SDK/Dart constraints는 변경하지 않는다.
공식 안내: https://pub.dev/packages/flutter_naver_map/versions/1.4.4

## 설정

앱 시작 시 `NAVER_MAP_CLIENT_ID` dart-define이 비어 있으면 초기화하지 않는다.
기본값이나 가짜 키, 플랫폼 메타데이터 키를 넣지 않는다.

```sh
export RUN_TMP=/tmp/naver-map-run
mkdir -p "$RUN_TMP"
export TMPDIR="$RUN_TMP"
fvm flutter run --flavor dev --dart-define=NAVER_MAP_CLIENT_ID="$NAVER_MAP_CLIENT_ID"
```

실제 Client ID와 NCP Maps Dynamic Map 활성화, Android applicationId / iOS bundle
identifier 등록은 운영자가 별도로 확인해야 한다. 이 작업은 콘솔 변경이나 유료 서비스
등록을 수행하지 않는다. dev Android ID는 `com.beomq.balmatchum.dev`, prod는
`com.beomq.balmatchum`이며 iOS는 선택한 scheme의 실제 Bundle ID를 확인한다.
현재 iOS에서 사용 가능한 앱 scheme은 `dev`/`Runner`이며 `prod` scheme은 없다.
로그인용 네이버 OAuth 키와 지도 Client ID는 서로 다르다.

1.4.4의 `FlutterNaverMap().init`는 `initializeNcp`를 호출하는 **신규 NCP 인증**이다.
legacy `NaverMapSdk.initialize`를 사용하지 않으며 별도의 legacy 인증 플래그가 없다.
Android Maven 저장소와 map-sdk 3.23.0 의존성은 플러그인 자체에 선언되어 있다.
Android INTERNET은 기존 앱 manifest에 있으며 새 위치 권한/키 설정을 추가하지 않는다.
iOS는 플러그인 등록과 SPM/CocoaPods의 네이티브 SDK 해석이 빌드 때 필요하다.
CocoaPods는 NMapsMap 3.23.0 고정, SPM은 `from: 3.23.0`이며 이번 환경에서는
NMapsMap 3.24.0 / NMapsGeometry 1.0.2로 해석되었다.

## 동작과 데이터 경계

`main.dart` → `recordMapRuntime.initialize` → 기록 상세 `_Routes` →
`RecordedRouteMap` 순서다. 초기화 성공 후에만 NaverMap을 구성한다. 초기화 성공은
인증/타일 로드 성공을 의미하지 않는다. 지연 인증 오류는 전역 SDK 상태를 오류로 바꾼다.
초기 타일 로드는 `onMapLoaded`로 확인하며 15초 안에 로드되지 않으면 좌표 윤곽으로
돌아간다. SDK는 일반 네트워크/타일 오류 이벤트를 제공하지 않으므로 오프라인과 인증
실패 원인을 임의로 단정하지 않는다. 로드 후 연결 단절은 SDK 캐시/렌더링에 의존하며
지속적인 네트워크 가용성을 보장하지 않는다. 초기 실패 후 재확인은 화면을 다시 연다.
인증 설정 변경은 새 dart-define 빌드와 앱 재시작이 필요하다.

각 저장 구간은 별도 polyline, 한 점 구간은 marker, 빈 구간은 overlay 없음이다.
전체 좌표 bounds에 24dp 패딩을 적용한다. 모든 점이 같은 좌표면 해당 점을 zoom 16으로
표시한다. 구간 사이 연결, 보간, 위치 추정, 경로 보정은 없다. 화면의 시간/점 개수도
원본 기록을 사용한다. fallback에는 **저장된 좌표 윤곽 · 지도 아님**을 표시한다.

저장 경로를 보기 위한 현재 위치 요청/추적/내 위치 버튼은 없다. 지도 SDK에 렌더링에
필요한 좌표와 카메라 범위를 전달하지만 별도 업로드/검색/외부 저장 API는 추가하지 않는다.
SDK 자체의 타일 요청/캐시/진단 동작은 공급자 정책 범위이며 앱이 별도 보존을 보장하지 않는다.
삭제된 날짜는 부모 화면이 지도와 윤곽을 모두 제거한다. 경로 snapshot이 바뀌면 native
map을 새로 만들며 dispose 후 콜백/overlay 완료가 새 카메라나 화면을 갱신하지 않는다.

## 직접 검증과 장애 확인

키 없이 기록 상세를 열면 설정 없음과 윤곽만 표시되고 권한 팝업이 없어야 한다.
유효 키로는 저장된 두 구간 사이가 연결되지 않는지, 단일 점의 marker, 패딩/로고를
확인한다. 비행기 모드에서 최초 로드 실패 안내, 날짜 삭제 후 지도 제거, 뒤로 이동 중
콜백 오류가 없는지 확인한다. 장애 시 Client ID 주입 → 선택한 앱 식별자와 NCP 등록 →
네트워크/사용량/인증 상태 → SDK 초기화 순으로 확인한다.

자동 검증은 `test/features/records/record_map_test.dart`와 기존 RoutePainter 테스트,
`integration_test/record_map_unconfigured_test.dart`를 사용한다. 네이티브 QA 하네스의
좌표는 명시적으로 표시한 합성 fixture이고 앱 사용자 데이터/저장 동작이 아니다.
유효한 키 없이 실타일 표시, 실인증 성공, 실제 개인 경로의 타일 정합성을 검증했다고
주장할 수 없다. 사람의 직접 검증과 운영 준비 판단은 별도다.

## 이번 실행 근거

- `fvm flutter pub get`: 종료 0, 지도 플러그인 1.4.4 추가. 기존 인증 패키지와
  로컬 Serverpod override를 보존했다.
- `fvm flutter test --no-pub test/features/records`: 20개 통과, 종료 0.
  기존 RoutePainter의 구간 수 검증과 삭제 테스트도 그대로 실행했다.
- `fvm flutter test --no-pub`: 237개 통과, 종료 0.
- `fvm flutter build apk --debug --flavor dev --no-pub`: 종료 0,
  `build/app/outputs/flutter-apk/app-dev-debug.apk` 생성. Flutter는 지도 플러그인
  1.4.4와 기존 flutter_web_auth_2의 Kotlin Gradle Plugin 사용에 대해 향후 호환성
  경고를 출력했다. 요청된 SDK 고정을 유지했으며 경고를 숨기지 않았다.
- 원래 한글 경로의 `fvm flutter analyze --no-pub`는 analysis server의
  `FormatException: Unterminated string`으로 종료 255였다. 짧은 ASCII 심볼릭 링크
  `/tmp/naver-map-audit/app`에서 `fvm dart analyze --fatal-infos`는 오류 없이 종료 0.
  포맷 검사도 8개 파일 0 changed로 종료 0. 도구 LSP fresh diagnostics는 이후 timeout이
  발생했으므로 최종 정적 검증 근거는 CLI 분석이다.
- iOS `--flavor prod` 최초 QA는 해당 scheme 부재로 종료 1. 기존 `dev` scheme으로
  `fvm flutter drive --no-pub --flavor dev -d 06C7AD47-C910-4D53-95C3-C1AD6283311B
  --driver=test_driver/record_map_driver.dart
  --target=integration_test/record_map_unconfigured_test.dart`는 빌드·실행 통과, 종료 0.
  초기화 생략과 native map 미구성, Flutter 예외 없음 및 320/768 폭의 캡처를 확인했다.
- 같은 native QA를 iPad Pro 13-inch (M5)
  `CF5BD8BD-5B37-40DA-A6B7-A2E03329C519`에서 실행해 종료 0으로 통과했다.
  최신 320/768dp 각각 light/dark 캡처 4개를 직접 열어 빈 UI/겹침/잘린 경로가
  없음을 확인했다. iPad 실행 로그에는 simulator ActionKit/Spotlight의 타 앱 확장
  검색 경고가 있었지만 Flutter 테스트는 모두 통과했다.
- 캡처는 `/tmp/naver-map-audit/map-screenshots/`에 있다. 작은 폭과 큰 폭 모두
  설정 없음 안내, 지도 아님 라벨, 분리된 좌표 윤곽과 삭제 버튼의 접근을 확인한다.
  밝기 환경을 light/dark로 각각 주입했지만 기존 앱 테마는 light 고정이므로 색상은 같다.
  하네스 바깥 검정 영역은 제한 폭 바깥의 테스트 viewport이며 실제 앱 UI가 아니다.
