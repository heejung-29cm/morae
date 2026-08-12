# 모래 Sprint 1.5 — 메뉴 막대 UI Polish

> 상태: Implemented — automated verification complete
> 작성: 2026-07-29  
> 최종 수정: 2026-07-30
> 선행: Sprint 1 완료  
> 후속: Sprint 2  
> 관련 결정: [ADR-0011](adr/0011-soft-blue-native-menu-bar-visual-system.md)
> 직접 확인: [Sprint 1.5 데모 체크리스트](SPRINT_1_5_DEMO_CHECKLIST.md)

## 1. 목적

Sprint 1에서 검증한 할 일 관리 흐름을 유지하면서 메뉴 막대 패널의 정보 밀도, 시각적 위계, drag/reorder 피드백과 키보드 접근성을 정리합니다. Sprint 2 이후 아티클과 에이전트 기능이 같은 화면에 추가되어도 재사용할 수 있는 SwiftUI 컴포넌트와 semantic color 기반을 만드는 것이 목표입니다.

참고 디자인:

- `모래 패널.dc.html`: 패널 구조, 할 일 row, 전용 drag handle과 drop indicator
- `모래 메뉴바 패널.dc.html`: 소프트 블루를 포함한 라이트·다크 색상 변형
- 현재 Morae 메뉴 막대 화면 스크린샷: 실제 native control 크기와 동작 비교

외부 참고 파일은 구현 입력일 뿐 런타임 또는 빌드 의존성으로 추가하지 않습니다. 필요한 규칙과 완료 기준은 이 문서와 ADR에 기록합니다.

## 2. 확정 방향

### 2.1 시각 체계

- 기본 accent는 소프트 블루입니다.
- 라이트 기준 토큰 목표는 `oklch(0.575 0.105 252)`, 다크 기준은 `oklch(0.685 0.095 252)`입니다.
- 실제 SwiftUI 구현은 Asset Catalog의 `MoraeAccent` light/dark color set으로 변환하고 macOS 색상 프로파일에서 육안 및 대비를 확인합니다.
- 본문, 보조 텍스트, separator와 오류 색상은 가능한 한 macOS semantic color를 사용합니다.
- 패널 배경은 SwiftUI material을 사용하고 HTML의 CSS blur, shadow와 OKLCH 렌더러를 도입하지 않습니다.
- 사용자 accent 선택 기능은 MVP 범위에 포함하지 않습니다.

### 2.2 패널 구조

- 패널 폭은 392pt를 기준으로 합니다.
- 높이는 최대 700pt 안에서 내용에 맞추고, 초과 내용은 기존 ScrollView 안에서 표시합니다.
- header는 제품명·지역화된 날짜, 아티클 추천받기 버튼, 설정 버튼 순서로 유지합니다.
- section 제목은 compact hierarchy를 사용하고 가능한 section에는 우측에 항목 개수를 표시합니다.
- 아직 구현되지 않은 동기화 시각과 전역 단축키는 footer에 가짜 값으로 표시하지 않습니다.

### 2.3 할 일 상호작용

- pending row에만 전용 6-dot drag affordance를 표시합니다.
- pending 행에서 3pt 이상 이동하면 로컬 pointer drag를 시작합니다. 일반
  버튼 click은 reorder로 처리하지 않습니다.
- drag 중 원본 row의 opacity를 낮추고 대상 위치에 2pt 소프트 블루 insertion line을 표시합니다.
- mouse-up에서 유효한 위치가 확정될 때만 기존 `TodoRepository.reorder`를
  한 번 호출합니다.
- 위·아래 이동 버튼 또는 동등한 keyboard action을 유지해 drag가 유일한 조작법이 되지 않게 합니다.
- 완료 항목은 drag 대상에서 제외하고 muted text와 취소선으로 상태를 함께 표현합니다.
- 편집과 삭제 확인은 `MenuBarExtra(.window)` 내부 inline UI로 유지합니다. 시스템 sheet/alert로 되돌리지 않습니다.
- 삭제 실행 취소 5초 정책과 기존 DB 즉시 삭제 동작은 변경하지 않습니다.

## 3. 범위

포함:

- soft-blue semantic design token과 다크 모드
- 패널·header·section layout 정리
- compact todo row와 hover/focus 상태
- 전용 drag handle과 drop indicator
- inline 편집·삭제·undo 시각 정리
- empty/error/validation 상태 통일
- keyboard, VoiceOver label, 긴 한국어·영문 제목 검증

제외:

- Article, Briefing, Agent의 실제 데이터 연결
- 피드 네트워크, DB schema 또는 repository 계약 변경
- 설정 화면에서 theme/accent 선택
- 마스코트와 애니메이션
- 가짜 동기화 시각, 아직 등록되지 않은 전역 단축키
- WebView 또는 HTML/CSS 런타임 포함

