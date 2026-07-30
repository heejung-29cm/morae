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

@MainActor
struct MenuBarRootView: View {
    let container: AppContainer
    @State private var viewModel: MenuBarViewModel
    @State private var quickAddTitle = ""
    @State private var editingDraft: TodoEditDraft?
    @State private var draggedTodoID: TodoID?
    @State private var dropTargetID: TodoID?
    @FocusState private var isQuickAddFocused: Bool

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(
            initialValue: MenuBarViewModel(
                repository: container.todoRepository,
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
                        emptySection(.recentAgents, count: nil)
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
            Button {} label: {
                HStack(spacing: MoraeSpacing.compact) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .opacity(0.85)
                    Text("오늘 브리핑")
                }
            }
            .buttonStyle(
                MoraeCompactButtonStyle(
                    variant: .prominent,
                    horizontalPadding: 9
                )
            )
            .disabled(true)
            .help("수동 브리핑은 Sprint 3에서 연결됩니다.")
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

    private var articleSection: some View {
        emptySection(.article, count: "0")
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
                        }
                        Button("선택 항목을 오늘로 가져오기") {
                            Task {
                                await viewModel.carryOverSelected()
                            }
                        }
                        .disabled(viewModel.selectedCarryOverIDs.isEmpty)
                    }
                    .padding(.top, 6)
                }
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.todayTodos) { item in
                        todayTodoRow(item)
                    }
                }
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

    @ViewBuilder
    private func todayTodoRow(_ item: TodoItem) -> some View {
        if item.status == .pending {
            todoRowContent(item)
                .dropDestination(for: String.self) { identifiers, _ in
                    defer {
                        draggedTodoID = nil
                        dropTargetID = nil
                    }
                    guard let sourceStorageID = identifiers.first,
                          let source = pendingTodo(storageID: sourceStorageID),
                          TodoReorderPlan.moving(
                            source.id,
                            before: item.id,
                            in: pendingTodoIDs
                          ) != nil else {
                        return false
                    }
                    Task {
                        await viewModel.movePending(id: source.id, before: item.id)
                    }
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted, draggedTodoID != item.id {
                        dropTargetID = item.id
                    } else if dropTargetID == item.id {
                        dropTargetID = nil
                    }
                }
        } else {
            todoRowContent(item)
        }
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
            isDragging: draggedTodoID == item.id,
            showsDropIndicator: dropTargetID == item.id,
            onToggleCompletion: {
                Task {
                    await viewModel.toggleTodo(id: item.id)
                }
            },
            onDragStarted: {
                draggedTodoID = item.id
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

    private func submitQuickAdd() {
        let title = quickAddTitle
        Task {
            if await viewModel.addTodo(title: title) {
                quickAddTitle = ""
            }
        }
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
