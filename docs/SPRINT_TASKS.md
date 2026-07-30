# 모래 MVP Sprint Tasks

> 상태: Sprint 0·1·1.5·2·3·3.1 완료 / Sprint 4~6 준비 완료
> 최종 수정: 2026-07-30
> 기준 문서: [README](../README.md), [HLD](HLD.md), [LLD](LLD.md), [ADR](adr/)

## 1. 사용 방법

이 문서는 MVP 구현을 검토하기 쉬운 작은 작업으로 나눈 백로그입니다. Sprint 번호는 의존 순서를 나타내며 달력 기간을 고정하지 않습니다. 팀 가용 인원과 속도에 맞춰 같은 Sprint의 일부만 선택할 수 있습니다.

태스크 원칙:

- 태스크 하나는 원칙적으로 PR 하나이며 한 가지 관심사만 다룹니다.
- 구현과 그 구현을 검증하는 단위 테스트는 같은 태스크에 포함합니다.
- `XS`는 1~2시간, `S`는 2~4시간, `M`은 반나절~1일의 초기 추정치입니다.
- `M`을 넘길 것으로 보이면 구현 전에 태스크를 다시 분할합니다.
- 선행 태스크가 완료되고 main branch에서 검증된 뒤 후속 태스크를 시작합니다.
- MVP 제외 항목은 이 백로그에 끼워 넣지 않습니다.

모든 태스크의 공통 완료 조건:

- macOS 14 대상 Debug build가 성공합니다.
- 새 로직의 성공·실패 경계가 테스트됩니다.
- 원본 Hook payload와 피드 body가 로그나 fixture 산출물에 남지 않습니다.
- 관련 LLD 계약이 바뀌면 코드와 같은 PR에서 문서를 갱신합니다.
- 리뷰어가 태스크 설명만 보고 변경 범위와 검증 방법을 재현할 수 있습니다.

현재 진행 요약:

| Sprint | 상태 | 구현 결과 |
| --- | --- | --- |
| Sprint 0 | 완료 | Xcode 타깃, 공통 코어, GRDB/SQLite, 테스트 기반 |
| Sprint 1 | 완료 | Todo CRUD·완료·재정렬·이월·어제 완료 요약 |
| Sprint 1.5 | 완료 | 소프트 블루 UI, light/dark, inline panel, pointer reorder |
| Sprint 2 | 완료 | 기본 피드, 제한된 HTTP, RSS/Atom, 정규화·선정·Article 저장소 |
| Sprint 3 | 완료 | 수동 생성, 무재시도, 최우선 할 일 질문, 최신 결과 복원 |
| Sprint 3.1 | 완료 | 큐레이션 기본 피드 전환, 소스 가중치, 기존 설치 migration |
| Sprint 4~6 | 예정 | Agent IPC·알림, 설정·배포 |

완료 표시는 현재 브랜치의 구현과 자동화 테스트를 기준으로 합니다. 후속
Sprint용 DB 테이블과 empty state가 존재하더라도 실제 기능 연결 전에는
완료로 간주하지 않습니다.

## 2. Sprint 0 — 실행 가능한 앱 기반

