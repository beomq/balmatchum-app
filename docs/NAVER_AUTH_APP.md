# 네이버 로그인 앱 연결

## 흐름

네이버 버튼 → 서버 isConfigured → 앱 메모리에서 보안 난수 PKCE 생성 →
beginLogin(S256 challenge) → 외부 인증 브라우저 → 정확한 callback/state 검사 →
completeLogin(code, state, verifier) → 기존 AuthSession.save 순서다.
Client Secret을 앱에 넣거나 프로필 이메일로 계정을 합치지 않는다.

`naver_login_browser.dart`는 네이버 고정 HTTPS authorize 주소와
redirect/state/S256 challenge를 확인한 뒤 브라우저를 연다.
callback의 주소·state가 다르거나 code/state가 중복되면 서버 교환을 하지 않는다.
`naver_auth_service.dart`는 중복 실행, 시도 만료, 로그인 중 계정 변경·provider 폐기를
검사한다. provider는 인증 변경 횟수를 사용해 로그인→로그아웃 뒤에도 늦은 응답을
저장하지 않는다. 서버 성공 뒤 로컬 저장 실패는 성공으로 보고하지 않는다.

브라우저 어댑터는 flutter_web_auth_2 5.1.0이다. 공식 태그 podspec의 iOS 최소 버전은
11이며 앱의 기존 15 설정을 변경하지 않았다. 인증 서버 기능과 별도로 외부
브라우저를 열고 콜백을 받는 역할만 한다.

## 콜백과 외부 설정

- dev: `com.beomq.balmatchum.dev://naver/callback`
- prod: `com.beomq.balmatchum://naver/callback`

앱 flavor에서 정한 URI와 서버 응답 URI가 정확히 같아야 한다. Android CallbackActivity는
applicationId scheme, naver host, /callback path만 받는다.
iOS는 ASWebAuthenticationSession의 custom callback scheme을 사용한다.
현재 앱 어댑터는 HTTPS app/universal links를 지원한다고 주장하지 않는다.

위 URI는 로컬 코드 계약이며 네이버 콘솔 등록이나 외부 로그인 성공 증거가 아니다.
실제 등록에서 URI 허용 여부·콜백 동작을 확인해야 한다. 제한이 있으면 HTTPS bridge/
app link 계약을 별도 구현해야 하며 임의 리다이렉트를 허용하는 것으로 우회하지 않는다.

## 검증

2026-10-21:
- 브라우저/PKCE 13개 테스트와 해당 두 파일 분석 종료 0.
- 초기 서비스 연결을 포함한 인증 회귀 74개와 전체 Dart 분석 종료 0.
- 그 뒤 인증 변경 횟수 방어와 서버 검증 중 계정 변경 테스트를 추가했다.
  최신 전체 회귀 368개, 전체 fatal-infos 분석, 6개 파일 포맷 검사가 통과했다.
  Android dev debug APK 빌드도 종료 0으로 통과했다.
- iOS 미설정 로그인 화면은 Xcode build 32.2초, 네이티브 테스트 1개 통과, 종료 0.
  Google/Apple/Naver 미설정 거절·인증 없음·버튼 재시도 가능 상태를 확인했다.
  실제 SignInScreen과 실제 provider를 직접 조립했으며 prod 시작 라우트 검증은 아니다.
- 최초 iOS 실행은 dev flavor의 체험 시작 화면을 로그인 화면으로 가정해 실패했다.
  dev 라우팅을 바꾸거나 assertion을 삭제하지 않고 테스트 조립 경계를 수정했다.
- 실제 네이버 OAuth, 콘솔 설정, iOS 브라우저 전환, 실제 서버와 앱의 네이버 로그인
  통합은 아직 검증하지 않았다. 테스트 주입 콜백을 실제 로그인으로 보고하지 않는다.

장애 시 server configuration → flavor별 callback → state/attempt 만료 →
PKCE/서버 LoginException → 현재 인증 수명 → 로컬 세션 저장 순서로 확인한다.
code/verifier/원본 토큰을 로그에 남기지 않는다. 로그인 시도가 실패하면 새로운
시도로 시작하며 이전 코드를 임의 재전송하지 않는다.
