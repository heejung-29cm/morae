import MoraeCore
import SwiftUI

enum MenuBarSection: String, CaseIterable, Sendable {
    case article
    case yesterdayCompleted
    case todayTodos
    case recentAgents

    static let orderedCases: [MenuBarSection] = [
        .article,
        .yesterdayCompleted,
        .todayTodos,
        .recentAgents,
    ]

    var title: String {
        switch self {
        case .article: "오늘의 아티클"
        case .yesterdayCompleted: "어제 완료"
        case .todayTodos: "오늘 할 일"
        case .recentAgents: "최근 에이전트 기록"
        }
    }

    var emptyMessage: String {
        switch self {
        case .article: "아직 추천한 아티클이 없습니다."
        case .yesterdayCompleted: "어제 완료한 일이 없습니다."
        case .todayTodos: "오늘 할 일이 없습니다."
        case .recentAgents: "수신한 에이전트 기록이 없습니다."
        }
    }

    var systemImage: String {
        switch self {
        case .article: "newspaper"
        case .yesterdayCompleted: "checkmark.circle"
        case .todayTodos: "list.bullet"
        case .recentAgents: "terminal"
        }
    }
}

private enum TodoDropInsertion: Equatable {
    case before(TodoID)
    case end

    var targetID: TodoID? {
        switch self {
        case let .before(id): id
        case .end: nil
        }
    }
}

