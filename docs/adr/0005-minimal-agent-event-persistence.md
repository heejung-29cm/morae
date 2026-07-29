# ADR-0005: 원본 에이전트 payload 비저장과 최소 필드 저장

- 상태: Accepted
- 날짜: 2026-07-28

## Context

Codex `notify`와 Claude Hook payload에는 사용자 입력, 마지막 응답, 프로젝트 경로, transcript 경로 등 민감할 수 있는 정보가 포함됩니다. 모래는 상태 표시와 알림을 위해 payload를 수신해야 하지만 전체 내용을 장기간 저장할 필요는 없습니다.

## Decision

- 원본 Hook/notify payload는 메모리에서 정규화한 뒤 폐기합니다.
- 기본 영구 저장 필드는 source, sessionId, turnId, sourceEvent, normalizedStatus, occurredAt, receivedAt으로 제한합니다.
- 전체 입력 메시지, 전체 마지막 응답, Claude transcript 경로, 원본 payload는 저장하지 않습니다.
- 프로젝트 경로, 작업 제목, 마지막 응답 일부는 각각 별도 opt-in 설정이 켜진 경우에만 저장합니다.
- 기본 macOS 알림은 에이전트 종류와 상태만 표시합니다.
- 에이전트 이벤트 내용은 외부 서비스로 전송하지 않습니다.
- 진단 로그에도 원문 메시지와 전체 경로를 기록하지 않습니다.

## Consequences

### Positive

- 로컬 DB나 로그가 노출됐을 때의 민감 정보 범위를 줄입니다.
- 개인정보 원칙이 구현 가능한 저장 필드 규칙으로 연결됩니다.
- 이벤트 저장소가 작고 단순해집니다.

### Negative

- 사용자가 opt-in하지 않으면 과거 이벤트만 보고 작업 내용을 자세히 복원할 수 없습니다.
- 원본 payload가 없어 사후 파서 버그 조사와 재처리가 제한됩니다.
- 상세 알림과 검색 기능은 사용자 설정 여부에 따라 품질 차이가 생깁니다.

## Alternatives

- 원본 payload 전체 저장: 디버깅은 쉽지만 개인정보 최소화 원칙과 맞지 않아 제외했습니다.
- 암호화 후 전체 저장: 키 관리와 복구 범위가 커지고 MVP 목적에 비해 복잡해 제외했습니다.
- 이벤트 자체를 저장하지 않음: 최근 기록과 미확인 상태 요구를 만족하지 못해 제외했습니다.
