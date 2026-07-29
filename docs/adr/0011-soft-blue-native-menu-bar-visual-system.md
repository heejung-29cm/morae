# ADR-0011: 소프트 블루 기반 네이티브 메뉴 막대 시각 체계

- 상태: Accepted
- 날짜: 2026-07-29

## Context

Sprint 1에서 메뉴 막대 할 일 기능을 구현한 뒤 패널의 시각 밀도, drag/reorder 발견 가능성, dark mode와 modal 상호작용을 정리할 필요가 생겼습니다. 참고 디자인은 소프트 블루, 더스티 핑크와 머스터드 옐로 변형을 제공하며 HTML/CSS로 작성되어 있습니다.

`MenuBarExtra(.window)`는 일반 앱 window와 수명 주기가 다릅니다. 시스템 sheet나 alert가 별도 포커스를 얻으면 메뉴 패널이 닫혀 첫 클릭이 전달되지 않을 수 있습니다. 참고 디자인을 그대로 WebView로 포함하면 native control, keyboard, VoiceOver와 앱의 SwiftUI 구조를 잃게 됩니다.

## Decision

- Morae의 기본 accent는 소프트 블루로 정합니다.
- 라이트·다크 변형은 Asset Catalog의 semantic color set으로 관리합니다.
- 참고 색상의 목표값은 light `oklch(0.575 0.105 252)`, dark `oklch(0.685 0.095 252)`로 두고 구현 시 macOS 색상 프로파일에 맞는 sRGB 또는 Display P3 값으로 변환합니다.
- 본문, secondary text, separator, material과 destructive state는 macOS semantic color와 SwiftUI material을 우선 사용합니다.
- 패널, section header, TodoRow, drag handle, inline editor와 feedback view를 재사용 가능한 SwiftUI 컴포넌트로 구성합니다.
- pending Todo의 전용 drag handle과 insertion indicator에 accent를 사용합니다.
- drag와 동등한 keyboard 이동 action을 유지합니다.
- 편집과 삭제 확인은 메뉴 패널 내부 inline UI로 표시하고 시스템 sheet/alert를 사용하지 않습니다.
- 참고 HTML은 설계 입력으로만 사용하며 WebView, JavaScript와 CSS runtime을 앱에 포함하지 않습니다.
- footer에는 실제 구현된 상태와 action만 표시합니다.

## Consequences

### Positive

- 소프트 블루를 일관된 브랜드 accent로 사용할 수 있습니다.
- macOS light/dark, 접근성 설정과 native focus 동작을 유지할 수 있습니다.
- 아티클과 에이전트 section이 추가될 때 같은 component와 token을 재사용할 수 있습니다.
- 메뉴 패널이 modal 포커스로 닫히는 기존 상호작용 문제를 예방합니다.
- drag와 keyboard 사용자가 같은 reorder 기능을 이용할 수 있습니다.

### Negative

- HTML 디자인과 픽셀 단위로 완전히 동일하지 않을 수 있습니다.
- Asset Catalog 색상 변환과 light/dark 대비를 별도로 검증해야 합니다.
- inline 편집 UI가 패널의 세로 공간을 사용하므로 ScrollView와 focus 위치를 세심하게 관리해야 합니다.
- 사용자별 accent 선택은 제공하지 않습니다.

## Alternatives

- 머스터드 옐로: 제품명과 의미적으로 어울리지만 사용자가 소프트 블루를 기본 accent로 선택해 제외했습니다.
- 더스티 핑크: 차별화되지만 기본 업무 도구의 중립적인 인상에는 소프트 블루가 더 적합하다고 판단했습니다.
- macOS 시스템 accent만 사용: 사용자 환경과 잘 어울리지만 Morae의 일관된 기본 시각 정체성을 보장하지 못해 제외했습니다.
- HTML을 WebView로 포함: 참고 디자인 재현은 쉽지만 native accessibility, focus와 SwiftUI 상태 구조를 잃으므로 제외했습니다.
- 시스템 sheet/alert 유지: 일반 window에는 자연스럽지만 `MenuBarExtra(.window)`에서 패널 종료와 클릭 유실이 재현되어 제외했습니다.