private struct TodoRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TodoID: CGRect] = [:]

    static func reduce(
        value: inout [TodoID: CGRect],
        nextValue: () -> [TodoID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct AgentRunGroup: Identifiable {
    let id: String
    let title: String
    let runs: [AgentRun]
}

@MainActor
struct MenuBarRootView: View {
    let container: AppContainer
    @Environment(\.openURL) private var openURL
    @State private var viewModel: MenuBarViewModel
    @State private var quickAddTitle = ""
    @State private var editingDraft: TodoEditDraft?
    @State private var draggedTodoID: TodoID?
    @State private var dropInsertion: TodoDropInsertion?
    @State private var todoRowFrames: [TodoID: CGRect] = [:]
    @FocusState private var isQuickAddFocused: Bool

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(
            initialValue: MenuBarViewModel(
                repository: container.todoRepository,
                briefingRepository: container.briefingRepository,
                briefingGenerator: container.generateBriefing,
                clock: container.clock,
                uuidGenerator: container.uuidGenerator
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(MoraeColor.separator)
                .frame(height: 0.5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let startupError = container.startupError {
                        startupErrorView(startupError)
                    } else {
                        articleSection
                        yesterdaySection
                        todaySection
                        agentSection
                    }
                }
                .padding(.horizontal, MoraeSpacing.compact)
                .padding(.top, MoraeSpacing.regular)
                .padding(.bottom, MoraeSpacing.medium)
            }
        }
        .frame(width: 392, height: 700)
        .background(.ultraThinMaterial)
        .tint(MoraeColor.accent)
        .task {
            await viewModel.onAppear()
            container.agentActivity?.setVisible(true)
            if let notifier = container.agentNotifier {
                await container.agentActivity?
                    .refreshNotificationAuthorization(notifier: notifier)
            }
        }
        .onDisappear {
            viewModel.onDisappear()
            container.agentActivity?.setVisible(false)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: MoraeSpacing.regular) {
            VStack(alignment: .leading, spacing: 1) {
                Text("모래")
                    .font(.system(size: 15, weight: .semibold))
                Text(localizedToday)
                    .font(.caption2)
                    .foregroundStyle(MoraeColor.secondaryForeground)
            }
            Spacer()
            Button {
                Task {
                    await viewModel.requestBriefing()
                }
            } label: {
                HStack(spacing: MoraeSpacing.compact) {
                    if viewModel.briefingState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .opacity(0.85)
                    }
                    Text(
                        viewModel.briefingState.isLoading
                            ? "생성 중"
                            : "오늘 브리핑"
                    )
                }
            }
            .buttonStyle(
                MoraeCompactButtonStyle(
                    variant: .prominent,
                    horizontalPadding: 9
                )
            )
            .disabled(
                container.generateBriefing == nil
                    || viewModel.briefingState.isLoading
            )
            .help("클릭할 때만 피드에서 오늘의 아티클을 확인합니다.")
            SettingsLink {
                Label("설정", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(
                MoraeIconButtonStyle(
                    size: MoraeControlMetrics.headerIconButtonSize
                )
            )
            .help("설정 열기")
            .accessibilityLabel("설정 열기")
        }
        .padding(.leading, 14)
        .padding(.trailing, MoraeSpacing.medium)
        .padding(.vertical, MoraeSpacing.medium)
    }

    @ViewBuilder
    private var articleSection: some View {
        sectionContainer(
            .article,
            count: viewModel.briefingState.latestSuccess == nil ? "0" : "1"
        ) {
            switch viewModel.briefingState {
            case let .idle(previous):
                if let previous {
                    briefingSuccessContent(previous)
                } else {
                    emptyMessage(for: .article)
                }
            case let .loading(previous):
                if let previous {
                    briefingSuccessContent(previous)
                        .opacity(0.62)
                }
                HStack(spacing: MoraeSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("새로운 아티클을 찾고 있습니다.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MoraeColor.secondaryForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MoraeSpacing.regular)
                .background(
                    MoraeColor.subtleFill,
                    in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("오늘 브리핑 생성 중")
            case let .success(briefing):
                briefingSuccessContent(briefing)
            case let .failure(failure, previous):
                if let previous {
                    briefingSuccessContent(previous)
                        .opacity(0.72)
                }
                MenuBarStateView(
                    kind: .error,
                    title: failure.code.title,
                    message: failure.code.message,
                    recovery: failure.code.recovery
                )
            }
        }
    }

    @ViewBuilder
    private func briefingSuccessContent(
        _ briefing: GeneratedBriefing
    ) -> some View {
        if let article = briefing.stored.article {
            articleCard(article)
        }
        if briefing.failedFeedCount > 0 {
            MenuBarStateView(
                kind: .validation,
                title: "일부 피드를 확인하지 못했습니다",
                message: "성공한 피드의 아티클로 추천을 만들었습니다.",
                recovery: "실패한 피드는 이번 실행에서 재시도하지 않았습니다."
            )
        }
    }

    private func articleCard(_ article: Article) -> some View {
        Button {
            openURL(article.canonicalURL)
        } label: {
            VStack(alignment: .leading, spacing: MoraeSpacing.small) {
                Text(article.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoraeColor.foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: MoraeSpacing.compact) {
                    Text(article.sourceName)
                    if let publishedAt = article.publishedAt {
                        Text("·")
                        Text(
                            publishedAt.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                    }
                    Spacer(minLength: MoraeSpacing.small)
                    Label("원문 열기", systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                }
                .font(.system(size: 11))
                .foregroundStyle(MoraeColor.secondaryForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MoraeSpacing.medium)
            .background(
                MoraeColor.selectedFill,
                in: RoundedRectangle(cornerRadius: MoraeRadius.large)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MoraeRadius.large)
                    .stroke(MoraeColor.accent.opacity(0.20), lineWidth: 0.5)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: MoraeRadius.large)
            )
        }
        .buttonStyle(.plain)
        .help("기본 브라우저에서 원문 열기")
        .accessibilityLabel(
            "\(article.title), \(article.sourceName), 원문 열기"
        )
    }

    private var yesterdaySection: some View {
        sectionContainer(
            .yesterdayCompleted,
            count: String(viewModel.yesterdayCompleted.count)
        ) {
            if viewModel.yesterdayCompleted.isEmpty {
                emptyMessage(for: .yesterdayCompleted)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.yesterdayCompleted) { item in
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(MoraeColor.accent)
                            Text(item.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(MoraeColor.mutedForeground)
                                .strikethrough()
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, MoraeSpacing.regular)
                        .padding(.vertical, MoraeSpacing.compact)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("완료, \(item.title)")
                    }
                }
            }
            if !viewModel.yesterdayPending.isEmpty {
                DisclosureGroup("어제 미완료 가져오기") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.yesterdayPending) { item in
                            Toggle(
                                item.title,
                                isOn: Binding(
                                    get: {
                                        viewModel.selectedCarryOverIDs.contains(item.id)
                                    },
                                    set: { _ in
                                        viewModel.toggleCarryOverSelection(id: item.id)
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("선택 항목을 오늘로 가져오기") {
                            Task {
                                await viewModel.carryOverSelected()
                            }
                        }
                        .buttonStyle(
                            MoraeCompactButtonStyle(variant: .chip)
                        )
                        .disabled(viewModel.selectedCarryOverIDs.isEmpty)
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var todaySection: some View {
        sectionContainer(.todayTodos, count: todayCountLabel) {
            HStack(spacing: MoraeSpacing.compact) {
                TextField("빠른 할 일 추가", text: $quickAddTitle)
                    .focused($isQuickAddFocused)
                    .moraeInput(isFocused: isQuickAddFocused)
                    .onSubmit {
                        submitQuickAdd()
                    }
                    .onExitCommand {
                        quickAddTitle = ""
                        isQuickAddFocused = false
                        viewModel.clearValidationMessage()
                    }
                    .accessibilityLabel("빠른 할 일 추가")
                    .onChange(of: quickAddTitle) {
                        viewModel.clearValidationMessage()
                    }
                Button {
                    submitQuickAdd()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(
                    MoraeIconButtonStyle(
                        size: MoraeControlMetrics.inputHeight
                    )
                )
                .accessibilityLabel("할 일 저장")
            }
            if viewModel.todayTodos.isEmpty {
                emptyMessage(for: .todayTodos)
            } else {
                todayTodoList
            }
            if let draft = editingDraft {
                TodoEditorView(
                    initialDraft: draft,
                    onSave: { updatedDraft in
                        if await viewModel.updateTodo(updatedDraft) {
                            editingDraft = nil
                        }
                    },
                    onCancel: {
                        editingDraft = nil
                    }
                )
                .id(draft.id)
            }
            if let deletionCandidate = viewModel.deletionCandidate {
                InlineDeleteConfirmationView(
                    item: deletionCandidate,
                    onCancel: {
                        viewModel.cancelDelete()
                    },
                    onDelete: {
                        Task {
                            await viewModel.confirmDelete()
                        }
                    }
                )
            }
            if let validationMessage = viewModel.validationMessage {
                MenuBarStateView(
                    kind: .validation,
                    title: "입력을 확인해 주세요",
                    message: validationMessage
                )
            }
            if let deleted = viewModel.recentlyDeleted {
                UndoDeleteBanner(
                    title: deleted.title,
                    onUndo: {
                        Task {
                            await viewModel.undoDelete()
                        }
                    }
                )
            }
            if let errorMessage = viewModel.errorMessage {
                MenuBarStateView(
                    kind: .error,
                    title: "작업을 완료하지 못했습니다",
                    message: errorMessage
                )
            }
        }
    }

    private var todayTodoList: some View {
        let pendingItems = viewModel.todayTodos.filter {
            $0.status == .pending
        }
        let completedItems = viewModel.todayTodos.filter {
            $0.status == .completed
        }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pendingItems.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 0) {
                    if index > 0 {
                        staticTodoDivider
                    }
                    todoRowContent(item)
                }
                .overlay(alignment: .top) {
                    if dropInsertion == .before(item.id) {
                        dropInsertionLine
                    }
                }
                .overlay(alignment: .bottom) {
                    if index == pendingItems.count - 1,
                       dropInsertion == .end {
                        dropInsertionLine
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TodoRowFramePreferenceKey.self,
                            value: [
                                item.id: proxy.frame(
                                    in: .named(TodoDragCoordinateSpace.name)
                                ),
                            ]
                        )
                    }
                }
                .zIndex(draggedTodoID == item.id ? 1 : 0)
            }
            ForEach(completedItems) { item in
                if item.id != completedItems.first?.id || !pendingItems.isEmpty {
                    staticTodoDivider
                }
                todoRowContent(item)
            }
        }
        .coordinateSpace(name: TodoDragCoordinateSpace.name)
        .onPreferenceChange(TodoRowFramePreferenceKey.self) {
            todoRowFrames = $0
        }
    }

    private var staticTodoDivider: some View {
        Rectangle()
            .fill(MoraeColor.separator)
            .frame(height: 0.5)
            .padding(.leading, 42)
            .padding(.trailing, MoraeSpacing.small)
            .accessibilityHidden(true)
    }

    private var dropInsertionLine: some View {
        Capsule()
            .fill(MoraeColor.accent.opacity(0.76))
            .frame(height: 2)
            .padding(.horizontal, MoraeSpacing.xSmall)
            .shadow(
                color: MoraeColor.accent.opacity(0.24),
                radius: 2
            )
            .accessibilityHidden(true)
    }

    private func acceptTodoDrop(
        _ sourceID: TodoID,
        at insertion: TodoDropInsertion
    ) -> Bool {
        defer {
            draggedTodoID = nil
            dropInsertion = nil
        }
        let targetID = insertion.targetID
        guard TodoReorderPlan.moving(
                sourceID,
                before: targetID,
                in: pendingTodoIDs
              ) != nil else {
            return false
        }
        Task {
            await viewModel.movePending(id: sourceID, before: targetID)
        }
        return true
    }

    private func todoRowContent(_ item: TodoItem) -> some View {
        let pendingItems = viewModel.todayTodos.filter { $0.status == .pending }
        return TodoRowView(
            item: item,
            canMoveUp: pendingItems.first?.id != item.id,
            canMoveDown: pendingItems.last?.id != item.id,
            dragIdentifier: item.status == .pending
                ? item.id.storageValue
                : nil,
            onDragStarted: { storageID in
                draggedTodoID = pendingTodo(storageID: storageID)?.id
                dropInsertion = nil
            },
            onDragChanged: { location in
                updateTodoDrag(item.id, location: location)
            },
            onDragEnded: { location in
                finishTodoDrag(item.id, location: location)
            },
            onToggleCompletion: {
                Task {
                    await viewModel.toggleTodo(id: item.id)
                }
            },
            onMoveUp: {
                Task {
                    await viewModel.movePending(id: item.id, direction: .up)
                }
            },
            onMoveDown: {
                Task {
                    await viewModel.movePending(id: item.id, direction: .down)
                }
            },
            onEdit: {
                viewModel.cancelDelete()
                editingDraft = TodoEditDraft(item: item)
            },
            onDelete: {
                editingDraft = nil
                viewModel.requestDelete(id: item.id)
            }
        )
    }

    private var pendingTodoIDs: [TodoID] {
        viewModel.todayTodos
            .filter { $0.status == .pending }
            .map(\.id)
    }

    private func pendingTodo(storageID: String) -> TodoItem? {
        viewModel.todayTodos.first {
            $0.status == .pending && $0.id.storageValue == storageID
        }
    }

    private func updateTodoDrag(_ sourceID: TodoID, location: CGPoint) {
        guard draggedTodoID == sourceID else { return }
        let orderedFrames = pendingTodoIDs.compactMap { id in
            todoRowFrames[id].map { (id, $0) }
        }
        let candidate = orderedFrames.first { _, frame in
            location.y < frame.midY
        }
        let insertion = candidate.map {
            TodoDropInsertion.before($0.0)
        } ?? .end
        dropInsertion = TodoReorderPlan.moving(
            sourceID,
            before: insertion.targetID,
            in: pendingTodoIDs
        ) == nil ? nil : insertion
    }

    private func finishTodoDrag(_ sourceID: TodoID, location: CGPoint) {
        updateTodoDrag(sourceID, location: location)
        guard let dropInsertion else {
            draggedTodoID = nil
            return
        }
        _ = acceptTodoDrop(sourceID, at: dropInsertion)
    }

    private func submitQuickAdd() {
        let title = quickAddTitle
        Task {
            if await viewModel.addTodo(title: title) {
                quickAddTitle = ""
                isQuickAddFocused = false
            }
        }
    }

    private var agentSection: some View {
        let runs = container.agentActivity?.runs ?? []
        return sectionContainer(.recentAgents, count: String(runs.count)) {
            if let errorMessage = container.agentActivity?.errorMessage {
                MenuBarStateView(
                    kind: .error,
                    title: "기록을 표시하지 못했습니다",
                    message: errorMessage
                )
            } else if runs.isEmpty {
                emptyMessage(for: .recentAgents)
            } else {
                VStack(alignment: .leading, spacing: MoraeSpacing.regular) {
                    ForEach(agentRunGroups(for: runs)) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(MoraeColor.mutedForeground)
                                .padding(.horizontal, MoraeSpacing.regular)
                                .padding(.bottom, MoraeSpacing.xSmall)
                            ForEach(Array(group.runs.enumerated()), id: \.element.id) {
                                index,
                                run in
                                if index > 0 {
                                    Rectangle()
                                        .fill(MoraeColor.separator)
                                        .frame(height: 0.5)
                                        .padding(.leading, 38)
                                }
                                agentRow(run)
                            }
                        }
                    }
                }
            }
            if let notifier = container.agentNotifier,
               let activity = container.agentActivity {
                switch activity.notificationAuthorization {
                case .unknown, .notDetermined:
                    Button {
                        Task {
                            _ = await activity
                                .requestNotificationAuthorization(
                                    notifier: notifier
                                )
                        }
                    } label: {
                        Label("에이전트 알림 허용", systemImage: "bell")
                    }
                    .buttonStyle(MoraeCompactButtonStyle(variant: .chip))
                    .help("에이전트 종료 알림을 위한 macOS 권한을 요청합니다.")
                case .authorized:
                    Label("에이전트 알림 켜짐", systemImage: "bell.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MoraeColor.mutedForeground)
                case .denied:
                    Label(
                        "알림 꺼짐 · 메뉴 막대 아이콘으로 표시합니다.",
                        systemImage: "bell.slash"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(MoraeColor.mutedForeground)
                }
            }
        }
    }

    private func agentRow(_ run: AgentRun) -> some View {
        HStack(alignment: .center, spacing: MoraeSpacing.small) {
            Image(systemName: agentStatusIcon(run.status))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(agentStatusColor(run.status))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.title ?? "\(agentSourceName(run.source)) 작업")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(MoraeColor.foreground)
                    .lineLimit(2)
                Text(
                    "\(agentStatusText(run.status)) · "
                        + agentRelativeTime(run.updatedAt)
                )
                .font(.system(size: 10.5))
                .foregroundStyle(MoraeColor.secondaryForeground)
            }
            Spacer(minLength: MoraeSpacing.xSmall)
            if run.isUnread {
                Circle()
                    .fill(MoraeColor.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("읽지 않음")
            }
        }
        .padding(.horizontal, MoraeSpacing.regular)
        .padding(.vertical, MoraeSpacing.compact)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(agentSourceName(run.source)), "
                + "\(agentStatusText(run.status)), "
                + agentRelativeTime(run.updatedAt)
        )
    }

    private func agentRunGroups(for runs: [AgentRun]) -> [AgentRunGroup] {
        var groupOrder: [String] = []
        var grouped: [String: [AgentRun]] = [:]
        for run in runs {
            let title = agentGroupTitle(run)
            if grouped[title] == nil {
                groupOrder.append(title)
            }
            grouped[title, default: []].append(run)
        }
        return groupOrder.map {
            AgentRunGroup(id: $0, title: $0, runs: grouped[$0] ?? [])
        }
    }

    private func agentGroupTitle(_ run: AgentRun) -> String {
        guard let path = run.projectPath, !path.isEmpty else {
            return agentSourceName(run.source)
        }
        let components = URL(fileURLWithPath: path)
            .pathComponents
            .filter { $0 != "/" }
        return components.suffix(2).joined(separator: "/")
    }

    private func agentSourceName(_ source: AgentSource) -> String {
        source == .codex ? "Codex" : "Claude"
    }

    private func agentStatusText(_ status: AgentStatus) -> String {
        switch status {
        case .running: "진행 중"
        case .attentionRequired: "확인 필요"
        case .responded: "응답 완료"
        case .completed: "작업 완료"
        case .failed: "실패"
        case .cancelled: "취소됨"
        }
    }

    private func agentStatusIcon(_ status: AgentStatus) -> String {
        switch status {
        case .running: "ellipsis.circle"
        case .attentionRequired: "exclamationmark.bubble"
        case .responded: "text.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle"
        }
    }

    private func agentStatusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .running, .cancelled: MoraeColor.secondaryForeground
        case .attentionRequired: .orange
        case .responded: MoraeColor.accent
        case .completed: .green
        case .failed: MoraeColor.error
        }
    }

    private func agentRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(
            for: date,
            relativeTo: container.clock.now()
        )
    }

    private func emptySection(
        _ section: MenuBarSection,
        count: String? = "0"
    ) -> some View {
        sectionContainer(section, count: count) {
            emptyMessage(for: section)
        }
    }

    private func sectionContainer<Content: View>(
        _ section: MenuBarSection,
        count: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MoraeSpacing.compact) {
            HStack(alignment: .firstTextBaseline, spacing: MoraeSpacing.compact) {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MoraeColor.secondaryForeground)
                Spacer(minLength: MoraeSpacing.small)
                if let count {
                    Text(count)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(MoraeColor.mutedForeground)
                        .accessibilityLabel("\(count)개 항목")
                }
            }
            .padding(.horizontal, MoraeSpacing.xSmall)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MoraeSpacing.small)
        .padding(.top, MoraeSpacing.compact)
        .padding(.bottom, MoraeSpacing.regular)
    }

    private var todayCountLabel: String {
        let pendingCount = viewModel.todayTodos
            .filter { $0.status == .pending }
            .count
        return "\(pendingCount) / \(viewModel.todayTodos.count)"
    }

    private var localizedToday: String {
        let components = viewModel.today.rawValue
            .split(separator: "-")
            .compactMap { Int($0) }
        guard components.count == 3 else {
            return viewModel.today.rawValue
        }
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        guard let date = calendar.date(
            from: DateComponents(
                year: components[0],
                month: components[1],
                day: components[2],
                hour: 12
            )
        ) else {
            return viewModel.today.rawValue
        }
        return date.formatted(date: .complete, time: .omitted)
    }

    private func emptyMessage(for section: MenuBarSection) -> some View {
        MenuBarStateView(
            kind: .empty,
            message: section.emptyMessage,
            systemImage: section.systemImage
        )
        .accessibilityLabel(
            "\(section.title), \(section.emptyMessage)"
        )
    }

    private func startupErrorView(_ error: AppError) -> some View {
        MenuBarStateView(
            kind: .error,
            title: "로컬 데이터 열기 실패",
            message: error.userMessage,
            recovery: error.recovery
        )
    }
}
