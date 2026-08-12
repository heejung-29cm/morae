# ADR-0017: 사용자 동작 기반 에이전트 Hook 안전 자동 설정

- 상태: Accepted
- 날짜: 2026-07-31

## Context

개인용 DMG를 다른 사용자에게 전달하면 앱 번들 경로, Codex TOML 편집,
Claude JSON 병합을 각 사용자가 직접 처리해야 했습니다. 앱을 DMG에서
실행하거나 나중에 이동하면 번들 안 helper의 절대 경로도 깨질 수 있습니다.
또한 Codex `notify`는 하나의 명령 배열이므로 기존 알림 도구를 단순히
덮어쓰면 안 됩니다.

## Decision

- 자동 설정은 사용자가 설정 화면의 버튼을 누를 때만 실행합니다.
- 번들 helper를
  `~/Library/Application Support/Morae/bin/hamster-event`에 설치하고
  외부 설정은 이 안정적인 경로를 사용합니다.
- `~/.codex/config.toml`과 `~/.claude/settings.json`은 변경 전에 같은
  디렉터리의 `*.morae-backup`에 최초 원본을 한 번 백업합니다.
- Codex는 root의 단일 행 string array `notify`만 자동 처리합니다.
  기존 명령이 있으면 base64 JSON argv를 helper relay에 보관하고 Codex가
  전달한 JSON payload를 모래와 기존 명령 양쪽에 전달합니다.
- Claude는 기존 최상위 key와 다른 hook handler를 보존하고 모래가 관리하는
  command handler만 제거·재등록해 반복 실행을 멱등하게 만듭니다.
- 해석할 수 없는 TOML, 잘못된 JSON, 예상하지 못한 hooks 자료형은 수정하지
  않고 오류와 직접 설정 스니펫을 표시합니다.
- helper와 hook은 기존 best-effort 계약대로 에이전트 실행을 실패시키지
  않습니다.

## Consequences

- 다른 사용자가 파일을 직접 편집하지 않고도 Codex와 Claude를 연결할 수
  있고 앱 이동 후에도 helper 경로가 유지됩니다.
- 기존 Codex notify와 Claude hook을 보존합니다.
- 지원하지 않는 복잡한 TOML notify는 여전히 직접 설정이 필요합니다.
- 앱 삭제만으로 Application Support helper와 외부 설정이 자동 제거되지는
  않습니다. 연결 해제 기능은 후속 개선 범위입니다.

## Supersedes

Sprint 6의 “외부 설정 파일을 자동 수정하지 않는다”는 초기 안전 경계를
대체합니다. 명시적 사용자 동작, 백업, 보수적 파싱, 실패 시 무수정 원칙을
추가한 뒤 자동 설정을 허용합니다.