목표: 메뉴 막대 앱, CLI, 공통 코어와 로컬 DB를 빌드·테스트할 수 있는 최소 기반을 만듭니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S0-01 | S | Xcode 프로젝트와 타깃 생성 | 없음 | `MoraeApp`, `HamsterEventCLI`, `MoraeCore` 및 테스트 타깃이 각각 빌드되고 CLI smoke test가 통과합니다. |
| S0-02 | XS | 제품 식별자와 로컬 배포 설정 적용 | S0-01 | Bundle ID `io.github.heejung-29cm.morae`, macOS 14 deployment target과 로컬 실행용 서명 구성이 build settings에 반영됩니다. |
| S0-03 | S | 로컬 앱 데이터 디렉터리 구성 | S0-02 | 사용자 Application Support 아래 `Morae` 디렉터리를 생성하고 접근 실패를 사용자에게 안내하는 테스트가 통과합니다. |
| S0-04 | S | Swift Package 의존성 추가 | S0-01 | GRDB와 FeedKit을 호환 minor 범위로 추가하고 `Package.resolved`를 커밋하며 세 타깃의 불필요한 의존이 없는지 확인합니다. |
| S0-05 | S | 공통 식별자·시간 값 타입 구현 | S0-01 | `LocalDay`, UUID 기반 ID, Unix millisecond 변환과 날짜 경계 테스트를 `MoraeCore`에 추가합니다. |
| S0-06 | S | 공통 오류와 상태 타입 구현 | S0-05 | LLD의 `AppError`, agent/briefing/task enum raw value와 Codable round-trip 테스트를 추가합니다. |
| S0-07 | S | AppContainer와 Port 골격 구성 | S0-06 | UI가 concrete adapter가 아닌 protocol/use case에 의존하고 Preview/Test용 대체 구현을 주입할 수 있습니다. |
| S0-08 | XS | OSLog category와 redaction helper 구성 | S0-01 | LLD category가 정의되고 금지 필드가 public 로그로 전달되지 않는 테스트 또는 검토 가능한 wrapper가 있습니다. |
| S0-09 | M | GRDB 초기화와 v1 migration 구현 | S0-03, S0-04 | 사용자 Application Support에 DB를 생성하고 WAL/foreign key/busy timeout 설정, LLD 전체 DDL migration과 in-memory migration test가 통과합니다. |
| S0-10 | S | 공통 테스트 fixture와 Stub 기반 구성 | S0-05, S0-07 | 고정 Clock, UUID generator, 임시 DB, Stub URLProtocol과 fixture 디렉터리를 후속 테스트에서 재사용할 수 있습니다. |

Sprint 종료 데모:

- 앱을 실행하면 빈 메뉴 막대 항목이 나타납니다.
- CLI와 모든 테스트 타깃이 로컬에서 빌드됩니다.
- 임시 DB에 v1 스키마를 생성하고 종료할 수 있습니다.

## 3. Sprint 1 — 할 일과 로컬 하루 요약

목표: 네트워크 없이 할 일을 관리하고 어제 한 일·오늘 할 일을 표시합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S1-01 | S | Task DB record와 Domain mapping | S0-09 | 모든 nullable 필드와 enum mapping이 round-trip되며 잘못된 DB 값은 명시적 오류가 됩니다. |
| S1-02 | S | 할 일 생성·날짜별 조회 repository | S1-01 | 빈 제목/200자 초과를 거부하고 `taskDay`, `status`, `sortOrder` 순 조회 integration test가 통과합니다. |
| S1-03 | S | 할 일 제목·메타데이터 수정 repository | S1-02 | 제목, 중요도, 예상 시간, 링크, 프로젝트 경로 수정과 `updatedAt` 갱신을 검증합니다. |
| S1-04 | S | 완료·미완료 상태 전환 repository | S1-02 | 상태와 `completedAt` 불변식을 한 transaction에서 지키고 양방향 전환을 테스트합니다. |
| S1-05 | XS | 할 일 삭제 repository | S1-02 | 대상 한 건만 삭제되며 존재하지 않는 ID 처리가 결정적으로 동작합니다. |
| S1-06 | S | 할 일 순서 변경 repository | S1-02 | 같은 날짜 목록의 `sortOrder`를 transaction으로 재계산하고 중복 순서를 남기지 않습니다. |
| S1-07 | S | 어제 미완료 항목 가져오기 use case | S1-02 | 선택한 항목을 오늘 날짜의 새 ID로 복제하고 원본은 유지합니다. 복사 provenance와 DB unique 제약으로 반복 요청·재시작 후에도 같은 날짜에 중복 이월되지 않습니다. |
| S1-08 | S | 어제 한 일·오늘 할 일 요약 use case | S1-04 | 사용자 Calendar 기준 전날 완료 항목과 오늘 항목을 API 호출 없이 결정적으로 반환합니다. |
| S1-09 | S | MenuBarExtra 기본 화면과 섹션 구성 | S0-07 | 날짜, 어제 완료, 오늘 할 일, 에이전트, 브리핑 영역의 empty state를 keyboard로 탐색할 수 있습니다. |
| S1-10 | M | 할 일 목록 관찰과 완료 UI | S1-04, S1-09 | GRDB 변경이 목록에 반영되고 체크 동작, 중요 표시와 예상 시간이 올바르게 보입니다. |
| S1-11 | M | 할 일 추가·편집·삭제 UI | S1-03, S1-05, S1-10 | validation, 저장, 취소, 삭제 확인 흐름을 UI test로 검증합니다. |
| S1-12 | S | 순서 변경과 미완료 가져오기 UI | S1-06, S1-07, S1-10 | pointer reorder와 keyboard 이동이 동작하고, 가져온 항목은 즉시 후보에서 사라지며 재시작 후에도 제외됩니다. |

