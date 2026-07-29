# Sprint 1.5 직접 실행 체크리스트

> 대상: `MoraeApp` / macOS 14 이상  
> 기준: Sprint 1.5 UI Polish 완료 빌드

## 1. 실행

1. Xcode에서 `MoraeApp` scheme과 `My Mac` destination을 선택합니다.
2. 이전 Morae가 실행 중이면 Xcode의 Stop 버튼으로 종료합니다.
3. Run을 누른 뒤 메뉴 막대의 모래시계 아이콘을 클릭합니다.
4. 패널이 392pt 폭으로 열리고 세로 내용이 ScrollView 안에 표시되는지 확인합니다.

## 2. Light/Dark 캡처

- [ ] 시스템 설정 → 모양 → 라이트를 선택하고 전체 패널을 캡처합니다.
- [ ] 소프트 블루가 체크, 주요 버튼, 편집 패널과 undo 배너에 일관되게 보입니다.
- [ ] 본문·보조 텍스트·separator가 배경과 구분됩니다.
- [ ] 시스템 설정 → 모양 → 다크를 선택하고 같은 상태를 캡처합니다.
- [ ] 다크용 소프트 블루가 라이트용보다 밝고 control 상태가 구분됩니다.
- [ ] empty, validation, error 상태가 색상 외에도 아이콘과 문구로 구분됩니다.

권장 캡처 상태:

1. 네 섹션의 empty state
2. pending·important·completed 할 일이 함께 있는 목록
3. 편집 패널
4. 삭제 확인과 undo 배너
5. 긴 한국어·영문 제목이 두 줄로 표시되는 목록

## 3. Pointer와 Drag

- [ ] pending 행의 6-dot 핸들에서만 drag가 시작됩니다.
- [ ] drag 중 원본 행이 흐려지고 대상 앞에 2pt 소프트 블루 선이 나타납니다.
- [ ] drop 후 순서가 변경되며 앱을 다시 실행해도 유지됩니다.
- [ ] 이미 같은 위치인 drop은 목록을 변경하지 않습니다.
- [ ] checkbox, 편집, 삭제 버튼 클릭은 drag를 시작하지 않습니다.
- [ ] completed 행에는 drag handle이 없습니다.

## 4. Keyboard

- [ ] 빠른 추가 필드에서 제목을 입력하고 Return으로 저장합니다.
- [ ] Tab과 Shift-Tab으로 checkbox, 위·아래 이동, 편집, 삭제 버튼에 접근합니다.
- [ ] 위·아래 이동 버튼으로 pending 순서를 변경합니다.
- [ ] 편집을 열면 제목 필드에 focus가 오며 Return으로 저장하고 Escape로 취소합니다.
- [ ] 삭제 확인을 열면 취소 버튼에 focus가 오며 Escape로 닫힙니다.
- [ ] 삭제 직후 5초 안에 undo 버튼 또는 Command-Z로 복구합니다.

## 5. VoiceOver와 회귀

- [ ] VoiceOver에서 section 제목과 항목 개수를 읽습니다.
- [ ] 완료 상태, 중요도, 예상 시간과 각 행 action을 색상 없이 이해할 수 있습니다.
- [ ] drag handle과 위·아래 이동 accessibility action을 읽고 실행할 수 있습니다.
- [ ] 빈 상태, 입력 오류와 startup 오류의 종류·메시지·복구 문구를 읽습니다.
- [ ] 어제 미완료 가져오기, 완료 전환, 편집, 삭제와 undo가 기존과 동일하게 동작합니다.
