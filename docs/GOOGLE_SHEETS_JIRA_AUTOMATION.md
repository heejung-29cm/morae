# Google Sheets Jira 생성 자동화

구현 파일: `scripts/google-sheets-jira-automation.gs`

## 시트 열

| 열 | 값 | 처리 |
|---|---|---|
| A | 기존 구분값 | 사용하지 않음 |
| B | Dev 제목 | 선택한 첫 행에서 사용 |
| C | Subtask 제목 | 선택한 두 번째 행부터 사용 |
| D | 기존 메모/구분값 | 사용하지 않음 |
| E | Jira Priority 이름 | Jira 메타데이터의 실제 이름과 대조 |
| F | Estimate MD | 0 이상의 숫자, 필수 |
| G | Jira Key | 생성 결과 기록, 유효한 키가 있으면 건너뜀 |
| H | Story Points | 0 이상의 숫자, 필수 |
| I | 기한 | 날짜 셀 또는 `YYYY-MM-DD`, 필수 |

첫 행은 `Dev`, 이후 행은 첫 Dev의 `Subtask`로 생성한다. 첫 행 G열에
기존 Dev 키가 있으면 Dev를 다시 만들지 않고 그 키를 Subtask의 부모로
사용한다.

## 설치

1. 대상 Google Spreadsheet에서 `확장 프로그램 > Apps Script`를 연다.
2. 토큰이 들어 있던 기존 코드는 삭제한다.
3. `google-sheets-jira-automation.gs` 전체를 붙여 넣고 저장한다.
4. `프로젝트 설정 > 스크립트 속성`에 다음 값을 등록한다.

| 속성 | 값 |
|---|---|
| `JIRA_BASE_URL` | `https://jira.team.musinsa.com` |
| `JIRA_EMAIL` | Atlassian 계정 이메일 |
| `JIRA_API_TOKEN` | 새 API 토큰 전체 |

5. `testJiraAuthentication`을 한 번 실행한다.
6. Spreadsheet를 새로고침한다.

새로고침하면 `Jira 자동화` 메뉴가 생긴다.

## 실행

1. Dev가 있는 첫 행부터 마지막 Subtask 행까지 드래그한다. 어느 열을
   드래그해도 스크립트는 선택한 행의 A~I 값을 읽는다.
2. `Jira 자동화 > 선택 영역으로 Jira 생성`을 누른다.
3. 새 Dev의 상위 Jira 키를 입력한다. 빈 값은 직전 키를 사용하고 `-`는
   상위 Task 없이 생성한다.
4. 최초 실행에서 Scrum 보드가 여러 개 발견되면 보드 ID를 선택한다.
5. 생성 확인 내용을 검토한 후 `예`를 누른다.

스크립트는 시작 날짜를 실행 당일로 설정하고, 선택한 보드의 활성
Sprint를 사용한다. Status는 Jira 워크플로의 기본 시작 상태를 사용하며,
Assignee와 Reporter는 인증된 본인으로 설정한다. Description에는 해당
Spreadsheet 행으로 이동하는 링크만 기록한다.

## 자동 저장되는 설정

- `JIRA_API_BASE_URL`: 실제 `*.atlassian.net` API 주소
- `JIRA_DISPLAY_BASE_URL`: 사용자에게 표시할 Jira 주소
- `JIRA_BOARD_ID`: 선택한 Scrum 보드
- `JIRA_LAST_PARENT_KEY`: 직전에 사용한 상위 Jira 키

보드를 바꾸려면 `Jira 자동화 > Sprint 보드 다시 선택`을 누른다.

## 필드 ID 충돌 해결

필드 이름이 중복되거나 자동 탐색되지 않으면 Script Properties에 실제
필드 ID를 지정할 수 있다.

- `JIRA_START_DATE_FIELD_ID`
- `JIRA_STORY_POINTS_FIELD_ID`
- `JIRA_ESTIMATE_MD_FIELD_ID`
- `JIRA_SPRINT_FIELD_ID`

스크립트는 Create Metadata에 나타나지 않는 필드나 자동 입력할 수 없는
필수 필드가 있으면 Jira 이슈를 만들기 전에 중단한다.