Sprint 종료 데모:

- 할 일을 추가·수정·완료·삭제·재정렬할 수 있습니다.
- 다음 날짜로 Clock을 이동하면 완료 항목이 “어제 한 일”에 나타납니다.
- 앱을 재실행해도 데이터가 유지됩니다.

## 3.1 Sprint 1.5 — 메뉴 막대 UI Polish

목표: Sprint 1 기능을 유지하면서 소프트 블루 기반의 compact native UI, 전용 drag handle과 light/dark·keyboard 접근성 기반을 정리합니다.

상세 계획: [Sprint 1.5 UI Polish](SPRINT_1_5_UI_POLISH.md)

관련 결정: [ADR-0011](adr/0011-soft-blue-native-menu-bar-visual-system.md)

직접 확인: [Sprint 1.5 데모 체크리스트](SPRINT_1_5_DEMO_CHECKLIST.md)

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S1.5-01 | XS | Soft-blue semantic token 구성 | S1-12 | `MoraeAccent` light/dark asset과 semantic foreground/background token이 native control에 적용됩니다. |
| S1.5-02 | S | 패널·header·section hierarchy 정리 | S1.5-01 | 392pt 패널, compact header, 지역화 날짜와 section count가 ScrollView에서 잘리지 않습니다. |
| S1.5-03 | S | Compact TodoRow 컴포넌트 분리 | S1.5-01 | checkbox, 중요도, 제목, 예상 시간과 action 영역이 재사용 가능한 row로 분리됩니다. |
| S1.5-04 | M | drag affordance와 insertion indicator 구현 | S1.5-03 | pending 행에서 3pt 이상 이동하면 로컬 drag가 시작되고 insertion line과 확정 gesture당 한 번의 reorder 저장을 검증합니다. 6-dot handle과 keyboard 이동 action을 함께 제공합니다. |
| S1.5-05 | S | Inline 편집·삭제·undo panel 정리 | S1.5-03 | 버튼 클릭 중 메뉴 패널이 닫히지 않고 저장·취소·삭제·undo focus가 예측 가능하게 동작합니다. |
| S1.5-06 | S | Empty·error·validation 상태 통일 | S1.5-02, S1.5-03 | 네 section과 오류 상태가 공통 layout, 색상과 VoiceOver 문구를 사용합니다. |
| S1.5-07 | S | Light/dark·keyboard·회귀 검증 | S1.5-04, S1.5-05, S1.5-06 | appearance별 checklist, keyboard-only 흐름과 기존 Sprint 1 테스트가 모두 통과합니다. |

Sprint 종료 데모:

