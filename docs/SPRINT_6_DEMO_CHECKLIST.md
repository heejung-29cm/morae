# Sprint 6 Demo Checklist

> 대상: 설정·개인정보·Hook 온보딩·개인용 DMG
> 최종 수정: 2026-07-30

Sprint 6는 외부 도구의 설정 파일을 자동 수정하지 않습니다. 앱 설정에서
현재 앱 번들의 절대 helper 경로가 들어간 snippet을 복사해 사용자가 직접
붙여넣습니다. 앱이 실행 중일 때 들어온 이벤트만 한 번 처리하며 재시도나
디스크 대기열은 없습니다.

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

추가된 테스트는 잘못된 UserDefaults fallback, 개인정보 column scrub,
일반/상세 알림 분리와 글자 수 제한, 유효한 Hook snippet, 사용자 피드
CRUD를 검증합니다.

기대 결과는 `MoraeApp` 84개, `MoraeCore` 32개,
`HamsterEventCLI` 10개, 합계 126개 실패 0개입니다.

## 2. 설정 화면

1. Xcode에서 `MoraeApp` scheme을 `Cmd+R`로 실행합니다.
2. 메뉴의 설정 버튼을 눌러 일반·브리핑·에이전트·개인정보·정보 탭을
   차례로 엽니다.
3. 관심사를 쉼표로 입력하고 저장한 뒤 설정 창을 다시 열어 유지되는지
   확인합니다.
4. `https://` RSS/Atom 피드를 추가합니다. 같은 URL, HTTP URL과 피드가
   아닌 URL은 명확한 오류를 보여야 합니다.
5. 사용자 피드를 끄고 켠 뒤 삭제합니다. 기본 피드는 삭제 버튼 없이
   활성화만 바꿀 수 있어야 합니다.

## 3. 개인정보와 알림

1. 개인정보 세 항목과 상세 알림이 모두 기본적으로 꺼져 있는지
   확인합니다.
2. 제목 저장을 켜고 테스트 이벤트를 수신한 뒤 제목 저장을 끕니다.
3. `~/Library/Application Support/Morae/morae.sqlite`의 기존
   `agent_runs.title` 값이 모두 `NULL`인지 확인합니다.

```bash
sqlite3 "$HOME/Library/Application Support/Morae/morae.sqlite" \
  'SELECT COUNT(*) FROM agent_runs WHERE title IS NOT NULL;'
```

기대값은 `0`입니다. 이 삭제는 되돌릴 수 없습니다.

4. 알림이 미결정이면 권한 요청 버튼, 거부 상태면 시스템 알림 설정 이동
   버튼이 표시되는지 확인합니다.
5. 상세 알림을 끄면 source/status만, 켜면 저장을 허용한 제목·마지막
   메시지만 제한된 길이로 표시되는지 확인합니다. 잠금 화면 노출 주의
   문구도 확인합니다.

## 4. Codex·Claude 연결

1. 에이전트 탭에서 helper가 `번들에 포함됨`인지 확인합니다.
2. Codex snippet을 복사해 `~/.codex/config.toml`에 직접 추가합니다.
3. Claude snippet을 복사해 `~/.claude/settings.json`의 기존 JSON과
   직접 병합합니다. 앱은 두 파일을 편집하지 않습니다.
4. Claude Code는 2.1.198 이상인지 확인합니다.
5. 앱을 실행한 채 새 Codex 턴과 Claude 턴을 각각 끝내 최근 기록과
   알림을 확인합니다.
6. 앱을 종료하고 한 턴을 끝냅니다. 이벤트가 저장되지 않고 앱을 다시
   열어도 재전송되지 않아야 합니다.

## 5. 로그인 시 실행

1. 일반 탭에서 로그인 시 실행을 켭니다.
2. 시스템 설정의 로그인 항목에 모래가 표시되는지 확인합니다.
3. 다시 끄고 항목이 해제되는지 확인합니다.

이 기능은 기본적으로 꺼져 있으며 사용자가 toggle한 경우에만 등록합니다.

## 6. 재실행·데이터 유지

할 일, 수동 생성 브리핑과 에이전트 기록을 각각 하나 이상 만든 뒤 앱
종료와 재실행을 수행합니다. 세 데이터가 모두 유지되어야 합니다. 설정을
껐다가 다시 켜도 이미 scrub된 개인정보는 복구되지 않아야 합니다.

## 7. 개인용 DMG

```bash
./scripts/build-personal-dmg.sh
```

산출물은 `.artifacts/Morae-personal.dmg`입니다.

1. DMG를 열고 `Morae.app`을 Applications 링크로 복사합니다.
2. 기존 개발 빌드를 종료한 뒤 `/Applications/Morae.app`을 엽니다.
3. 설정의 정보 탭에서 helper 포함 상태를 확인합니다.
4. 첫 실행, 브리핑, 알림, Codex/Claude snippet 경로를 확인합니다.

이 DMG는 본인 Mac용 ad-hoc 서명 산출물입니다. Developer ID 서명과
공증은 하지 않으며 다른 사용자 배포용이 아닙니다.
