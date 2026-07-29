# ADR-0004: 에이전트 턴 식별과 상태 정규화

- 상태: Accepted
- 날짜: 2026-07-29

## Context

Codex와 Claude Code는 서로 다른 이벤트 이름과 식별자를 제공합니다. Codex `notify`에는 `thread-id`와 `turn-id`가 있고, Claude Code 2.1.196 이상의 Hook 공통 입력에는 사용자 프롬프트 UUID인 `prompt_id`가 있습니다. 하나의 세션에는 여러 턴이 있으므로 `sessionId`만 저장하면 서로 다른 작업이 합쳐집니다.

## Decision

- 공통 식별자는 `(source, sessionId, turnId)`로 정의하고 고유 제약을 둡니다.
- Codex는 원본 `thread-id`를 `sessionId`, `turn-id`를 `turnId`로 사용합니다.
- Claude는 Hook의 `prompt_id`를 `turnId`로 사용합니다.
- `prompt_id`가 없는 구버전 이벤트는 같은 `sessionId`의 최신 열린 턴에 연결하고, 열린 턴도 없으면 UUID를 생성합니다.
- `agent_needs_input`까지 수신하는 전체 Hook 기능의 최소 호환 버전은 Claude Code 2.1.198로 안내합니다.
- Claude `Stop` 또는 `StopFailure` 수신 시 턴을 닫습니다.
- 기본 상태 매핑은 다음과 같습니다.

| Source event | Normalized status |
| --- | --- |
| Codex `agent-turn-complete` | `responded` |
| Claude `Notification`의 `permission_prompt`, `elicitation_dialog`, `agent_needs_input` | `attention_required` |
| Claude `Stop` | `responded` |
| Claude `TaskCompleted` | `completed` |
| Claude `StopFailure` | `failed` |

- 상태 우선순위는 `failed > completed > responded > attention_required`로 둡니다.
- `TaskCompleted` 뒤의 `Stop`은 `completed` 상태를 낮추지 않고 중복 종료 알림도 만들지 않습니다.

## Consequences

### Positive

- 같은 세션의 여러 턴을 독립적으로 저장할 수 있습니다.
- 외부 도구 차이를 도메인 모델 밖으로 격리합니다.
- `responded`와 실제 `completed`를 UI에서 구분할 수 있습니다.

### Negative

- `prompt_id`가 없는 Claude Code 구버전에서는 모래가 만든 UUID를 사용하므로 외부 기록과 직접 대조하기 어렵습니다.
- `prompt_id`가 없고 앱이 중간에 종료되면 열린 턴 연결 정보가 사라질 수 있으며, 후속 Hook은 새 폴백 턴으로 기록됩니다.
- Claude `TaskCompleted`는 전체 사용자 목표가 아니라 Claude 내부 업무 단위 완료일 수 있습니다.

## Alternatives

- `sessionId`만 사용: 여러 턴이 합쳐지므로 제외했습니다.
- 모든 Claude 턴에 UUID 생성: 공식 `prompt_id`와 외부 진단 정보를 활용하지 못하므로 제외했습니다.
- 종료 이벤트마다 UUID 생성: 같은 턴의 Notification, TaskCompleted, Stop을 연결할 수 없어 제외했습니다.
- 대화 transcript 파싱: 개인정보와 구현 복잡성 때문에 제외했습니다.