- light/dark 모드에서 소프트 블루 accent와 native material이 일관되게 표시됩니다.
- pending 행 pointer drag, insertion indicator와 keyboard 순서 이동이 모두 동작합니다.
- 추가·완료·편집·삭제·undo 중 메뉴 패널이 닫히지 않습니다.
- 긴 제목과 empty/error 상태가 392pt 패널 안에서 잘리지 않습니다.

## 4. Sprint 2 — 아티클 메타데이터 수집·선정

목표: 신뢰할 수 있는 피드에서 제목, 링크, 출처와 게시일을 읽어 최근
아티클 한 개를 선정합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S2-01 | S | 기본 피드 fixture와 seed 구현 | S0-09 | 검증된 HTTPS RSS/Atom URL을 설정 파일에 두고 versioned marker로 seed합니다. |
| S2-02 | S | 제한된 URLSession HTTPClient 구현 | S0-10 | HTTPS, timeout, redirect, response size, cookie/credential 비사용 정책을 Stub URLProtocol로 검증합니다. |
| S2-03 | M | FeedKit RSS 메타데이터 mapping 구현 | S2-01, S2-02 | 자체 제작 RSS fixture의 제목, 링크, 출처와 게시일을 `FeedCandidate`로 변환하고 필수값 validation과 날짜 실패 처리를 테스트합니다. |
| S2-04 | M | FeedKit Atom 메타데이터 mapping 구현 | S2-01, S2-02 | 자체 제작 Atom fixture의 제목, 링크, 출처와 게시일을 같은 중간 모델로 변환하며 summary/content는 모델에 포함하지 않습니다. |
| S2-05 | S | URL canonicalization 구현 | S0-05 | fragment, 기본 port, tracking query 제거와 query 정렬을 table-driven test로 검증합니다. |
| S2-06 | S | 후보 deduplication 구현 | S2-03, S2-04, S2-05 | canonical URL이 같은 RSS/Atom 항목을 한 후보로 합치고 결과가 입력 순서에 의존하지 않습니다. |
| S2-07 | M | 아티클 선정 점수 구현 | S2-06 | freshness, 관심사, 공식 출처, 읽음/최근 추천 감점과 동점 규칙을 고정 Clock으로 검증합니다. |
| S2-08 | S | Article repository와 최근 추천 조회 구현 | S0-09, S2-05 | canonical URL unique 처리, 읽음/좋아요, 최근 90일 추천 조회가 integration test를 통과합니다. |

Sprint 종료 데모:

- 고정 피드 fixture에서 아티클 한 개를 재현 가능하게 선정합니다.
- 결과에는 제목, 링크, 출처와 게시일만 포함되고 피드 본문·요약은 저장되지 않습니다.

구현 결과:

- S2-01~S2-08을 task별 커밋으로 구현하고 현재 브랜치에 푸시했습니다.
- 고정 RSS/Atom fixture를 한 후보 집합으로 파싱한 뒤 입력 순서를 뒤집어도
  같은 canonical URL을 고르는 통합 테스트가 통과합니다.
- Sprint 2는 화면과 네트워크 실행을 연결하지 않습니다. 사용자의 버튼
  클릭 한 번에만 피드를 조회하는 조립은 Sprint 3에서 구현합니다.
- 상세 재현 절차는 [Sprint 2 데모 체크리스트](SPRINT_2_DEMO_CHECKLIST.md)를
  따릅니다.

## 5. Sprint 3 — 수동 브리핑

