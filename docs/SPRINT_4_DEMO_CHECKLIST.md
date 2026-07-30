# Sprint 4 Demo Checklist

> 대상: Agent IPC 전송 계층
> 최종 수정: 2026-07-30

Sprint 4는 Codex/Claude 이벤트를 앱 프로세스까지 안전하게 전달하는
transport를 완성한 시점의 체크리스트입니다. 현재 브랜치는 Sprint 5까지
구현되어 정상 이벤트를 저장하므로, 최신 동작은
[Sprint 5 데모 체크리스트](SPRINT_5_DEMO_CHECKLIST.md)를 따릅니다.

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

- `MoraeCore` 26개
- `HamsterEventCLI` 10개
- `MoraeApp` 70개
- 합계 106개, 실패 0개

`testRealClientServerRoundTrip`은 임시 UDS에서 production client/server의
성공 ACK를 확인합니다. partial read는 별도 byte 단위 테스트가 검증합니다.

## 2. 앱 실행 중 수동 smoke test

1. Xcode에서 `MoraeApp` scheme을 `Cmd+R`로 실행합니다.
2. 다음 경로에 socket이 생성됐는지 확인합니다.

```bash
SOCKET_DIR="${TMPDIR%/}/morae-$(id -u)"
ls -ld "$SOCKET_DIR"
ls -l "$SOCKET_DIR/event.sock"
```

기대 권한은 부모 `drwx------`, socket `srw-------`입니다.

3. Xcode build products의 `hamster-event`를 실행합니다.

```bash
CLI_PATH="$(find ~/Library/Developer/Xcode/DerivedData \
  -path '*/Build/Products/Debug/hamster-event' -print -quit)"
"$CLI_PATH" '{"type":"agent-turn-complete","thread-id":"demo","turn-id":"turn-1"}'
echo $?
```

기대 결과는 출력 없음, exit code `0`입니다. 현재 Sprint 5 live handler는
이 이벤트를 최근 에이전트 기록에 `응답 완료`로 저장합니다.

## 3. 앱 종료 상태 확인

1. Xcode의 Stop 버튼으로 Morae를 종료합니다.
2. 같은 CLI 명령을 다시 실행합니다.

기대 결과:

- 출력 없음
- exit code `0`
- 재시도 없음
- payload spool 파일 없음
- 기존 `event.sock` 제거

## 4. Sprint 5 연결 상태

현재는 `AgentEnvelopeHandling`에 `ReceiveAgentEvent`가 주입되어 있습니다.
지원 이벤트는 정규화와 DB 저장 성공 후 success ACK를 받고, 에이전트
목록과 알림까지 직접 확인할 수 있습니다.
