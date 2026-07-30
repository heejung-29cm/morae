import AppKit
import MoraeCore
import SwiftUI

struct SettingsRootView: View {
    private let container: AppContainer
    @State private var model: SettingsModel
    @State private var interestsText: String
    @State private var feedName = ""
    @State private var feedURL = ""

    init(container: AppContainer) {
        self.container = container
        let model = SettingsModel(
            store: container.settingsStore,
            agentRepository: container.agentRepository,
            feedRepository: container.feedSourceRepository,
            notifier: container.agentNotifier,
            clock: container.clock,
            uuidGenerator: container.uuidGenerator
        )
        _model = State(initialValue: model)
        _interestsText = State(
            initialValue: model.settings.interests.joined(separator: ", ")
        )
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("일반", systemImage: "gearshape") }
            briefing
                .tabItem { Label("브리핑", systemImage: "sparkles") }
            agents
                .tabItem { Label("에이전트", systemImage: "terminal") }
            privacy
                .tabItem { Label("개인정보", systemImage: "hand.raised") }
            about
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .frame(width: 680, height: 520)
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

            hookSection(
                title: "Codex",
                destination: "~/.codex/config.toml",
                snippet: HookSnippetBuilder.codex(
                    helperURL: HookSnippetBuilder.helperURL()
                )
            )
            hookSection(
                title: "Claude Code",
                destination: "~/.claude/settings.json",
                snippet: HookSnippetBuilder.claude(
                    helperURL: HookSnippetBuilder.helperURL()
                ),
                footer: "전체 알림 호환성에는 Claude Code 2.1.198 이상이 필요합니다."
            )
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

    private func hookSection(
        title: String,
        destination: String,
        snippet: String,
        footer: String? = nil
    ) -> some View {
        Section("\(title) Hook") {
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

    private var notificationLabel: String {
        switch model.notificationState {
        case .unknown: "확인 중"
        case .notDetermined: "아직 요청하지 않음"
        case .authorized: "허용됨"
        case .denied: "거부됨"
        }
    }
}
