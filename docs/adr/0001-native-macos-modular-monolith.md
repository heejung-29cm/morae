# ADR-0001: 네이티브 macOS 모듈형 모놀리스와 개인용 배포

- 상태: Accepted (배포와 저장 위치는 ADR-0009로 개정)
- 날짜: 2026-07-28
- 개정: 2026-07-29

## Context

모래는 메뉴 막대, macOS 알림, 로그인 항목과 향후 WidgetKit을 자연스럽게 사용해야 합니다. Codex `notify`와 Claude Code Hook은 앱 번들 안의 실행 파일을 직접 호출합니다. MVP에는 계정, 서버, 팀 기능이 없으며 한 사용자 Mac 안에서 모든 핵심 기능이 동작합니다.

## Decision

- Swift와 SwiftUI로 네이티브 macOS 앱을 구현합니다.
- MVP는 단일 앱 프로세스 안에서 Presentation, Application, Domain, Infrastructure 경계를 둔 모듈형 모놀리스로 구성합니다.
- 하나의 Xcode 프로젝트에 `MoraeApp`, `HamsterEventCLI`, `MoraeCore` 세 타깃을 둡니다.
- `MoraeCore`에는 도메인 모델, IPC envelope와 공통 오류를 두고 App과 CLI가 함께 사용합니다.
- `HamsterEventCLI`은 GRDB와 FeedKit에 의존하지 않습니다.
- 일회성 이벤트 전달 실행 파일 `hamster-event`를 같은 `.app` 번들에 포함합니다.
- 본인 전용 DMG에는 로컬 실행용 서명(`Sign to Run Locally` 또는 ad-hoc)을 사용합니다.
- Developer ID 서명과 공증은 MVP에서 사용하지 않습니다.
- Mac App Store와 App Sandbox는 MVP 배포 대상에서 제외합니다.
- 사용자 Application Support 디렉터리와 표준 `UserDefaults`를 사용합니다.
- 공개 배포나 WidgetKit이 필요해지면 [ADR-0009](0009-personal-dmg-and-local-storage.md)에 따라 서명·공증, App Group과 데이터 이전을 다시 결정합니다.

## Consequences

### Positive

- macOS 기능을 가장 작은 통합 비용으로 사용할 수 있습니다.
- 별도 서버와 런타임 설치가 필요 없습니다.
- 로컬 데이터 흐름과 권한 경계가 단순합니다.
- 기능별 경계를 유지하면서도 MVP 배포 단위는 하나입니다.
- 앱과 CLI가 IPC 계약을 컴파일 시점에 공유할 수 있습니다.

### Negative

- macOS 외 플랫폼을 지원하지 않습니다.
- 앱 업데이트와 배포 채널을 직접 운영해야 합니다.
- 타인에게 전달할 경우 Gatekeeper 경고 없는 설치 경험을 보장하지 않습니다.
- 사용자가 앱을 이동하면 외부 도구에 설정한 `hamster-event` 절대 경로가 달라질 수 있습니다.
- App Sandbox가 제공하는 추가 격리를 사용하지 않습니다.
- 기능 경계가 Xcode 타깃 경계와 모두 일치하지 않으므로 의존성 규칙을 코드 리뷰와 테스트로 유지해야 합니다.

## Alternatives

- Electron/Tauri: macOS 전용 API와 위젯 통합 비용 때문에 선택하지 않았습니다.
- 클라이언트·서버 분리: MVP에 계정과 동기화 요구가 없어 선택하지 않았습니다.
- 여러 local Swift Package: 경계는 더 강하지만 MVP의 프로젝트·서명 구성이 늘어나므로 선택하지 않았습니다.
- Mac App Store: 외부 도구가 앱 번들 실행 파일을 호출하는 구조와 Sandbox 제약 때문에 선택하지 않았습니다.
