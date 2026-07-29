# ADR-0009: 본인 전용 DMG와 일반 사용자 저장소

- 상태: Accepted
- 날짜: 2026-07-29

## Context

MVP는 개발자 본인만 사용하는 macOS 앱이며 공개 배포, 다른 사용자 설치 지원과 WidgetKit은 범위 밖입니다. Developer ID 서명·공증과 App Group은 Apple Developer Program 가입 및 추가 설정이 필요하지만 현재 범위에서는 얻는 이점이 작습니다.

## Decision

- 배포 산출물은 본인 전용 DMG로 한정합니다.
- 앱과 번들 내부 CLI는 로컬 실행용 서명(`Sign to Run Locally` 또는 ad-hoc)을 사용합니다.
- Developer ID 서명, 공증과 App Group entitlement는 MVP에서 사용하지 않습니다.
- SQLite는 `~/Library/Application Support/Morae/morae.sqlite`에 저장합니다.
- 설정은 `UserDefaults.standard`에 저장합니다.
- Bundle ID `io.github.heejung-29cm.morae`는 로컬 식별자로 유지합니다.
- 공개 배포 또는 WidgetKit 요구가 생기면 새 ADR에서 Developer ID·공증 또는 App Group 도입과 기존 데이터 이전을 함께 결정합니다.

## Consequences

### Positive

- 유료 Apple Developer Program 없이 MVP를 구현하고 본인 Mac에서 사용할 수 있습니다.
- entitlement와 provisioning 설정이 줄어 빌드와 저장소 구성이 단순해집니다.
- 현재 필요한 로컬 데이터와 설정은 macOS 표준 사용자 디렉터리에 유지됩니다.

### Negative

- 타인에게 배포할 때 Gatekeeper 경고 없는 설치 경험을 제공하지 못합니다.
- 향후 WidgetKit 도입 시 저장소를 App Group으로 이전해야 합니다.
- 공개 배포로 전환할 때 서명·공증 파이프라인과 설치 검증을 새로 구성해야 합니다.

## Alternatives

- Developer ID 서명과 공증: 공개 배포에는 적합하지만 본인 전용 MVP에는 비용과 설정 부담이 큽니다.
- App Group 선도입: WidgetKit 데이터 공유에는 유리하지만 현재 범위에는 불필요한 entitlement와 계정 의존성을 만듭니다.
- Mac App Store: App Sandbox와 외부 Hook 실행 파일 경로 제약 때문에 MVP 구조에 맞지 않습니다.