목표: 사용자가 버튼을 누른 경우에만 로컬 할 일 요약과 추천 아티클 링크를 한 번 생성합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S3-01 | S | BriefingRun repository 구현 | S0-09, S2-08 | `running` 생성과 `succeeded`/`failed` 종료를 transaction으로 저장합니다. |
| S3-02 | M | GenerateBriefing 정상 흐름 조립 | S1-08, S2-07, S3-01 | 사용자 호출 한 번에 최대 4개 feed를 동시에 조회하고 local task summary, article 선정과 저장을 각각 한 번 수행합니다. |
| S3-03 | S | 피드 실패와 무재시도 정책 구현 | S3-02 | 일부 피드는 성공 후보를 계속 사용하고 모두 실패하면 로컬 할 일 요약을 보존하며 동일 실행 내 두 번째 요청이 없습니다. |
| S3-04 | S | 브리핑 ViewModel 상태 머신 | S3-02, S3-03 | `idle/loading/success/failure` 전이가 정의되고 loading 중 중복 trigger를 막습니다. |
| S3-05 | M | 브리핑 생성 버튼과 결과 UI | S3-04, S1-09 | 제목·출처·게시일·원문 링크와 피드 실패 UI를 표시하고 원문은 기본 브라우저에서 엽니다. |
| S3-06 | S | 첫 브리핑 최우선 할 일 질문 | S1-02, S3-05 | 해당 날짜 첫 생성에만 선택적으로 표시하고 답변을 중요 할 일로 저장하며 건너뛰기를 지원합니다. |
| S3-07 | S | 브리핑 재실행·재시작 통합 테스트 | S3-05 | 버튼 한 번당 run 하나, retry 버튼 없음, 앱 재실행 후 마지막 결과 유지가 검증됩니다. |

Sprint 종료 데모:

- 수동 브리핑에서 추천 아티클의 제목·출처·게시일·원문 링크가 표시됩니다.
- 피드 실패 시에도 가능한 로컬 할 일 결과가 남습니다.
- 앱 실행이나 화면 열기만으로 네트워크 요청이 발생하지 않습니다.

구현 결과:

- S3-01~S3-07을 task별 커밋으로 구현하고 현재 브랜치에 푸시했습니다.
- 피드별 요청 1회, 최대 4개 동시 조회, 부분·전체 실패와 loading 중 중복
  trigger 차단을 자동화 테스트로 검증합니다.
- 첫 브리핑 질문의 중요 할 일 저장·건너뛰기와 같은 날짜 질문 미반복을
  검증합니다.
- 임시 DB를 닫고 다시 여는 통합 테스트에서 실행당 run 한 건과 최신
  브리핑 복원을 검증합니다.
- 직접 확인은 [Sprint 3 데모 체크리스트](SPRINT_3_DEMO_CHECKLIST.md)를
  따릅니다.

## 5.1 Sprint 3.1 — 추천 소스 품질

목표: 제품 공식 공지보다 사람이 선별한 개발·프론트엔드 읽을거리를
우선 추천합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S3.1-01 | S | 큐레이션 기본 피드 전환 | S2-01 | GeekNews, FE News, Frontend Focus, JavaScript Weekly 공식 피드를 기본으로 사용합니다. |
| S3.1-02 | S | 소스 선정 가중치 | S2-07 | `selectionWeight`가 파싱·중복 제거 후에도 보존되고 최신성보다 높은 큐레이션 후보를 선택할 수 있습니다. |
| S3.1-03 | S | 기존 설치 기본 피드 전환 | S3.1-01 | v2 marker 적용 시 기존 네 기본 피드만 비활성화하고 새 기본 피드를 한 번 추가하며 사용자 정의 피드를 유지합니다. |
| S3.1-04 | XS | 추천 소스 ADR·회귀 검증 | S3.1-02, S3.1-03 | ADR-0013과 코드·문서가 일치하고 전체 테스트가 통과합니다. |

## 6. Sprint 4 — 에이전트 IPC

