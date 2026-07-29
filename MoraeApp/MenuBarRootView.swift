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
}

@MainActor
struct MenuBarRootView: View {
    let container: AppContainer
    @State private var viewModel: MenuBarViewModel
    @State private var quickAddTitle = ""
    @State private var editingDraft: TodoEditDraft?

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
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let startupError = container.startupError {
                        startupErrorView(startupError)
                    } else {
                        articleSection
                        yesterdaySection
                        todaySection
                        emptySection(.recentAgents)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 600)
        .task {
            await viewModel.onAppear()
        }
        .sheet(item: $editingDraft) { draft in
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
        }
        .alert(
            "할 일을 삭제할까요?",
            isPresented: Binding(
                get: { viewModel.deletionCandidate != nil },
                set: { presented in
                    if !presented {
                        viewModel.cancelDelete()
                    }
                }
            )
        ) {
            Button("삭제", role: .destructive) {
                Task {
                    await viewModel.confirmDelete()
                }
            }
            Button("취소", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text(viewModel.deletionCandidate?.title ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("모래")
                    .font(.headline)
                Text(viewModel.today.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("오늘 브리핑 만들기", systemImage: "sparkles") {}
                .disabled(true)
                .help("수동 브리핑은 Sprint 3에서 연결됩니다.")
            SettingsLink {
                Label("설정", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .help("설정 열기")
            .accessibilityLabel("설정 열기")
        }
        .padding(16)
    }

    private var articleSection: some View {
        emptySection(.article)
    }

    private var yesterdaySection: some View {
        sectionContainer(.yesterdayCompleted) {
            if viewModel.yesterdayCompleted.isEmpty {
                emptyMessage(for: .yesterdayCompleted)
            } else {
                ForEach(viewModel.yesterdayCompleted) { item in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(item.title)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("완료, \(item.title)")
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
        sectionContainer(.todayTodos) {
            HStack {
                TextField("빠른 할 일 추가", text: $quickAddTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitQuickAdd()
                    }
                    .onExitCommand {
                        quickAddTitle = ""
                        viewModel.clearValidationMessage()
                    }
                    .accessibilityLabel("빠른 할 일 추가")
                Button {
                    submitQuickAdd()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("할 일 저장")
            }
            if viewModel.todayTodos.isEmpty {
                emptyMessage(for: .todayTodos)
            } else {
                ForEach(viewModel.todayTodos) { item in
                    todayTodoRow(item)
                }
            }
            if let validationMessage = viewModel.validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("입력 오류, \(validationMessage)")
            }
            if let deleted = viewModel.recentlyDeleted {
                HStack {
                    Text("‘\(deleted.title)’을 삭제했습니다.")
                        .font(.caption)
                    Spacer()
                    Button("실행 취소") {
                        Task {
                            await viewModel.undoDelete()
                        }
                    }
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("오류, \(errorMessage)")
            }
        }
    }

    @ViewBuilder
    private func todayTodoRow(_ item: TodoItem) -> some View {
        if item.status == .pending {
            todoRowContent(item)
                .draggable(item.id.storageValue)
                .dropDestination(for: String.self) { identifiers, _ in
                    guard let sourceStorageID = identifiers.first,
                          let source = viewModel.todayTodos.first(
                            where: { $0.id.storageValue == sourceStorageID }
                          ),
                          source.status == .pending else {
                        return false
                    }
                    Task {
                        await viewModel.movePending(id: source.id, before: item.id)
                    }
                    return true
                }
        } else {
            todoRowContent(item)
        }
    }

    private func todoRowContent(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.toggleTodo(id: item.id)
                }
            } label: {
                Image(
                    systemName: item.status == .completed
                        ? "checkmark.circle.fill"
                        : "circle"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                item.status == .completed
                    ? "\(item.title) 미완료로 변경"
                    : "\(item.title) 완료"
            )

            if item.priority == .important {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("중요")
            }
            Text(item.title)
                .strikethrough(item.status == .completed)
                .foregroundStyle(
                    item.status == .completed ? .secondary : .primary
                )
                .lineLimit(2)
            Spacer()
            if let minutes = item.estimatedMinutes {
                Text("\(minutes)분")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if item.status == .pending {
                Button {
                    Task {
                        await viewModel.movePending(id: item.id, direction: .up)
                    }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.todayTodos
                        .filter { $0.status == .pending }
                        .first?.id == item.id
                )
                .accessibilityLabel("\(item.title) 위로 이동")
                Button {
                    Task {
                        await viewModel.movePending(id: item.id, direction: .down)
                    }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.todayTodos
                        .filter { $0.status == .pending }
                        .last?.id == item.id
                )
                .accessibilityLabel("\(item.title) 아래로 이동")
            }
            Button {
                editingDraft = TodoEditDraft(item: item)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title) 편집")
            Button {
                viewModel.requestDelete(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title) 삭제")
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

    private func emptySection(_ section: MenuBarSection) -> some View {
        sectionContainer(section) {
            emptyMessage(for: section)
        }
    }

    private func sectionContainer<Content: View>(
        _ section: MenuBarSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyMessage(for section: MenuBarSection) -> some View {
        Text(section.emptyMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("\(section.title), \(section.emptyMessage)")
    }

    private func startupErrorView(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("로컬 데이터 열기 실패", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
            if let recovery = error.recovery {
                Text(recovery)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TodoEditorView: View {
    @State private var draft: TodoEditDraft
    let onSave: (TodoEditDraft) async -> Void
    let onCancel: () -> Void

    init(
        initialDraft: TodoEditDraft,
        onSave: @escaping (TodoEditDraft) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            TextField("제목", text: $draft.title)
            Toggle("중요", isOn: Binding(
                get: { draft.priority == .important },
                set: { draft.priority = $0 ? .important : .normal }
            ))
            TextField("예상 시간(분)", text: $draft.estimatedMinutes)
            TextField("관련 URL", text: $draft.relatedURL)
            TextField("프로젝트 경로", text: $draft.projectPath)
            HStack {
                Spacer()
                Button("취소", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    Task {
                        await onSave(draft)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
