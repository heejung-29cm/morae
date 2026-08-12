# ADR-0016: 읽기 전용 Jira Cloud 날짜별 할 일 가져오기

- 상태: Accepted
- 날짜: 2026-07-31

## Context

사용자는 Jira에서 자신에게 할당된 현재 작업을 모래의 오늘 할 일에 자동
반영하려고 합니다. 단순히 오늘 기한인 이슈만 조회하면 이미 진행 중인
작업과 시작일이 지났지만 아직 완료되지 않은 작업을 놓칩니다.

모래의 Todo는 LocalDay별 기록입니다. 하나의 Jira 이슈는 여러 날에 걸쳐
진행될 수 있고, 사용자가 모래에서 오늘 작업 완료로 표시하더라도 Jira
이슈 전체는 아직 In Progress일 수 있습니다. Jira와 로컬 완료 상태를
양방향 동기화하면 두 시스템의 완료 의미가 충돌합니다.

회사는 Jira Cloud에 커스텀 화면 도메인을 사용합니다. 확인된
`serverInfo`에서 화면 URL과 기본 `*.atlassian.net` API URL이 서로
다릅니다. 일반 API 토큰을 커스텀 화면 도메인에 보내면 401이 발생하고
기본 API URL에서는 인증됩니다. 실제 회사 host는 코드와 공유 문서에
상수로 고정하지 않습니다.

## Decision

- Jira는 원본, 모래는 읽기 전용 날짜별 작업 화면으로 둡니다.
- 모래는 Jira에 생성·수정·상태 변경 요청을 보내지 않습니다.
- 후보는 현재 사용자 할당, Done 아님을 기본으로 다음 OR 조건을
  적용합니다.
  - status category가 In Progress
  - 시작 날짜가 오늘 또는 과거
  - due date가 오늘 또는 과거
- Jira profile time zone 함수 대신 모래의 LocalDay를 명시적
  `yyyy-MM-dd` JQL literal로 사용합니다.
- 시작 날짜는 field metadata에서 검색 가능한 date custom field ID를
  찾고 JQL에는 `cf[ID]`를 사용합니다.
- API 요청은 `serverInfo.baseUrl`, 사용자 링크는
  `serverInfo.displayUrl`을 사용합니다.
- 초기 내부 프로토타입은 Atlassian 이메일과 일반 API 토큰을 사용하며
  토큰은 macOS Keychain에만 저장합니다.
- 자동 동기화는 연결된 경우 앱 시작과 LocalDay 변경에 요청하되 날짜당
  최대 한 번만 실행합니다.
- 자동 재시도는 하지 않습니다. 사용자가 누른 수동 동기화는 새로운
  명시적 실행으로 허용합니다.
- `(LocalDay, provider, Jira issue ID)`를 DB unique key로 사용합니다.
- 같은 날짜 upsert는 Jira metadata를 갱신하되 로컬 완료와 순서를
  덮어쓰지 않습니다.
- 다음 날짜에도 Jira 후보이면 새 LocalDay의 Todo를 생성합니다.
- 검색 결과에서 사라졌다는 이유로 기존 Todo를 삭제하거나 완료하지
  않습니다.
- 사용자가 Jira Todo를 직접 삭제하면 `(LocalDay, Jira issue ID)`
  dismissal을 저장해 같은 날 다시 가져오지 않습니다. 실행 취소하면
  dismissal도 제거하며, 다음 LocalDay의 자동 생성에는 영향을 주지
  않습니다.
- Jira Todo는 자동으로 다음 날짜에 재평가하므로 수동 carry-over
  후보에서 제외합니다.

상세 계약은 [Jira 연동 설계](../JIRA_INTEGRATION_DESIGN.md)를 따릅니다.

## Consequences

### Positive

- 진행 중, 시작일 경과와 기한 초과 작업을 한 화면에서 놓치지 않습니다.
- 오늘 한 작업과 Jira 이슈 전체 완료의 의미를 분리할 수 있습니다.
- 같은 날 반복 실행과 앱 재시작에도 중복 항목이 생기지 않습니다.
- Jira 권한 또는 검색 오류가 로컬 기록의 삭제로 이어지지 않습니다.
- OAuth로 전환해도 query와 import 도메인은 유지할 수 있습니다.

### Negative

- 모래에서 완료해도 Jira 상태는 바뀌지 않습니다.
- Jira에서 Done으로 바뀐 오늘 항목은 로컬에 기록으로 남습니다.
- 시작 날짜 custom field가 없거나 모호하면 설정 또는 제한 동작이
  필요합니다.
- 일반 API 토큰은 내부 프로토타입에는 단순하지만 일반 배포형 앱의 최종
  인증 방식으로 적합하지 않습니다.
- Mac이 잠자기 중이거나 앱이 종료돼 있으면 동기화되지 않습니다.

## Distribution boundary

Atlassian은 배포형 앱이 사용자별 API 토큰을 수집하는 대신 하나의 OAuth
2.0 3LO 앱을 사용하도록 안내합니다. 따라서 일반 API 토큰 단계는 개인
또는 회사 승인 내부 프로토타입으로 제한합니다. 팀 전체나 외부에 일반
배포하기 전에는 회사 Jira 관리자 승인 또는 OAuth 2.0 3LO 전환을 별도
결정합니다.

## Alternatives

- due date가 오늘인 이슈만 가져오기: 단순하지만 장기 진행 및 시작일 경과
  작업을 놓칩니다.
- Jira 이슈당 로컬 Todo 하나만 유지: 날짜별 한 일 기록과 다음 날 계획
  모델에 맞지 않습니다.
- 모래 완료를 Jira Done으로 전송: 두 완료 의미가 다르고 쓰기 권한과
  오작동 위험이 커집니다.
- 검색 결과에 없는 기존 Todo 자동 삭제: 권한·field·일시 오류를 완료로
  오판할 수 있습니다.
- 시작일 field 이름을 JQL에 직접 사용: 같은 이름 field와 이름 변경에
  취약합니다.
- 처음부터 OAuth 2.0 3LO: 배포에는 적절하지만 현재 개인 내부 검증
  단계에는 callback과 앱 등록 범위가 큽니다.