## 4. Task

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S1.5-01 | XS | Soft-blue semantic token 구성 | S1-12 | `MoraeAccent` light/dark asset과 foreground/background token을 추가하고 light/dark에서 control 상태를 구분할 수 있습니다. |
| S1.5-02 | S | 패널·header·section hierarchy 정리 | S1.5-01 | 392pt 패널, compact header, 지역화 날짜, hairline separator와 section count가 작은 화면의 ScrollView 안에서 잘리지 않습니다. |
| S1.5-03 | S | Compact TodoRow 컴포넌트 분리 | S1.5-01 | checkbox, 중요도, 제목, 예상 시간과 action 영역이 재사용 컴포넌트로 분리되고 긴 제목·완료 상태가 안정적으로 배치됩니다. |
| S1.5-04 | M | drag affordance와 insertion indicator 구현 | S1.5-03 | pending 행의 로컬 pointer drag가 반투명 preview와 insertion line을 표시하며 확정 gesture당 reorder transaction이 한 번 실행됩니다. |
| S1.5-05 | S | Inline 편집·삭제·undo panel 정리 | S1.5-03 | 저장·취소·삭제·undo 버튼 클릭 중 메뉴 패널이 닫히지 않고 focus가 해당 inline 영역 안에서 예측 가능하게 이동합니다. |
| S1.5-06 | S | Empty·error·validation 상태 통일 | S1.5-02, S1.5-03 | 네 section의 empty state, startup 오류와 Todo validation이 공통 padding, icon, 색상 및 VoiceOver 문구를 사용합니다. |
| S1.5-07 | S | Light/dark·keyboard·회귀 검증 | S1.5-04, S1.5-05, S1.5-06 | light/dark screenshot checklist, keyboard-only 주요 흐름, VoiceOver label과 기존 Sprint 1 테스트가 모두 통과합니다. |

## 5. 구현 순서

1. 색상과 spacing token을 먼저 정의합니다.
2. 패널 shell과 section header를 정리합니다.
3. TodoRow를 분리하되 기존 ViewModel·repository 동작은 변경하지 않습니다.
4. 로컬 pointer drag presentation과 keyboard 대안을 TodoRow 위에 연결합니다.
5. inline editor, delete confirmation과 undo banner를 같은 visual language로 맞춥니다.
6. 모든 empty/error 상태를 통일합니다.
7. light/dark 및 interaction regression을 수행합니다.

## 6. Sprint 종료 데모

- light/dark 모드 모두에서 소프트 블루가 기본 accent로 표시됩니다.
- 빠른 추가, 완료 전환, 편집, 삭제 확인과 undo 중 패널이 닫히지 않습니다.
- pending 행을 3pt 이상 끌면 insertion line이 나타나고 mouse-up 후 순서가 재실행 뒤에도 유지됩니다.
- 체크·편집·삭제 버튼을 일반 클릭하면 해당 action만 실행됩니다.
- keyboard만으로 추가, 완료 전환, 순서 이동, 편집 저장·취소와 삭제 확인을 수행할 수 있습니다.
- 긴 제목, 빈 목록, validation 오류와 startup 오류가 392pt 패널 안에서 잘리지 않습니다.

## 7. 검증 전략

- 기존 repository, ViewModel과 Sprint 1 인수 테스트를 회귀 실행합니다.
- 재정렬 계획은 UI에서 분리해 source/target/end/no-op 경계를 단위 테스트합니다.
- reorder 저장 호출 횟수를 Stub repository로 검증합니다.
- Xcode에서 light/dark appearance별 실제 `MenuBarExtra`를 수동 점검합니다.
- VoiceOver label은 상태와 action을 색상 없이 이해할 수 있는지 확인합니다.
- 시스템 sheet/alert가 메뉴 패널에 다시 추가되지 않았는지 코드 리뷰에서 확인합니다.

## 8. 구현 결과

- `MoraeAccent` Asset Catalog에 light/dark 소프트 블루를 추가했습니다.
- 392pt native material 패널, compact header와 section count를 적용했습니다.
- `TodoRowView`, `TodoInlinePanels`, `MenuBarStateView`로 화면 요소를 분리했습니다.
- pending 전용 6-dot affordance, 반투명 preview, insertion indicator와 keyboard·VoiceOver 이동 action을 추가했습니다.
- 시스템 `onDrop` 대신 named coordinate space의 row frame과 `DragGesture`를
  사용하며, 의미 없는 위치를 제외하고 확정 gesture당 repository
  reorder가 한 번 호출되는지 테스트합니다.
- 시스템 sheet/alert 없이 inline 편집·삭제·undo 흐름을 유지합니다.
- macOS Debug build와 전체 scheme 자동화 테스트 41개가 통과했습니다 (`MoraeApp` 31개, `MoraeCore` 9개, `HamsterEventCLI` 1개).
- 자동화 테스트와 사용자의 실제 `MenuBarExtra` 점검 범위는 [데모 체크리스트](SPRINT_1_5_DEMO_CHECKLIST.md)로 구분합니다.
