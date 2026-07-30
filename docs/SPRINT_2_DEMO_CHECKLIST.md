# Sprint 2 데모 체크리스트

> 상태: 완료
> 최종 수정: 2026-07-30
> 범위: 아티클 메타데이터 수집·선정 기반

## 1. 데모 목표

Sprint 2는 화면 기능이 아니라 수동 브리핑에 필요한 기반을 검증합니다.
자체 제작 RSS/Atom fixture에서 제목, 링크, 출처와 게시일만 읽고, 입력
순서와 무관하게 같은 아티클 한 개를 선택해야 합니다.

앱 실행이나 메뉴 열기만으로 실제 피드를 요청하지 않습니다. 사용자가
브리핑 버튼을 클릭했을 때의 네트워크 실행과 결과 UI는 Sprint 3
범위입니다.

## 2. 자동화 데모

Xcode에서 `MoraeApp` scheme의 다음 테스트를 실행합니다.

```text
FeedParsingTests
└── testSprintTwoDemoDeterministicallySelectsOneMetadataCandidate
```

터미널에서는 다음 명령으로 같은 검증을 재현할 수 있습니다.

```bash
xcodebuild test \
  -project Morae.xcodeproj \
  -scheme MoraeApp \
  -destination 'platform=macOS' \
  -only-testing:MoraeAppTests/FeedParsingTests/testSprintTwoDemoDeterministicallySelectsOneMetadataCandidate
```

확인 항목:

- RSS와 Atom fixture를 같은 `FeedCandidate` 모델로 변환합니다.
- 후보 입력 순서를 뒤집어도 같은 결과를 선택합니다.
- tracking query가 제거된 canonical URL을 사용합니다.
- 선택 결과에는 제목, 링크, 출처와 게시일만 있습니다.
- fixture의 description, summary와 content는 도메인 모델이나 DB에
  저장하지 않습니다.

## 3. 전체 회귀 검증

2026-07-30 기준 다음 63개 테스트가 통과합니다.

| Scheme | 테스트 수 |
| --- | ---: |
| `MoraeApp` | 46 |
| `MoraeCore` | 16 |
| `HamsterEventCLI` | 1 |

각 scheme은 Xcode의 Test action 또는 아래 형태의 명령으로 실행합니다.

```bash
xcodebuild test \
  -project Morae.xcodeproj \
  -scheme <SCHEME_NAME> \
  -destination 'platform=macOS'
```

## 4. Sprint 3로 넘기는 범위

- 메뉴 막대의 브리핑 버튼 활성화
- 버튼 한 번당 실제 enabled feed 최대 4개 조회
- 로컬 한 일/할 일 요약과 추천 아티클 결과 조립
- 로딩 중 중복 실행 방지, 일부/전체 피드 실패와 무재시도 처리
- 마지막 성공 결과 저장과 화면 표시