목표: 앱 실행 중 Codex/Claude 이벤트 하나를 안전하게 전달하고 ACK를 반환합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S4-01 | S | AgentTransportEnvelope와 framing 구현 | S0-06 | 4-byte big-endian 길이, Codable envelope, transport version과 1 MiB frame 경계를 테스트합니다. |
| S4-02 | S | CLI argv/stdin 입력 parser 구현 | S4-01 | Codex argv와 Claude subcommand/stdin을 구분하고 raw 입력 760 KiB 및 최종 frame 1 MiB 상한을 모두 검증합니다. |
| S4-03 | S | UDS client와 ACK decoder 구현 | S4-02 | process 시작 기준 900ms total deadline, connect 최대 250ms, 남은 시간을 공유하는 write+ACK를 적용하고 ACK를 구분합니다. |
| S4-04 | XS | best-effort CLI 종료 정책 구현 | S4-03 | 성공·앱 미실행·timeout·invalid subcommand/payload/ACK 모두 출력 없이 exit 0이며 재시도·spool이 없습니다. |
| S4-05 | M | UDS server lifecycle 구현 | S0-07, S4-01 | 앱 시작/종료에 맞춰 bind/listen/close하고 connection당 frame 하나, 동시 최대 8개를 처리합니다. |
| S4-06 | S | socket 경로·권한 검증 구현 | S4-05 | 부모 `0700`, socket `0600`, owner UID, symlink 방어와 안전한 stale socket 처리 테스트가 통과합니다. |
| S4-07 | S | peer UID·frame validation 구현 | S4-05, S4-06 | 다른 UID, 0 byte, 초과 크기, partial read, 잘못된 version을 저장 전에 거부합니다. |
| S4-08 | S | ACK writer와 민감정보 없는 오류 code | S4-07 | DB 저장 이후 성공 ACK, validation 실패 오류 ACK를 보내며 raw body가 로그에 없습니다. |
| S4-09 | S | CLI·server 전송 integration test | S4-04, S4-08 | 임시 socket에서 partial I/O와 정상 round-trip을 실제 client/server로 검증합니다. |

Sprint 종료 데모:

- 실행 중인 앱에 CLI fixture를 보내면 ACK를 받습니다.
- 앱이 꺼져 있으면 CLI가 빠르게 성공 종료하고 아무 파일도 남기지 않습니다.
- 과대 payload와 권한이 잘못된 socket을 거부합니다.

## 7. Sprint 5 — 에이전트 정규화·기록·알림

목표: Codex와 Claude의 여러 턴을 구분해 저장하고 상태별 UI와 알림을 제공합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S5-01 | S | NormalizedAgentEvent validation 구현 | S0-06 | 필수 식별자, 허용 source event, status, 시간과 개인정보 optional 필드를 검증합니다. |
| S5-02 | S | Codex notify DTO와 normalizer | S5-01 | `agent-turn-complete`만 `responded`로 변환하고 원본 `thread-id`/`turn-id`를 유지합니다. |
| S5-03 | M | Claude Hook DTO와 event mapping | S5-01 | 다섯 Hook을 상태로 변환하되 Notification은 `permission_prompt`, `elicitation_dialog`, `agent_needs_input`만 허용하고 transcript 경로를 버립니다. |
| S5-04 | M | Claude turn correlation 구현 | S5-03 | `prompt_id` 우선, 필드 누락 시 UUID/최신 열린 턴 fallback, Stop/StopFailure close와 superseded turn을 테스트합니다. |
| S5-05 | M | Agent repository upsert와 event dedup | S0-09, S5-01 | `(source, sessionId, turnId)` unique, `eventKey` idempotency와 status rank 비강등을 transaction으로 검증합니다. |
| S5-06 | S | ReceiveAgentEvent use case와 ACK 연결 | S4-08, S5-02, S5-04, S5-05 | decode→normalize→save 순서와 저장 성공 뒤 ACK를 end-to-end로 검증합니다. |
| S5-07 | S | 90일 보존 정리 구현 | S5-05 | 앱 시작 및 하루 한 번 저장 후 prune, 90일 경계와 AgentEvent cascade를 고정 Clock으로 검증합니다. |
| S5-08 | S | 에이전트 기록 목록 ViewModel | S5-05 | 최근 수신 순, projectPath 그룹, unread 상태를 관찰하고 privacy off에서도 동작합니다. |
| S5-09 | M | 에이전트 기록 메뉴 UI | S5-08, S1-09 | source와 상태를 표시하고 responded/complete 문구·색상을 구분하며 generic row fallback이 있습니다. |
| S5-10 | S | macOS notification adapter | S5-06 | 기본 알림은 source/status만 포함하고 동일 turn의 중복 종료 알림을 보내지 않습니다. |
| S5-11 | S | 알림 권한 거부와 unread dot | S5-09, S5-10 | 거부·비활성 상태에서 메뉴 막대 dot가 나타나고 목록 확인 시 읽음 처리됩니다. |
| S5-12 | S | Codex·Claude fixture E2E 테스트 | S5-06, S5-10 | 지원 event는 기대 turn/status로 한 번 저장·알림되고 비대상 Notification은 저장 전에 거부됩니다. |

