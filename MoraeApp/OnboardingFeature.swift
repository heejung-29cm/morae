import AppKit
import MoraeCore
import SwiftUI

extension Notification.Name {
    static let moraeOpenOnboarding = Notification.Name(
        "io.github.heejung-29cm.morae.open-onboarding"
    )
}

protocol OnboardingStateStoring: Sendable {
    func isCompleted() -> Bool
    func markCompleted()
}

final class UserDefaultsOnboardingStateStore:
    OnboardingStateStoring,
    @unchecked Sendable
{
    static let currentVersion = 1
    private static let completedVersionKey = "onboarding.completedVersion"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isCompleted() -> Bool {
        defaults.integer(forKey: Self.completedVersionKey)
            >= Self.currentVersion
    }

    func markCompleted() {
        defaults.set(
            Self.currentVersion,
            forKey: Self.completedVersionKey
        )
    }
}

@MainActor
final class MoraeOnboardingWindowController: NSWindowController {
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "모래 시작하기"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
        ]
        window.hidesOnDeactivate = false
        window.center()
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: OnboardingRootView(
                container: container,
                finish: { [weak self] in self?.finish() }
            )
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showFromNotification),
            name: .moraeOpenOnboarding,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidFinishLaunching),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func showIfNeeded() {
        guard !container.onboardingStore.isCompleted() else { return }
        show()
    }

    @objc private func showFromNotification() {
        show()
    }

    @objc private func applicationDidFinishLaunching() {
        showIfNeeded()
    }

    private func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func finish() {
        container.onboardingStore.markCompleted()
        close()
    }
}

@MainActor
private struct OnboardingRootView: View {
    private static let interests = ["AI", "Frontend", "협업", "인프라", "데이터"]

    let finish: () -> Void
    @State private var model: SettingsModel
    @State private var step = 0
    @State private var selectedInterests: Set<String>
    @State private var customInterests = ""
    @State private var jiraSiteURL = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jiraStartDateFieldID = ""

    init(container: AppContainer, finish: @escaping () -> Void) {
        self.finish = finish
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
        let existing = model.settings.interests
        _selectedInterests = State(
            initialValue: Set(existing.filter(Self.interests.contains))
        )
        _customInterests = State(
            initialValue: existing.filter { !Self.interests.contains($0) }
                .joined(separator: ", ")
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("모래 시작하기")
                    .font(.headline)
                Spacer()
                Text("\(step + 1) / 5")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            ProgressView(value: Double(step + 1), total: 5)
                .tint(MoraeColor.accent)
                .padding(.horizontal, 28)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: interestsStep
                case 2: agentsStep
                case 3: jiraStep
                default: completionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()
            HStack {
                if step > 0 && step < 4 {
                    Button("이전") { step -= 1 }
                }
                Spacer()
                if step < 4 {
                    Button(step == 3 ? "건너뛰고 계속" : "계속") {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("모래 시작") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 660, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(MoraeColor.accent)
        .task { await model.refresh() }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "hourglass.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(MoraeColor.accent)
            Text("오늘의 흐름을 가볍게 모아보세요")
                .font(.system(size: 25, weight: .bold))
            Text("할 일, 읽을거리, Codex·Claude 종료 알림을\n메뉴 막대 한곳에서 확인할 수 있습니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("관심 주제를 골라주세요", detail: "아티클 추천 순서에만 사용하며 이 Mac에 저장합니다.")
            HStack(spacing: 9) {
                ForEach(Self.interests, id: \.self) { interest in
                    Button {
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    } label: {
                        Label(
                            interest,
                            systemImage: selectedInterests.contains(interest)
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(
                        selectedInterests.contains(interest)
                            ? MoraeColor.accent
                            : .secondary
                    )
                }
            }
            TextField("추가 관심사 (쉼표로 구분)", text: $customInterests)
                .textFieldStyle(.roundedBorder)
            Spacer()
        }
    }

    private var agentsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("에이전트 알림을 연결하세요", detail: "기존 설정은 백업하고 모래 항목만 안전하게 병합합니다.")
            ForEach(AgentHookProvider.allCases, id: \.self) { provider in
                HStack {
                    Label(provider.displayName, systemImage: "terminal")
                    Spacer()
                    Text(hookStatus(provider))
                        .foregroundStyle(
                            model.hookStatuses[provider] == .installed
                                ? .green
                                : .secondary
                        )
                }
                .padding(12)
                .background(MoraeColor.subtleFill, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("Codex·Claude 자동 설정") {
                    model.installAllHooks()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button(notificationButtonTitle) {
                    Task { await model.requestNotifications() }
                }
                .disabled(model.notificationState == .authorized)
            }
            Text("에이전트를 사용하지 않는다면 설정하지 않고 계속해도 됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var jiraStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Jira 연결은 선택 사항입니다", detail: "연결하면 오늘 시작했거나 진행 중인 내 이슈를 할 일로 가져옵니다.")
            if model.jiraSnapshot.connection != nil {
                Label("Jira 연결됨", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                TextField("Jira 사이트 주소", text: $jiraSiteURL)
                TextField("계정 이메일", text: $jiraEmail)
                SecureField("API token 전체 값", text: $jiraToken)
                if !model.jiraStartDateFields.isEmpty {
                    Picker("시작 날짜 필드", selection: $jiraStartDateFieldID) {
                        Text("선택해 주세요").tag("")
                        ForEach(model.jiraStartDateFields) { field in
                            Text("\(field.displayName) · \(field.id)").tag(field.id)
                        }
                    }
                }
                HStack {
                    Link(
                        "API token 만들기",
                        destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
                    )
                    Spacer()
                    Button(model.isJiraBusy ? "확인 중…" : "연결 확인") {
                        Task { await connectJira() }
                    }
                    .disabled(
                        model.isJiraBusy || jiraSiteURL.isEmpty
                            || jiraEmail.isEmpty || jiraToken.isEmpty
                    )
                }
            }
            if let message = model.jiraStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(model.jiraStatusIsError ? .red : .secondary)
            }
            Spacer()
        }
    }

    private var completionStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(MoraeColor.accent)
            Text("준비가 끝났습니다")
                .font(.system(size: 25, weight: .bold))
            Text("메뉴 막대의 햄스터를 눌러 할 일을 추가하고\n오늘의 아티클을 추천받아 보세요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func stepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private func advance() {
        if step == 1 {
            let custom = customInterests.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let values = selectedInterests.sorted() + custom
            model.updateInterests(values.joined(separator: ", "))
        }
        step = min(step + 1, 4)
    }

    private func connectJira() async {
        let connected = await model.connectJira(
            siteURL: jiraSiteURL,
            email: jiraEmail,
            token: jiraToken,
            startDateFieldID: jiraStartDateFieldID.isEmpty
                ? nil
                : jiraStartDateFieldID
        )
        if connected { jiraToken = "" }
    }

    private func hookStatus(_ provider: AgentHookProvider) -> String {
        switch model.hookStatuses[provider] ?? .notInstalled {
        case .notInstalled: "설정 전"
        case .installed: "연결됨"
        case .needsAttention: "확인 필요"
        }
    }

    private var notificationButtonTitle: String {
        switch model.notificationState {
        case .authorized: "알림 허용됨"
        case .denied: "알림이 차단됨"
        case .notDetermined, .unknown: "알림 허용"
        }
    }
}
