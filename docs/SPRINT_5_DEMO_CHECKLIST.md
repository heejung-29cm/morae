# Sprint 5 Demo Checklist

> 대상: 에이전트 이벤트 정규화·기록·알림
> 최종 수정: 2026-07-30

Sprint 5는 앱 프로세스가 실행 중일 때 받은 Codex/Claude 이벤트를 턴별로
저장하고 최근 기록, unread 메뉴 아이콘과 macOS 알림으로 표시합니다.
앱이 꺼져 있을 때는 저장·재시도·spool하지 않습니다.

## 1. 자동 검증

```bash
xcodebuild test \
  -project Morae.xcodeproj \
  -scheme MoraeCore \
  -destination 'platform=macOS'

xcodebuild test \
  -project Morae.xcodeproj \
  -scheme HamsterEventCLI \
  -destination 'platform=macOS'

xcodebuild test \
  -project Morae.xcodeproj \
  -scheme MoraeApp \
  -destination 'platform=macOS'
```

기대 결과:

- `MoraeCore`: 32개
- `HamsterEventCLI`: 10개
- `MoraeApp`: 79개
- 합계 121개, 실패 0개

`testCodexAndClaudeFixturesRoundTripThroughSocket`은 production UDS
client/server로 Codex 1개와 Claude 4단계 fixture를 보내 성공 ACK, 두 턴,
다섯 이벤트와 세 알림 요청을 검증합니다.

## 2. 앱과 helper 준비

1. 실행 중인 이전 모래를 Xcode Stop 버튼이나 메뉴 막대의 앱 종료로
   중지합니다.
2. Xcode에서 `MoraeApp` scheme을 `Cmd+R`로 실행합니다.
3. 모래 메뉴를 열어 에이전트 섹션의 `에이전트 알림 허용`을 누르고 macOS
   권한 대화상자에서 허용합니다.
4. 터미널에서 helper를 빌드하고 경로를 찾습니다.

```bash
xcodebuild build \
  -project Morae.xcodeproj \
  -scheme HamsterEventCLI \
  -configuration Debug

CLI_PATH="$(find ~/Library/Developer/Xcode/DerivedData \
  -path '*/Build/Products/Debug/hamster-event' -print -quit)"
test -x "$CLI_PATH"
```

Sprint 6 전에는 helper가 앱 번들에 자동 포함되지 않으며 Codex/Claude 설정
파일도 앱이 편집하지 않습니다. 이 체크리스트는 빌드 산출물을 직접
사용합니다.

## 3. Codex 여러 턴 확인

메뉴를 닫은 뒤 다음 두 명령을 실행합니다.

```bash
"$CLI_PATH" \
  '{"type":"agent-turn-complete","thread-id":"codex-demo","turn-id":"turn-1"}'

"$CLI_PATH" \
  '{"type":"agent-turn-complete","thread-id":"codex-demo","turn-id":"turn-2"}'
```

기대 결과:

- helper stdout/stderr 출력이 없습니다.
- 메뉴 막대 모래 아이콘이 filled variant로 바뀝니다.
- 허용한 경우 Codex 응답 종료 알림이 두 번 표시됩니다.
- 메뉴를 열면 `Codex` 그룹에 `응답 완료` 두 건이 최근 수신 순으로
  표시되고 unread 표시가 사라집니다.

## 4. Claude 상태 연결 확인

메뉴를 다시 닫은 뒤 한 턴에 대한 네 이벤트를 보냅니다.

```bash
printf '%s' \
  '{"session_id":"claude-demo","prompt_id":"prompt-1"}' \
  | "$CLI_PATH" claude-turn-start

printf '%s' \
  '{"session_id":"claude-demo","prompt_id":"prompt-1","notification_type":"agent_needs_input","message":"demo"}' \
  | "$CLI_PATH" claude-notification

printf '%s' \
  '{"session_id":"claude-demo","prompt_id":"prompt-1","task_id":"task-1"}' \
  | "$CLI_PATH" claude-task-completed

printf '%s' \
  '{"session_id":"claude-demo","prompt_id":"prompt-1"}' \
  | "$CLI_PATH" claude-stop
```

기대 결과:

- Claude 목록은 네 행이 아니라 한 턴 한 행입니다.
- 최종 상태는 `작업 완료`입니다. 뒤의 Stop이 `응답 완료`로 강등하지
  않습니다.
- 사용자 확인과 작업 완료 알림은 표시되지만 Stop 중복 종료 알림은
  추가되지 않습니다.

## 5. 권한 거부와 개인정보 기본값

- 알림을 거부해도 이벤트는 저장되고 메뉴 막대 filled 아이콘이 표시됩니다.
- 거부 상태에서는 앱이 권한 요청을 반복하지 않고 에이전트 섹션에
  메뉴 막대 아이콘 fallback을 안내합니다.
- Sprint 6 설정을 추가하기 전 기본값에서는 projectPath, 사용자 입력 제목과
  마지막 메시지를 저장하거나 화면·알림에 표시하지 않습니다.
- 앱을 종료한 상태에서 같은 helper 명령을 실행하면 조용히 exit 0으로
  끝나며 다음 앱 실행 때 복구되지 않습니다.