Sprint 종료 데모:

- 서로 다른 Codex turn 두 개가 별도 기록됩니다.
- Claude Notification→TaskCompleted→Stop이 한 turn에 연결되고 상태가 강등되지 않습니다.
- 앱 창이 닫혀 있어도 앱 프로세스가 실행 중이면 알림이 표시됩니다.

## 8. Sprint 6 — 설정·개인정보·출시 검증

목표: 사용자가 안전하게 설정하고 본인 Mac의 macOS 14 환경에서 MVP 완료 조건을 검증합니다.

| ID | 크기 | 태스크 | 선행 | 완료·검토 기준 |
| --- | --- | --- | --- | --- |
| S6-01 | S | 표준 UserDefaults 설정 저장소 | S0-07 | `UserDefaults.standard`에서 LLD schemaVersion과 모든 기본값을 typed API로 제공하고 잘못된 값에 안전하게 fallback합니다. |
| S6-02 | M | 개인정보 opt-in 저장 정책 적용 | S5-05, S6-01 | projectPath/title/lastMessage 각각 기본 off이며 off인 필드는 정규화 후 DB에 저장되지 않습니다. |
| S6-03 | S | 개인정보 opt-in 해제 scrub | S6-02 | 설정을 끄면 해당 기존 DB column을 한 transaction에서 NULL로 만들고 되돌릴 수 없음을 UI에 알립니다. |
| S6-04 | S | 상세 알림 opt-in 적용 | S5-10, S6-01 | 기본 generic 알림과 명시적 opt-in 상세 알림을 구분하고 잠금 화면 노출 주의를 표시합니다. |
| S6-05 | M | 설정 화면 기본 섹션 구현 | S6-01 | 관심사, 피드, 개인정보, 알림 권한, 로그인 실행 상태를 분리해 편집할 수 있습니다. |
| S6-06 | S | 사용자 RSS/Atom 피드 관리 UI | S2-01, S6-05 | HTTPS URL 추가, 활성화, 삭제, 중복 URL validation과 파싱 실패 메시지가 동작합니다. |
| S6-07 | S | Codex·Claude 설정 snippet UI | S4-04, S6-05 | 확정 CLI 경로와 subcommand가 포함된 snippet을 복사할 수 있고 외부 설정 파일을 수정하지 않으며 Claude Code 2.1.198 미만에는 호환성 안내를 표시합니다. |
| S6-08 | S | 로그인 시 실행 설정 | S6-01, S6-05 | 기본 off, 사용자 toggle에 의한 등록/해제와 실패 안내를 검증합니다. |
| S6-09 | S | 알림 설정 안내와 시스템 설정 이동 | S5-11, S6-05 | 권한 상태를 표시하고 거부 시 사용자가 System Settings에서 복구할 경로를 제공합니다. |
| S6-10 | M | 접근성·keyboard·VoiceOver 점검 | S3-05, S5-09, S6-05 | 주요 버튼/상태 label, focus 순서, 색상 외 상태 문구, keyboard 조작을 UI test와 수동 점검으로 확인합니다. |
| S6-11 | S | 개인정보·로그 redaction 감사 | S5-12, S6-03 | fixture 실행 후 DB와 수집 로그에 raw Hook payload, feed body와 transcript path가 없음을 확인합니다. |
| S6-12 | M | 전체 재실행·데이터 유지 인수 테스트 | S3-07, S5-12, S6-11 | README 완료 조건 1~6을 자동화 가능한 부분과 수동 checklist로 모두 통과합니다. |
| S6-13 | M | 본인 전용 DMG 생성·로컬 설치 테스트 | S6-12 | 앱과 nested CLI를 로컬 실행용으로 서명해 DMG를 만들고, 본인 사용자 앱 디렉터리에 복사한 뒤 첫 실행, 피드 조회, 알림과 Codex/Claude snippet 흐름을 검증합니다. |

