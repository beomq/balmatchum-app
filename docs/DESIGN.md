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
