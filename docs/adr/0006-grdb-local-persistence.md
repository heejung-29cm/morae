# ADR-0006: GRDB 기반 SQLite 영구 저장

- 상태: Accepted
- 날짜: 2026-07-28
- 개정: 2026-07-29

## Context

모래는 Task, Article, BriefingRun, AgentRun, AgentEvent를 로컬에 저장해야 합니다. 데이터에는 고유 제약, 상태 전이, cascade 삭제와 스키마 마이그레이션이 필요합니다. MVP는 한 사용자만 쓰며 WidgetKit은 범위 밖입니다.

후보는 GRDB 기반 SQLite와 SwiftData였습니다.

## Decision

- 로컬 영구 저장소는 GRDB 기반 SQLite로 구현합니다.
- DB 파일은 사용자 Application Support의 `Morae` 디렉터리에 둡니다.
- 저장 구현은 `LocalStore` 프로토콜 뒤에 숨겨 도메인과 UI가 GRDB에 직접 의존하지 않게 합니다.
- GRDB DatabaseMigrator로 버전별 스키마 마이그레이션을 관리합니다.
- 고유 제약, 외래 키, cascade 삭제와 트랜잭션은 DB 수준에서 적용합니다.
- 테스트는 임시 파일 또는 in-memory DatabaseQueue를 사용합니다.
- 향후 WidgetKit이 추가되면 App Group 도입과 기존 DB 이전을 별도 ADR로 결정합니다.

## Consequences

### Positive

- SQL 스키마와 마이그레이션을 명시적으로 통제할 수 있습니다.
- `(source, sessionId, turnId)` 같은 복합 고유 제약을 직접 표현할 수 있습니다.
- 브리핑·아티클 원자 저장과 만료 cascade 삭제를 트랜잭션으로 구현할 수 있습니다.
- SQLite 도구로 장애 조사와 데이터 검증이 가능합니다.

### Negative

- 외부 패키지 의존성이 추가됩니다.
- SQL과 Swift 모델 간 매핑 코드를 관리해야 합니다.
- WidgetKit을 추가할 때는 App Group으로의 데이터 이전을 구현해야 합니다.

## Alternatives

- SwiftData: Apple 프레임워크와의 통합 및 단순 CRUD는 편리하지만, 명시적 마이그레이션과 복합 제약·동시 접근 제어를 우선해 선택하지 않았습니다.
- Core Data 직접 사용: 성숙한 대안이지만 MVP 데이터 모델에는 GRDB의 명시적 SQL과 가벼운 API가 더 적합하다고 판단했습니다.
- JSON 파일: 트랜잭션, 검색, 마이그레이션과 동시 읽기 요구를 만족하기 어려워 제외했습니다.
