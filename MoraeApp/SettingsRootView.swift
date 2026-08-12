import AppKit
import MoraeCore
import SwiftUI

struct SettingsRootView: View {
    private let container: AppContainer
    @State private var model: SettingsModel
    @State private var interestsText: String
    @State private var feedName = ""
    @State private var feedURL = ""
    @State private var jiraSiteURL = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jiraStartDateFieldID = ""

    init(container: AppContainer) {
        self.container = container
        let model = SettingsModel(
            store: container.settingsStore,
            agentRepository: container.agentRepository,
            feedRepository: container.feedSourceRepository,
            notifier: container.agentNotifier,
            launchAtLogin: container.launchAtLoginController,
            clock: container.clock,
            uuidGenerator: container.uuidGenerator,
            jiraIntegration: container.jiraIntegration,
            hookInstaller: container.hookInstaller
        )
        _model = State(initialValue: model)
        _interestsText = State(
            initialValue: model.settings.interests.joined(separator: ", ")
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if container.runtimeProfile.isFreshTest {
                Label(
                    "첫 실행 테스트 모드 · 기존 데이터와 설정은 변경되지 않습니다",
                    systemImage: "testtube.2"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(MoraeColor.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(MoraeColor.subtleFill)
            }
            TabView {
                general
                    .tabItem { Label("일반", systemImage: "gearshape") }
                briefing
                    .tabItem { Label("아티클", systemImage: "sparkles") }
                agents
                    .tabItem { Label("에이전트", systemImage: "terminal") }
                integrations
                    .tabItem {
                        Label("연동", systemImage: "puzzlepiece.extension")
                    }
                privacy
                    .tabItem {
                        Label("개인정보", systemImage: "hand.raised")
                    }
                about
                    .tabItem { Label("정보", systemImage: "info.circle") }
            }
        }
        .frame(width: 720, height: 600)
        .task { await model.refresh() }
        .alert(
            "설정을 완료하지 못했습니다",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var integrations: some View {
        Form {
            Section("Jira Cloud") {
                if let connection = model.jiraSnapshot.connection {
                    LabeledContent("상태") {
                        Label("연결됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    LabeledContent("사이트") {
                        Text(
                            connection.displayBaseURL.host
                                ?? connection.displayBaseURL.absoluteString
                        )
                        .textSelection(.enabled)
                    }
                    LabeledContent("계정") {
                        Text(connection.accountEmail)
                            .textSelection(.enabled)
                    }
                    LabeledContent("시작 날짜") {
                        Text(
                            connection.startDateFieldID
                                ?? "사용하지 않음 (기한 기준)"
                        )
                    }
                    if let lastSync =
                        model.jiraSnapshot.lastSuccessfulSyncAt {
                        LabeledContent("마지막 성공") {
                            Text(
                                lastSync.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                        }
                    }
                    HStack {
                        Button(
                            model.isJiraBusy ? "가져오는 중…" : "지금 가져오기"
                        ) {
                            Task { await model.syncJiraNow() }
                        }
                        .disabled(model.isJiraBusy)
                        Spacer()
                        Button("연결 해제", role: .destructive) {
                            Task { await model.disconnectJira() }
                        }
                        .disabled(model.isJiraBusy)
                    }
                } else {
                    jiraStep(
                        number: 1,
                        title: "Jira 사이트 주소"
                    ) {
                        TextField(
                            "https://your-team.atlassian.net 또는 사내 Jira 주소",
                            text: $jiraSiteURL
                        )
                        Text(
                            "브라우저에서 이슈를 볼 때 사용하는 주소를 입력하세요."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    jiraStep(
                        number: 2,
                        title: "Atlassian 계정"
                    ) {
                        TextField(
                            "Atlassian 계정 이메일",
                            text: $jiraEmail
                        )
                        HStack {
                            SecureField(
                                "API token 전체 값",
                                text: $jiraToken
                            )
                            Button("붙여넣기") {
                                if let value = NSPasteboard.general
                                    .string(forType: .string) {
                                    jiraToken = value
                                        .trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        )
                                }
                            }
                        }
                        HStack {
                            Link(
                                "API token 만들기",
                                destination: URL(
                                    string:
                                        "https://id.atlassian.com/manage-profile/security/api-tokens"
                                )!
                            )
                            Spacer()
                            Text("토큰은 자르지 않고 전체를 붙여넣으세요.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    if !model.jiraStartDateFields.isEmpty {
                        Divider()
                        jiraStep(
                            number: 3,
                            title: "시작 날짜 필드"
                        ) {
                            Picker(
                                "시작 날짜 필드",
                                selection: $jiraStartDateFieldID
                            ) {
                                Text("선택해 주세요").tag("")
                                ForEach(model.jiraStartDateFields) { field in
                                    Text(
                                        "\(field.displayName) · \(field.id)"
                                    )
                                    .tag(field.id)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    Divider()
                    HStack {
                        Text(
                            container.runtimeProfile.isFreshTest
                                ? "연결 확인은 실제 Jira를 조회하지만 토큰은 테스트 프로세스의 메모리에만 보관됩니다."
                                : "연결 확인은 조회만 수행하며 토큰은 이 Mac의 Keychain에만 저장됩니다."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button(
                            model.isJiraBusy
                                ? "확인 중…"
                                : model.jiraStartDateFields.isEmpty
                                    ? "연결 확인 및 저장"
                                    : "선택 후 연결"
                        ) {
                            Task {
                                let connected = await model.connectJira(
                                    siteURL: jiraSiteURL,
                                    email: jiraEmail,
                                    token: jiraToken,
                                    startDateFieldID:
                                        jiraStartDateFieldID.isEmpty
                                        ? nil
                                        : jiraStartDateFieldID
                                )
                                if connected {
                                    jiraToken = ""
                                }
                            }
                        }
                        .disabled(
                            model.isJiraBusy
                                || jiraSiteURL.isEmpty
                                || jiraEmail.isEmpty
                                || jiraToken.isEmpty
                                || (
                                    !model.jiraStartDateFields.isEmpty
                                        && jiraStartDateFieldID.isEmpty
                                )
                        )
                    }
                }

                if let message = model.jiraStatusMessage {
                    Label(
                        message,
                        systemImage: model.jiraStatusIsError
                            ? "exclamationmark.circle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        model.jiraStatusIsError
                            ? Color.red
                            : Color.secondary
                    )
                }
            }

            Section("자동 가져오기") {
                Text(
                    "앱을 열거나 날짜가 바뀔 때 하루 한 번만 시도합니다. In Progress이거나 시작일·기한이 오늘 이전인 미완료 이슈를 추가하며 Epic·Initiative·Hold·Backlog는 제외합니다."
                )
                .foregroundStyle(.secondary)
                Text(
                    "자동 시도는 실패해도 재시도하지 않습니다. 필요하면 ‘지금 가져오기’를 눌러 직접 다시 확인할 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var general: some View {
        Form {
            Section("실행") {
                Toggle(
                    "로그인할 때 모래 열기",
                    isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                Text("기본값은 꺼짐이며 이 Mac 사용자 계정에만 적용됩니다.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("온보딩 다시 보기") {
                    NotificationCenter.default.post(
                        name: .moraeOpenOnboarding,
                        object: nil
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var briefing: some View {
        Form {
            Section("관심사") {
                TextField(
                    "예: AI, Frontend, 협업",
                    text: $interestsText
                )
                .onSubmit { model.updateInterests(interestsText) }
                HStack {
                    Text("쉼표로 구분하며 아티클 우선순위에 사용합니다.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Button("저장") {
                        model.updateInterests(interestsText)
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }

            Section("RSS / Atom 피드") {
                ForEach(model.feeds) { source in
                    HStack(spacing: 10) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { source.isEnabled },
                                set: { enabled in
                                    Task {
                                        await model.setFeedEnabled(
                                            source,
                                            enabled: enabled
                                        )
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .accessibilityLabel(
                            "\(source.name) 피드 활성화"
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text(source.feedURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if source.isOfficial {
                            Text("기본")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(role: .destructive) {
                                Task { await model.deleteFeed(source) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("사용자 피드 삭제")
                            .accessibilityLabel(
                                "\(source.name) 사용자 피드 삭제"
                            )
                        }
                    }
                }

                Divider()
                TextField("피드 이름 (선택)", text: $feedName)
                HStack {
                    TextField("https://example.com/feed.xml", text: $feedURL)
                    Button(model.isBusy ? "확인 중…" : "추가") {
                        Task {
                            if await model.addFeed(
                                name: feedName,
                                urlText: feedURL
                            ) {
                                feedName = ""
                                feedURL = ""
                            }
                        }
                    }
                    .disabled(model.isBusy || feedURL.isEmpty)
                }
                Text("추가할 때 한 번만 연결해 RSS/Atom 형식을 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var agents: some View {
        Form {
            Section("에이전트 연결") {
                Text(
                    container.runtimeProfile.isFreshTest
                        ? "테스트용 Codex·Claude 설정에 모래 항목을 병합합니다. 실제 사용자 설정 파일은 변경되지 않습니다."
                        : "자동 설정을 누르면 기존 파일을 백업하고 모래 항목만 병합합니다. 앱을 옮겨도 연결이 유지되도록 helper는 이 Mac의 Application Support에 설치됩니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(
                    AgentHookProvider.allCases,
                    id: \.self
                ) { provider in
                    hookConnectionRow(provider)
                }

                HStack {
                    Text("Codex와 Claude Code를 한 번에 연결할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("모두 자동 설정") {
                        model.installAllHooks()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.installingHook != nil
                            || !HookSnippetBuilder.helperIsExecutable()
                    )
                }
            }

            Section("알림") {
                LabeledContent("현재 권한") {
                    Text(notificationLabel)
                }
                if model.notificationState == .notDetermined {
                    Button("알림 허용 요청") {
                        Task { await model.requestNotifications() }
                    }
                }
                if model.notificationState == .denied {
                    Button("시스템 알림 설정 열기") {
                        model.openNotificationSettings()
                    }
                }
                Toggle(
                    "알림에 제목과 마지막 메시지 표시",
                    isOn: Binding(
                        get: {
                            model.settings.showDetailsInNotification
                        },
                        set: { model.setDetailedNotifications($0) }
                    )
                )
                Text(
                    "기본 알림은 세부 내용을 숨깁니다. 켜면 잠금 화면에도 작업 내용이 보일 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("직접 설정") {
                DisclosureGroup("자동 설정이 어려울 때") {
                    manualHookBlock(
                        title: "Codex",
                        destination: "~/.codex/config.toml",
                        snippet: HookSnippetBuilder.codex(
                            helperURL: HookSnippetBuilder.helperURL()
                        )
                    )
                    Divider()
                    manualHookBlock(
                        title: "Claude Code",
                        destination: "~/.claude/settings.json",
                        snippet: HookSnippetBuilder.claude(
                            helperURL: HookSnippetBuilder.helperURL()
                        ),
                        footer:
                            "전체 알림 호환성에는 Claude Code 2.1.198 이상이 필요합니다."
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("에이전트 기록에 저장") {
                privacyToggle(
                    "프로젝트 경로",
                    field: .projectPath,
                    value: model.settings.storeProjectPath
                )
                privacyToggle(
                    "에이전트 작업 제목",
                    field: .title,
                    value: model.settings.storeAgentTitle
                )
                privacyToggle(
                    "마지막 메시지",
                    field: .lastMessage,
                    value: model.settings.storeLastMessage
                )
                Text(
                    "모두 기본적으로 꺼져 있습니다. 설정을 끄면 이미 저장된 해당 값도 즉시 영구 삭제되며 복구할 수 없습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("데이터 처리") {
                Text(
                    "에이전트 원본 payload, 대화 전문 경로, 피드 본문은 저장하거나 로그에 남기지 않습니다."
                )
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section("모래") {
                LabeledContent("Bundle ID") {
                    Text("io.github.heejung-29cm.morae")
                        .textSelection(.enabled)
                }
                LabeledContent("이벤트 helper") {
                    Text(
                        HookSnippetBuilder.helperIsExecutable()
                            ? "번들에 포함됨"
                            : "찾을 수 없음 — 앱을 다시 빌드해 주세요"
                    )
                    .foregroundStyle(
                        HookSnippetBuilder.helperIsExecutable()
                            ? Color.secondary : Color.red
                    )
                }
                Text("개인용 로컬 서명 앱 · macOS 14 이상")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func privacyToggle(
        _ title: String,
        field: AgentPrivateField,
        value: Bool
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { value },
                set: { enabled in
                    Task {
                        await model.setPrivacy(field, enabled: enabled)
                    }
                }
            )
        )
    }

    private func hookConnectionRow(
        _ provider: AgentHookProvider
    ) -> some View {
        let status = model.hookStatuses[provider] ?? .notInstalled
        return HStack(spacing: 12) {
            Image(
                systemName: provider == .codex
                    ? "chevron.left.forwardslash.chevron.right"
                    : "terminal"
            )
            .foregroundStyle(MoraeColor.accent)
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                switch status {
                case .installed:
                    Label("연결됨", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .notInstalled:
                    Text("아직 연결되지 않음")
                        .foregroundStyle(.secondary)
                case let .needsAttention(message):
                    Text(message)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .font(.caption)
            Spacer()
            Button(
                model.installingHook == provider
                    ? "설정 중…"
                    : status == .installed
                        ? "다시 설정"
                        : "자동 설정"
            ) {
                model.installHook(provider)
            }
            .disabled(
                model.installingHook != nil
                    || !HookSnippetBuilder.helperIsExecutable()
            )
        }
    }

    private func manualHookBlock(
        title: String,
        destination: String,
        snippet: String,
        footer: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text("아래 내용을 \(destination)에 사용자가 직접 추가합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(snippet)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: title == "Codex" ? 48 : 130)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                if let footer {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        snippet,
                        forType: .string
                    )
                }
                .accessibilityLabel("\(title) Hook 설정 복사")
            }
        }
    }

    private func jiraStep<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        MoraeColor.accent,
                        in: Circle()
                    )
                Text(title)
                    .font(.headline)
            }
            content()
                .padding(.leading, 27)
        }
    }

    private var notificationLabel: String {
        switch model.notificationState {
        case .unknown: "확인 중"
        case .notDetermined: "아직 요청하지 않음"
        case .authorized: "허용됨"
        case .denied: "거부됨"
        }
    }
}
