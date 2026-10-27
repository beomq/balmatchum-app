# Dev 첫 만남 디자인 구현 기준

동결 Pen SHA: `1755f3514afb45c04308a841a6bfa5dc97422b735299fff268d40fc5bb84ebf3`.
`setup/first-meeting-contract-20261013.md`와 디자인 handoff가 이전 DESIGN.md보다 우선한다.
새 디자인·이미지 생성 없이 실제 Pen의 JSON geometry/copy/tokens를 따른다.

## 토큰

surface #FFF4E3, raised #FFFFFF, ink #50301E, muted #77614E, line #DECCB3,
primary #8A6941, strong #654126, soft #F1E3CA, pressed #F0E8DA,
record #637348, record-soft #EBEEDA. 간격4/8/12/16/20/24/32,
control radius12, panel16, touch 최소44. CTA 최소48, input52.

## 구조와 기준 프레임

Zjwm6 로그인: brand140, 소셜48/간격12, 카카오·네이버·Apple·Google 순서.
YOaF2: back48, heading, 직접/추천132 카드와48 아이콘, 정책 panel.
cP8p1: candidate280/contain220×240, 안내, primary/secondary48.
XfVXu: 이름 input52, 성별120 카드/32 아이콘, 선택2px+선택됨, 선택품종 panel.
C7IGJ: 기본5000 목표와 완료 CTA. KgBb1: scene330 cover background/contain dog,
오늘 걸음 panel184는 실제 — 표시, 기록/보상/기타는 미구현 안내만 한다.

## 반응형·접근성

SafeArea 안 폭 기준 <360 패딩12, <600 패딩16, <840 패딩24, 그 이상32.
온보딩 form max480, catalog max960, home medium max600. catalog 최신 Pen180 카드
기준이며 모바일2열,768에서 사용 가능 폭에 따라 열 수를 계산한다.
각 화면 하나의 세로 scroll이 키보드/큰 글자/짧은 높이에서 CTA까지 접근시킨다.
Scaffold가 keyboard inset을 처리하며 중복 bottom inset 없음. 텍스트 배율 제한 없음.
네비게이션은 뒤로만, 온보딩 home 우회 없음. 홈에도 하단 탭 없음.

## 공통 요소와 상태

back header, title/description, primary/secondary action, outlined field, selection card,
notice panel, dog image를 재사용한다. 선택은 색+border+문구, 저장 중 중복 행동 금지,
오류는 입력 유지+재시도. 동작을 줄이기 위한 fake auth/provider 없음.

## 폰트 및 알려진 검증 항목

Pen 자체 폰트 import 미완료라는 handoff를 보존한다. 앱은 로컬 변환본 대신 아래
공식 upstream TTF를 수정 없이 가져오고 기존 OFL1.1 사본을 포함했다.
Pretendard는 UI theme, Galmuri11은 홈 말풍선에 등록했다. 실제 native 캡처에서
Galmuri 픽셀 글리프를 확인했다. 320/390/768,1.3/2.0,키보드 render가 필요하다.

- https://raw.githubusercontent.com/orioncactus/pretendard/main/packages/pretendard/dist/public/variable/PretendardVariable.ttf
  SHA256 `3090ccde0442bb347aa7685d9ba8b17436a60682df6e8f92a9a670de14056e22`
- https://raw.githubusercontent.com/quiple/galmuri/main/dist/Galmuri11.ttf
  SHA256 `e24256f42e43713d2ea086a1e1669d78b968f5b3cc547e5c157f0606ffa5def1`
미세 animation이나 새 시각 효과를 만들지 않는다. Web/React/Lighthouse 규칙은 native
Flutter 검증을 대신하지 않으며 현재 Pen 비주얼을 변경할 근거로 쓰지 않는다.

## 인증 프로필 설정

인증 후에도 동일 MeetingPage, home scene, 폰트와 토큰을 사용한다. 홈 설정 아이콘은
기존 Material bottom sheet로 이름·목표 입력과 저장, 로그아웃을 제공한다. 각 입력은
기존 outlined field, 저장은 primary48, 로그아웃·재시도는 secondary48이다.
키보드 inset을 포함한 단일 scroll로 작은 높이와 큰 글자에서도 접근 가능하게 한다.
요청 중과 결과 미확정 시 편집을 잠그고 원본 요청 재시도만 제공한다. revision 충돌은
최신 서버 값을 표시하고 입력을 보존해 사용자가 검토 후 다시 저장한다. 계정 프로필은
Dev 체험 초기화로 삭제하지 않으며 삭제 동작은 제공하지 않는다.

## 인증 퀴즈

기존 ProductPage의 SafeArea·단일 scroll·최대640과 Space 간격을 사용한다.
무료 문제, 조건, 선택지, 제출 결과, 추가 문제 순서다. 정오답은 문구로도 표시하며
기존 지급 기록과 재전송·복습의 추가 지급 없음을 구분한다. 응답 미확정 상태는
입력과 신규 광고를 잠그고 같은 요청 확인만 제공한다. 광고 시트는 기존 AdsSheet를
재사용하고 검증 후 별도 추가 문제 열기를 제공한다. 이력과 복습은 한 페이지에서
전환하고 assignment ID 커서로 더 보기를 제공한다. 출처 URL은 선택·복사 가능하다.
새 토큰·애니메이션은 추가하지 않는다. 유료 혜택은 기존 outlined 확인 버튼과
명시적 primary 수령/추가 문제 열기 버튼을 사용한다. 미확인·비활성·조회 실패를
구분하며 오류를 구매 없음으로 표시하지 않는다. 무료·광고·유료는 같은 busy gate를
공유하고 응답 유실 시 원본 요청 확인만 허용한다. 자동 구매나 자동 수령은 없다.