Sprint 종료 데모:

- 개인정보 기본값이 모두 보수적으로 동작합니다.
- README의 MVP 완료 조건 6개가 추적 가능한 증거와 함께 통과합니다.
- 본인 전용 DMG를 macOS 14 환경에 설치해 실행할 수 있습니다.

## 9. 요구사항 추적

| README MVP 완료 조건 | 주요 태스크 |
| --- | --- |
| 1. 메뉴 막대에 모래 표시 | S0-01, S1-09 |
| 2. 수동 브리핑에서 아티클·한 일·할 일 확인 | S1-08, S2-07, S3-02~S3-05 |
| 3. 할 일 CRUD와 다음 날 완료 내역 | S1-02~S1-12 |
| 4. Claude/Codex 여러 턴 분리 | S5-02~S5-06, S5-12 |
| 5. 앱 실행 중 종료·완료·실패 알림 | S4-01~S4-09, S5-10~S5-12 |
| 6. 앱 재실행 후 데이터 유지 | S0-09, S3-07, S6-12 |

| 횡단 요구사항 | 주요 태스크 |
| --- | --- |
| 수동 실행·무재시도 | S3-02~S3-04, S4-04 |
| 피드 메타데이터만 처리 | S2-03, S2-04, S3-02 |
| 최소 이벤트 저장 | S5-01~S5-06, S6-02~S6-04 |
| 에이전트 기록 90일 보존 | S5-07 |
| 설정 파일 수동 온보딩 | S6-07 |
| 알림 거부 fallback | S5-11, S6-09 |
| 개인용 DMG·macOS 14 | S6-13 |

## 10. 명시적 비범위

다음 항목은 MVP Sprint에 추가하지 않습니다.

- 예약 오전 브리핑과 Slack 전송
- 백그라운드 RSS 수집과 자동 재시도
- AI 기반 아티클 요약과 아티클 원문 HTML 수집
- WidgetKit 위젯과 마스코트 애니메이션
- 계정, 클라우드 동기화와 팀 기능
- Git, GitHub, 미리 알림, 캘린더, Notion 연동
- Codex App Server 기반 실행 중·승인·실패 추적
- 에이전트 작업 실행과 자동 완료 판정

새 요구가 생기면 기존 태스크에 몰래 포함하지 않고 별도 backlog 항목과 설계 변경 여부를 먼저 검토합니다.

## 11. 외부 준비 상태

현재 외부 준비 항목은 모두 완료됐으며 구현을 막는 외부 블로커가 없습니다. Anthropic API 키, Apple Developer Program, Developer ID 인증서와 별도 Mac은 필요하지 않습니다.

| 항목 | 상태 | 확인 결과 |
| --- | --- | --- |
| 큐레이션 피드 URL·이용 정책 | 완료 (2026-07-30) | GeekNews, FE News, Frontend Focus, JavaScript Weekly의 공식 HTTPS 피드와 XML을 확인했습니다. 제목·링크·출처·게시일만 사용하는 정책을 유지합니다. |
