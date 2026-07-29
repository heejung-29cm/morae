# 모래

macOS 바탕화면에서 매일의 지식, 업무 계획, AI 에이전트 작업 상태를 한곳에 보여주는 개인 비서입니다. 마스코트는 움직이는 햄스터 캐릭터 "모래"입니다.

> 문서 상태: MVP 사양 확정  
> 최초 작성: 2026-07-24  
> 최종 수정: 2026-07-29  
> 코드네임: Hamster Bot (제품명 "모래"로 확정, bundle ID 등 식별자는 로마자 슬러그 `morae` 사용)

설계 문서:

- [High-Level Design](docs/HLD.md)
- [Low-Level Design](docs/LLD.md)
- [MVP Sprint Tasks](docs/SPRINT_TASKS.md)
- [Architecture Decision Records](docs/adr/)

## 1. 제품 목표

모래는 사용자가 하루를 시작하고 업무 흐름을 확인하기 위해 여러 앱과 터미널을 반복해서 열어보는 일을 줄입니다.

핵심 역할은 다음 세 가지입니다.

1. 오늘 읽을 프론트엔드 아티클을 선정하고 원문 링크를 제공한다.
2. 어제 한 일과 오늘 할 일을 한눈에 정리한다.
3. Codex의 응답 종료와 Claude Code의 응답 종료·완료·실패 등 수신 가능한 이벤트를 기록하고 알린다.

## 2. 제품 형태

모래는 하나의 macOS 앱 안에서 네 가지 인터페이스를 제공합니다.

| 인터페이스 | 역할 |
| --- | --- |
| 바탕화면 위젯 | 아티클, 완료한 일, 오늘 할 일 등 자주 보는 요약 정보 (MVP 이후 2단계) |
| 메뉴 막대 앱 | 상세 내용, 할 일 편집, 에이전트 상태, 설정 |
| 마스코트(모래) | 메뉴 막대 앱 또는 별도 오버레이 창에서 움직이는 햄스터 캐릭터로 상태를 표현 (MVP 이후 2단계) |
| macOS 알림 | 에이전트 작업 완료, 승인 필요, 실패 등 즉시 확인할 이벤트 |

마스코트는 WidgetKit 위젯이 아닌 메뉴 막대 앱 또는 별도 오버레이 창에 배치합니다. WidgetKit은 갱신 횟수가 제한돼 실시간 애니메이션이 불가능하기 때문입니다.

WidgetKit 위젯은 macOS가 갱신 횟수를 관리하므로 실시간 상태 표시 수단으로 사용하지 않습니다. 위젯은 정기적인 브리핑에 집중하고, 수신된 최신 에이전트 상태는 메뉴 막대 앱과 네이티브 알림으로 처리합니다.

관련 문서:

- [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple WidgetKit 업데이트 정책](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

## 3. 핵심 사용자 경험

### 3.1 수동 브리핑

메뉴 막대 아이콘을 누르고 "오늘 브리핑 만들기" 버튼을 선택하면 다음 정보를 준비합니다. MVP에서는 예약 실행이나 주기적인 백그라운드 생성을 하지 않습니다.

```text
7월 24일 금요일
좋은 아침이에요 👋

오늘의 프론트엔드
React의 새로운 캐시 전략
React Blog · 원문 보기

어제 완료
✓ 상품 목록 렌더링 개선
✓ 리뷰 PR 반영

오늘 할 일
□ 검색 필터 개발
□ 디자인 리뷰
+ 빠른 할 일 추가
```

브리핑은 사용자가 버튼을 누른 시점에 한 번 생성합니다. 앱을 다시 실행하거나 포그라운드로 전환하는 것만으로는 자동 생성하지 않습니다.

### 3.2 업무 중 확인

메뉴 막대 아이콘을 누르면 다음 내용을 확인할 수 있습니다.

- 최근 응답이 끝난 Claude/Codex 작업
- Claude Code에서 사용자 확인이나 권한 승인이 필요한 작업
- 오늘 할 일의 완료 상태
- 오늘의 추천 아티클 정보와 원문 링크
- 최근 완료된 에이전트 작업

### 3.3 에이전트 이벤트 알림

에이전트 이벤트를 수신하면 상태를 저장하고 macOS 알림을 표시합니다.

```text
모래
Codex 응답이 끝났어요.
모래에서 최근 기록을 확인해 주세요.
```

MVP에서 알림을 누르면 모래의 최근 에이전트 기록 목록을 엽니다. 해당 작업 상세 화면으로 바로 이동하는 기능은 2단계에서 추가합니다.

사용자가 macOS 알림 권한을 거부했거나 나중에 껐다면, 메뉴 막대 아이콘에 배지/도트로 미확인 상태를 표시해 알림 없이도 눈에 띄게 하고, 설정 화면에 권한 재요청 안내를 배치합니다.

## 4. 기능 요구사항

### 4.1 오늘의 프론트엔드 아티클

#### 수집

초기 버전은 신뢰할 수 있는 공식 블로그와 RSS/Atom 피드만 사용합니다.

- [MDN Blog](https://developer.mozilla.org/en-US/blog/rss.xml)
- [web.dev](https://web.dev/static/blog/feed.xml)
- [Chrome for Developers](https://developer.chrome.com/static/blog/feed.xml)
- [React Blog](https://react.dev/rss.xml)
- 사용자가 직접 추가한 RSS/Atom 피드

피드는 사용자가 메뉴 막대의 "오늘 브리핑 만들기" 버튼을 누를 때 한 번만 확인합니다. MVP에서는 예약 폴링이나 백그라운드 수집을 하지 않습니다.

#### 선정

하루에 기본 1개를 추천합니다. 다음 요소를 반영할 수 있어야 합니다.

- 게시 시점
- 사용자가 설정한 관심 분야
- 이미 읽었거나 추천한 글인지 여부
- 공식 출처 여부

#### 표시 결과

- 제목
- 출처와 게시일
- 원문 링크

피드의 본문·요약과 아티클 원문 HTML은 가져오거나 저장하지 않습니다. 피드에서 제목, 링크, 출처와 게시일만 읽으며 AI API를 사용하지 않습니다. 피드 조회에 실패하면 해당 브리핑의 할 일 요약은 표시하고 아티클 영역에는 오류 상태만 보여주며 자동 재시도하지 않습니다.

### 4.2 어제 한 일

초기 MVP에서는 모래 안에서 완료한 할 일을 기준으로 보여줍니다.

이후 다음 소스를 선택적으로 연결합니다.

- 로컬 Git 커밋
- GitHub에서 머지한 Pull Request
- Apple 미리 알림의 완료 항목
- 캘린더에서 끝난 일정
- 사용자가 직접 작성한 회고

자동 수집 항목과 사용자가 작성한 항목은 출처를 구분해 표시합니다. Git 커밋 메시지를 그대로 업무 성과로 간주하지 않고, 여러 커밋을 하나의 작업으로 묶거나 제외할 수 있어야 합니다.

3단계에서 Git 연동을 구현할 때는 브랜치 단위로 커밋을 자동 그룹핑해 하나의 "어제 한 일" 항목 후보로 만들고, 제목은 브랜치명 또는 대표 커밋 메시지에서 추출합니다. 사용자는 이 그룹을 화면에서 병합·분리·제외로 직접 편집할 수 있습니다.

### 4.3 오늘 할 일

#### 기본 기능

- 할 일 추가, 수정, 완료, 삭제
- 순서 변경
- 중요 항목 표시
- 예상 소요 시간
- 관련 링크 또는 프로젝트 경로
- 어제 미완료 항목 가져오기

#### 아침 체크인

오늘 브리핑을 처음 만들 때 선택적으로 한 가지 질문을 표시합니다.

> 오늘 반드시 끝내고 싶은 한 가지는 무엇인가요?

답변은 오늘의 최우선 항목으로 저장합니다.

#### 향후 연동

- Apple 미리 알림 (MVP 이후 최우선 연동 대상)
- Google Calendar
- Notion
- GitHub

외부 서비스는 MVP 이후 추가하며, 사용자가 연결하지 않아도 핵심 기능을 사용할 수 있어야 합니다. Apple 미리 알림을 먼저 연동하는 이유는 EventKit으로 OAuth 없이 온디바이스 연동이 가능해 §10 개인정보 원칙과 자연스럽게 맞고, Google Calendar 대비 구현 부담이 작기 때문입니다.

### 4.4 Claude/Codex 작업 상태

공통 상태 모델은 다음과 같습니다.

| 상태 | 의미 |
| --- | --- |
| `running` | 작업 진행 중 (MVP 이후) |
| `attention_required` | 사용자 입력 또는 권한 승인 필요 |
| `completed` | 정의된 완료 조건을 만족함 |
| `responded` | 에이전트 응답은 끝났지만 업무 완료 여부는 불명확함 |
| `failed` | 오류로 작업이 중단됨 |
| `cancelled` | 사용자 또는 시스템이 작업을 취소함 (MVP 이후) |

#### 중요한 구분

Codex의 `agent-turn-complete`와 Claude Code의 `Stop`은 기본적으로 한 번의 에이전트 응답이 끝났음을 의미합니다. 이것만으로 실제 업무가 완료됐다고 단정하지 않습니다.

따라서 기본 매핑은 다음과 같습니다.

- `agent-turn-complete` → `responded`
- Claude `Stop` → `responded`
- Claude `TaskCompleted` → `completed`
- Claude `Notification`의 권한 요청 또는 입력 대기 → `attention_required`
- Claude `StopFailure` → `failed`

MVP에서는 Claude `TaskCompleted`를 명시적인 완료 조건으로 사용합니다. 향후에는 테스트 통과, 결과 파일 생성, 명시적인 완료 보고 등 더 엄격한 검증 규칙을 만족했을 때만 `completed`로 승격하도록 확장할 수 있습니다.

메뉴 막대 UI에서는 `responded`와 `completed`를 색상과 문구로 명확히 구분합니다. `responded`는 회색 계열 색상과 "응답됨, 확인 필요" 문구로, `completed`는 초록 계열 색상과 "완료됨" 문구로 표시해 사용자가 응답 종료를 업무 완료로 오해하지 않도록 합니다.

MVP의 Codex 연동은 비용이 들지 않고 설정이 단순한 `notify`만 사용합니다. `notify`가 제공하는 외부 이벤트는 현재 `agent-turn-complete`뿐이므로 Codex의 `running`, `attention_required`, `failed`, `cancelled` 상태는 추적하지 않습니다. 실시간 상태와 승인 대기가 필요해지면 Codex App Server 연동을 후속 단계에서 검토합니다.

Claude Code는 `Stop`, `Notification`, `TaskCompleted`, `StopFailure` Hook을 통해 각각 응답 종료, 사용자 확인 필요, 명시적 작업 완료, API 오류 종료를 구분합니다.

## 5. 에이전트 연동 설계

### 5.1 공통 이벤트 흐름

```text
Claude Code / Codex
        │
        │ Hook 또는 notify
        ▼
모래 이벤트 수신기
        │
        ├─ 이벤트 정규화
        ├─ 로컬 DB 저장
        ├─ 메뉴 막대 상태 갱신
        └─ macOS 알림 전송
```

`hamster-event`는 Codex의 `notify`나 Claude Code의 Hook이 호출하는 일회성 CLI 프로세스입니다. 사용자 전용 Unix Domain Socket(사용자 전용 경로, 0600 권한)을 통해 실행 중인 메뉴 막대 앱과 통신하며, 전달 즉시 처리되고 별도 지연 큐를 두지 않습니다. 로그인 시 자동 실행은 사용자가 선택적으로 활성화합니다.

MVP는 앱이 실행 중일 때 수신한 이벤트만 기록합니다. 앱이 종료됐거나 소켓 연결에 실패하면 이벤트는 저장하지 않으며, 설정 화면에 이 제한을 안내합니다. 따라서 MVP의 에이전트 알림은 내구성 있는 감사 로그가 아니라 best-effort 편의 기능입니다.

여러 프로젝트에서 Claude/Codex 이벤트를 수신했을 때, 메뉴 막대에서는 `AgentRun`을 `projectPath` 기준으로 그룹핑한 단일 리스트로 보여주고 최근 수신 순으로 정렬합니다.

외부 도구별 원본 이벤트는 모래의 공통 이벤트 형식으로 변환합니다.

```json
{
  "schemaVersion": 1,
  "id": "event-uuid",
  "source": "codex",
  "sourceEvent": "agent-turn-complete",
  "status": "responded",
  "sessionId": "source-session-id",
  "turnId": "source-turn-id",
  "occurredAt": "2026-07-24T14:30:00+09:00",
  "receivedAt": "2026-07-24T14:30:00+09:00",
  "projectPath": "/path/to/project",
  "title": "상품 상세 페이지 리팩터링",
  "lastMessage": "구현과 테스트 결과를 확인해 주세요."
}
```

### 5.2 Codex

Codex CLI는 사용자 전역 `config.toml`의 `notify` 명령으로 지원 이벤트를 외부 프로그램에 전달합니다. 현재 공식 문서상 외부 알림 이벤트는 `agent-turn-complete`이며, JSON 문자열 한 개가 명령 인자로 전달됩니다.

예상 설정:

```toml
notify = ["/Applications/모래.app/Contents/MacOS/hamster-event"]
```

수신할 수 있는 주요 필드:

- `type`
- `thread-id`
- `turn-id`
- `cwd`
- `input-messages`
- `last-assistant-message`

참고: [Codex Notifications](https://developers.openai.com/codex/config-advanced)

이 방식은 한 턴의 응답 종료만 알려주며, 작업 시작·진행·승인 요청·실패 이벤트는 제공하지 않습니다. Codex 이벤트의 `turn-id`를 공통 이벤트의 `turnId`로 저장해 같은 세션에서 발생한 여러 턴을 구분합니다.

### 5.3 Claude Code

Claude Code는 사용자 전역 `~/.claude/settings.json` 또는 프로젝트 설정에서 Hook을 구성할 수 있습니다.

턴 시작, 응답 종료, API 오류 종료 이벤트 예시:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"/Applications/모래.app/Contents/MacOS/hamster-event\" claude-turn-start"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"/Applications/모래.app/Contents/MacOS/hamster-event\" claude-stop"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|elicitation_dialog|agent_needs_input",
        "hooks": [
          {
            "type": "command",
            "command": "\"/Applications/모래.app/Contents/MacOS/hamster-event\" claude-notification"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"/Applications/모래.app/Contents/MacOS/hamster-event\" claude-task-completed"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"/Applications/모래.app/Contents/MacOS/hamster-event\" claude-stop-failure"
          }
        ]
      }
    ]
  }
}
```

`UserPromptSubmit`을 받으면 Claude Code 2.1.196 이상이 제공하는 `prompt_id`를 `turnId`로 사용합니다. 해당 필드가 없는 구버전이나 비정상 Hook 입력에서만 UUID를 생성합니다. `Notification`은 `permission_prompt`, `elicitation_dialog`, `agent_needs_input`만 수신해 사용자 확인이 필요한 상태로 처리하고, `TaskCompleted`는 명시적인 업무 단위 완료를 전달합니다. `StopFailure`는 오류 종류와 상세 정보를 포함하므로 `failed`로 정규화합니다. `agent_needs_input`까지 포함한 전체 동작에는 Claude Code 2.1.198 이상이 필요하며, 설정 화면에서 그보다 낮은 버전에는 호환성 안내를 표시합니다.

Claude command Hook은 이벤트 JSON을 표준 입력으로 전달하므로, 이벤트 수신기는 Codex의 명령 인자 방식과 Claude의 표준 입력 방식을 모두 지원해야 합니다.

Claude Hook의 공통 `prompt_id`를 같은 사용자 프롬프트에서 발생한 `Notification`, `TaskCompleted`, `Stop`, `StopFailure` 연결에 사용합니다. `Stop` 또는 `StopFailure`를 받으면 해당 턴을 닫습니다. `TaskCompleted` 뒤에 `Stop`이 와도 `completed`를 `responded`로 낮추거나 같은 턴의 종료 알림을 다시 보내지 않습니다. `prompt_id`가 없으면 같은 `sessionId`의 최신 열린 턴에 연결하고, 열린 턴도 없다면 UUID 폴백 턴을 생성합니다.

Codex `config.toml`과 Claude `settings.json`은 사용자가 이미 소유한 설정 파일이므로, 모래 앱은 이 파일들을 자동으로 수정하지 않습니다. 설정 화면에서 추가해야 할 설정 스니펫을 보여주고, 사용자가 직접 복사해 붙여넣도록 안내합니다.

참고:

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)

## 6. 기술 구성

### 배포 및 버전

- 배포 방식: 본인 전용 DMG. 로컬 실행용 서명(`Sign to Run Locally` 또는 ad-hoc)을 사용하며 Developer ID 서명과 공증은 하지 않습니다.
- Mac App Store는 배포하지 않습니다 — §5의 `notify`/Hook 실행파일 호출 구조가 App Sandbox 제약과 충돌하기 때문입니다.
- macOS 최소 지원 버전: macOS 14 (Sonoma) 이상
- Bundle ID: `io.github.heejung-29cm.morae`

### macOS 클라이언트

- Swift
- SwiftUI
- `MenuBarExtra`
- UserNotifications
- SQLite + GRDB

### 실행 모델

- 사용자가 선택하면 로그인 시 메뉴 막대 앱 자동 실행
- 메뉴 막대 버튼을 누를 때만 RSS/Atom 메타데이터 수집과 아티클 선정 실행
- 메뉴 막대 앱이 실행 중일 때만 로컬 에이전트 이벤트 수신
- 예약 브리핑, 정기 수집, 피드 조회 재시도는 MVP에서 제외

별도 상시 서버를 도입하지 않고 macOS 앱과 경량 CLI 수신기로 시작합니다. 클라우드 동기화나 내구성 있는 이벤트 수집이 필요해질 때 서버 또는 로컬 스풀 도입을 검토합니다.

### 데이터 저장

기본 데이터는 Mac 내부에 저장합니다.

- 사용자 관심사와 설정
- 아티클 메타데이터
- 할 일과 회고
- 에이전트 실행과 이벤트 기록

MVP 앱은 사용자 Application Support 디렉터리(`~/Library/Application Support/Morae`)와 표준 `UserDefaults`를 사용합니다. WidgetKit을 추가할 때는 App Group 도입과 기존 데이터 이전을 별도 설계합니다.

## 7. 데이터 모델 요약

### `Article`

- `id`
- `canonicalURL`
- `title`
- `sourceName`
- `sourceURL`
- `publishedAt`
- `isRead`
- `isLiked`
- `createdAt`
- `updatedAt`

### `TodoItem`

- `id`
- `title`
- `day`
- `status`
- `priority`
- `sortOrder`
- `estimatedMinutes`
- `relatedURL`
- `projectPath`
- `completedAt`
- `createdAt`
- `updatedAt`

### `AgentRun`

- `id`
- `source`
- `sessionId`
- `turnId`
- `projectPath`
- `title`
- `status`
- `startedAt`
- `receivedAt`
- `updatedAt`
- `closedAt`
- `closureReason`
- `lastMessage`
- `isUnread`

### `AgentEvent`

- `id`
- `agentRunId`
- `eventKey`
- `sourceEvent`
- `normalizedStatus`
- `occurredAt`
- `receivedAt`

`AgentRun`의 `(source, sessionId, turnId)` 조합은 고유해야 합니다. Codex는 원본 `turn-id`를 사용하고 `startedAt`은 비워 둡니다. Claude Code는 공식 `prompt_id`를 사용하고, 해당 필드가 없을 때만 UUID로 대체합니다. 두 소스 모두 `receivedAt`에는 모래가 이벤트를 받은 시각을 기록합니다. 원본 Hook/notify payload 전체는 `AgentEvent`에 저장하지 않습니다.

## 8. MVP 범위

첫 번째 버전은 다음 세 가지 사용자 가치에 집중합니다.

1. 모래 안에서 기록한 어제 한 일과 오늘 할 일 요약
2. 사용자가 메뉴 막대 버튼을 눌렀을 때 최근 프론트엔드 아티클 1개의 제목과 원문 링크 제공
3. 앱 실행 중 수신한 Codex 응답 종료와 Claude Code 응답 종료·완료·실패 알림

이를 위해 다음 기반 기능을 포함합니다.

- 메뉴 막대 아이콘과 "오늘 브리핑 만들기" 버튼
- 할 일 직접 입력, 수정, 완료, 삭제
- Codex `notify` 연동
- Claude Code `UserPromptSubmit`, `Stop`, `Notification`, `TaskCompleted`, `StopFailure` Hook 연동
- Codex/Claude 설정 스니펫 표시 및 수동 붙여넣기 온보딩
- 네이티브 macOS 알림과 기본 설정 화면

MVP에서 제외합니다.

- 계정과 다중 기기 동기화
- 팀 기능
- 이메일과 메신저 연동
- 외부 캘린더 및 Notion 연동
- 자연어 음성 비서
- 에이전트 작업을 모래에서 직접 실행하는 기능
- 완전 자동화된 업무 완료 판정
- 모래 마스코트 애니메이션과 별도 오버레이 창
- 예약 아침 브리핑, 백그라운드 RSS 수집, 자동 재시도
- Codex 작업 시작·진행·승인 요청·실패 상태 추적

## 9. 단계별 로드맵

### 1단계: 로컬 개인 비서

- 메뉴 막대 UI와 수동 브리핑 트리거
- 로컬 데이터 저장
- 한 일/할 일 관리와 요약
- 수동 RSS 수집과 아티클 추천 링크
- 앱 실행 중 에이전트 종료 알림

### 2단계: 바탕화면 경험

- 모래 마스코트 애니메이션과 별도 오버레이 창
- WidgetKit 위젯
- 예약 아침 브리핑과 백그라운드 수집
- 위젯 크기별 레이아웃
- 알림에서 상세 화면으로 이동

### 3단계: 업무 자동 수집

- Git 커밋
- GitHub Pull Request
- Apple 미리 알림
- 캘린더

### 4단계: 개인화

- 선호하는 프론트엔드 주제 학습
- 아티클 추천 품질 개선
- 반복 업무 감지
- 주간 회고

## 10. 개인정보 및 보안 원칙

- Codex와 Claude가 Hook/notify payload에 포함한 입력 메시지, 마지막 응답, 프로젝트 경로는 이벤트 수신 시 메모리에서 일시적으로 처리될 수 있다.
- 기본값으로 DB에는 소스, 세션/턴 식별자, 정규화 상태, 수신 시각 등 알림과 상태 표시에 필요한 최소 필드만 저장한다.
- 원본 Hook/notify payload, 전체 입력 메시지, 전체 마지막 응답, Claude transcript 경로는 기본 저장하지 않고 처리 직후 폐기한다.
- 프로젝트 경로, 작업 제목, 마지막 응답 일부의 저장과 알림 본문 노출은 각각 사용자가 명시적으로 활성화할 수 있게 한다.
- 민감한 내용이 잠금 화면에 나타나지 않도록 기본 알림 문구는 에이전트 종류와 상태만 포함한다.
- 에이전트 기록은 수신일로부터 90일간 보존하고, 앱 시작 시와 새 이벤트 저장 후 만료된 기록을 삭제한다.
- 에이전트 이벤트와 아티클 본문은 외부 서비스로 전송하지 않는다.
- 피드에서는 제목, 링크, 출처와 게시일만 처리하고 피드 본문·요약과 아티클 원문 HTML은 저장하지 않는다.
- 이벤트 수신기는 로컬 프로세스 또는 사용자 전용 파일 권한으로 제한한다.
- Codex `config.toml`, Claude `settings.json` 등 외부 도구의 설정 파일은 앱이 자동으로 수정하지 않는다. 추가할 설정 스니펫만 화면에 표시하고 사용자가 직접 붙여넣는다.

## 11. 결정 이력

아래 항목은 모두 결정되어 본문에 반영되었습니다.

- MVP는 한 일/할 일 요약, 수동 아티클 추천, 앱 실행 중 에이전트 종료 알림에 집중합니다 (§8).
- 위젯과 마스코트 애니메이션은 MVP에서 제외하고 2단계(§2, §9)로 미룹니다.
- 아티클은 AI 요약 없이 공식 피드의 제목, 링크, 출처와 게시일만 사용합니다 (§4.1).
- Git 활동은 브랜치 단위 자동 그룹핑 + 사용자 편집 기준으로 3단계에 반영합니다 (§4.2).
- `responded`/`completed`는 색상+문구로 명확히 구분해 표시합니다 (§4.4).
- 외부 연동은 Apple 미리 알림을 Google Calendar보다 먼저 진행합니다 (§4.3).
- 제품 이름은 "모래"로 확정했고, 마스코트도 동일한 이름의 햄스터 캐릭터입니다 (제목, §2).

추가로 논의 과정에서 다음 구조적 결정도 확정했습니다.

- 배포 방식, macOS 최소 버전, 로컬 저장소, Bundle ID 슬러그 (§6)
- 에이전트 이벤트 IPC 방식과 앱 실행 중에만 수신하는 best-effort 정책 (§5.1)
- 설정 파일(Codex/Claude) 온보딩 방식과 보안 원칙 (§5.3, §10)
- 다중 프로젝트/턴 식별, 알림 권한 거부 폴백, Claude `StopFailure` 매핑 (§4.4, §3.3, §5.3)
- 메뉴 막대 수동 브리핑 트리거와 피드 조회 무재시도 정책 (§3.1, §4.1)
- 에이전트 이벤트의 일시적 수신과 영구 저장을 구분하는 개인정보 원칙 (§10)
- 로컬 저장소는 GRDB 기반 SQLite를 사용합니다 (§6, [ADR-0006](docs/adr/0006-grdb-local-persistence.md)).
- 아티클 원문과 피드 본문은 가져오지 않고 피드 메타데이터만 사용합니다 (§4.1, [ADR-0010](docs/adr/0010-feed-metadata-only-article-recommendation.md)).
- 에이전트 기록은 최근 90일간 보존합니다 (§10, [ADR-0008](docs/adr/0008-agent-record-90-day-retention.md)).

## 12. MVP 완료 조건

다음 시나리오가 로컬 Mac에서 처음부터 끝까지 동작하면 MVP가 완료된 것으로 봅니다.

1. 앱을 실행하면 메뉴 막대에 모래가 표시된다.
2. 메뉴 막대에서 브리핑 생성을 요청하면 최근 아티클 한 개의 제목·출처·게시일·원문 링크와 어제 한 일, 오늘 할 일을 확인할 수 있다.
3. 오늘 할 일을 추가·수정·완료·삭제할 수 있고, 다음 날 완료한 항목이 “어제 한 일”에 나타난다.
4. 메뉴 막대 앱이 실행 중일 때 Claude 또는 Codex의 한 턴이 끝나면 서로 다른 `turnId`로 기록된다.
5. 메뉴 막대 앱이 실행 중이고 창이 닫혀 있을 때 Codex 응답 종료와 Claude 응답 종료·완료·실패 이벤트에 대한 macOS 알림이 표시된다.
6. 앱을 재실행해도 수동으로 생성한 아티클 브리핑, 할 일, 수신한 에이전트 기록이 유지된다.
