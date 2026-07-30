# ADR-0012: provenance 기반 할 일 이월 중복 방지

- 상태: Accepted
- 날짜: 2026-07-30

## Context

어제 미완료 항목 가져오기는 원본을 보존하고 오늘 날짜에 새 ID로 복사합니다.
초기 구현은 복사본과 원본의 관계를 저장하지 않아 같은 항목을 반복해서
가져올 수 있었고, 가져온 뒤에도 원본이 후보 목록에 계속 표시됐습니다.

제목과 메타데이터 비교만으로 원본을 추정하면 사용자가 별도로 만든 동일한
할 일을 잘못 숨길 수 있습니다. 반복 클릭뿐 아니라 앱 재실행과 동시에
발생한 요청에서도 DB 수준의 중복 방지가 필요합니다.

## Decision

- 이월은 move가 아니라 copy로 유지하며 어제 원본을 변경하지 않습니다.
- 복사본은 새 `TodoID`를 사용합니다.
- 복사본의 기존 `tasks.source`에
  `carryover:<원본 task id>` 형식으로 provenance를 저장합니다.
- `(task_day, source)`에 `source LIKE 'carryover:%'` 조건의 partial unique
  index를 추가합니다.
- 이월 후보 조회는 대상 날짜에 같은 provenance를 가진 복사본이 있으면
  해당 원본을 제외합니다.
- 이월 transaction도 기존 provenance를 다시 확인해 반복 요청을
  idempotent하게 처리합니다.
- 성공한 원본은 현재 ViewModel의 후보 목록에서도 즉시 제거합니다.
- v2 이전 복사본은 `source=manual`이라 원본을 안전하게 판별할 수 없으므로
  자동 backfill하지 않습니다.

## Consequences

### Positive

- 같은 원본을 같은 날짜에 두 번 가져올 수 없습니다.
- 앱 재실행 후에도 이미 가져온 항목이 후보 목록에 나타나지 않습니다.
- 원본은 어제 기록으로 보존되고 오늘 복사본은 독립적으로 수정할 수
  있습니다.
- 새 table이나 nullable domain field를 추가하지 않고 기존 provenance
  column을 활용합니다.

### Negative

- v2 적용 전에 생성된 이월 복사본은 자동으로 연결되지 않습니다.
- `tasks.source`는 단순 생성 주체뿐 아니라 이월 provenance도 표현하므로
  repository 밖에서 임의 문자열로 쓰지 않아야 합니다.
- 다른 날짜로의 이월을 추가할 때도 대상 날짜와 provenance 규칙을
  유지해야 합니다.

## Alternatives

- 원본의 날짜를 오늘로 이동: 중복은 단순하게 막지만 어제 기록을
  보존한다는 기존 동작을 바꿉니다.
- 원본을 완료 또는 삭제 처리: 어제 완료 통계를 왜곡하거나 기록을
  잃습니다.
- 제목과 메타데이터가 같은 오늘 항목을 중복으로 간주: 수동으로 만든
  동일 항목을 오판할 수 있습니다.
- 별도 이월 mapping table 추가: 명시적이지만 현재 MVP의 단일 관계에는
  스키마와 repository 복잡도가 더 큽니다.
