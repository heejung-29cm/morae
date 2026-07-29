import Foundation
import MoraeCore
import Observation

@MainActor
@Observable
final class MenuBarViewModel {
    private(set) var todayTodos: [TodoItem] = []
    private(set) var yesterdayCompleted: [TodoItem] = []
    private(set) var errorMessage: String?
    private(set) var validationMessage: String?
    private(set) var deletionCandidate: TodoItem?
    private(set) var recentlyDeleted: TodoItem?

    let today: LocalDay

    private let repository: (any TodoRepository)?
    private let clock: any Clock
    private let uuidGenerator: any UUIDGenerating
    private let calendar: Calendar
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var undoExpirationTask: Task<Void, Never>?

    init(
        repository: (any TodoRepository)?,
        clock: any Clock,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.calendar = calendar
        today = clock.localDay(for: clock.now(), calendar: calendar)
    }

    func onAppear() async {
        guard observationTask == nil, let repository else {
            return
        }

        do {
            let summary = try await BuildLocalTaskSummary(repository: repository)
                .execute(today: today, calendar: calendar)
            yesterdayCompleted = summary.yesterdayCompleted
        } catch {
            errorMessage = "할 일 요약을 불러오지 못했습니다."
        }

        observationTask = Task { [weak self, repository, today] in
            do {
                for try await items in repository.observation(day: today) {
                    guard !Task.isCancelled else { return }
                    self?.todayTodos = items
                    self?.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = "할 일 목록을 불러오지 못했습니다."
            }
        }
    }

    func toggleTodo(id: TodoID) async {
        guard let repository,
              let item = todayTodos.first(where: { $0.id == id }) else {
            return
        }
        do {
            _ = try await repository.setCompletion(
                id: id,
                isCompleted: item.status == .pending,
                at: clock.now()
            )
        } catch {
            errorMessage = "완료 상태를 변경하지 못했습니다."
        }
    }

    func addTodo(title: String) async -> Bool {
        guard let repository else { return false }
        do {
            let instant = clock.now()
            let item = try TodoItem(
                id: TodoID(rawValue: uuidGenerator.next()),
                title: title,
                day: today,
                status: .pending,
                priority: .normal,
                sortOrder: (todayTodos.map(\.sortOrder).max() ?? -1) + 1,
                createdAt: instant,
                updatedAt: instant
            )
            try await repository.insert(item)
            todayTodos.append(item)
            validationMessage = nil
            return true
        } catch let error as TodoValidationError {
            validationMessage = validationText(for: error)
            return false
        } catch {
            errorMessage = "할 일을 저장하지 못했습니다."
            return false
        }
    }

    func updateTodo(_ draft: TodoEditDraft) async -> Bool {
        guard let repository,
              let original = todayTodos.first(where: { $0.id == draft.id }) else {
            return false
        }
        do {
            let estimatedMinutes: Int?
            if draft.estimatedMinutes.trimmingCharacters(in: .whitespaces).isEmpty {
                estimatedMinutes = nil
            } else if let parsed = Int(draft.estimatedMinutes) {
                estimatedMinutes = parsed
            } else {
                throw TodoValidationError.invalidEstimatedMinutes
            }

            let relatedURL: URL?
            if draft.relatedURL.trimmingCharacters(in: .whitespaces).isEmpty {
                relatedURL = nil
            } else if let parsed = URL(string: draft.relatedURL) {
                relatedURL = parsed
            } else {
                throw TodoValidationError.invalidRelatedURL
            }

            let updated = try TodoItem(
                id: original.id,
                title: draft.title,
                day: original.day,
                status: original.status,
                priority: draft.priority,
                sortOrder: original.sortOrder,
                estimatedMinutes: estimatedMinutes,
                relatedURL: relatedURL,
                projectPath: draft.projectPath.nilIfBlank,
                completedAt: original.completedAt,
                createdAt: original.createdAt,
                updatedAt: clock.now()
            )
            try await repository.update(updated)
            if let index = todayTodos.firstIndex(where: { $0.id == updated.id }) {
                todayTodos[index] = updated
            }
            validationMessage = nil
            return true
        } catch let error as TodoValidationError {
            validationMessage = validationText(for: error)
            return false
        } catch {
            errorMessage = "할 일을 수정하지 못했습니다."
            return false
        }
    }

    func requestDelete(id: TodoID) {
        deletionCandidate = todayTodos.first(where: { $0.id == id })
    }

    func cancelDelete() {
        deletionCandidate = nil
    }

    func confirmDelete() async {
        guard let repository, let item = deletionCandidate else { return }
        do {
            try await repository.delete(id: item.id)
            todayTodos.removeAll(where: { $0.id == item.id })
            deletionCandidate = nil
            recentlyDeleted = item
            scheduleUndoExpiration()
        } catch {
            errorMessage = "할 일을 삭제하지 못했습니다."
        }
    }

    func undoDelete() async {
        guard let repository, let item = recentlyDeleted else { return }
        do {
            try await repository.insert(item)
            todayTodos.append(item)
            todayTodos.sort { $0.sortOrder < $1.sortOrder }
            recentlyDeleted = nil
            undoExpirationTask?.cancel()
        } catch {
            errorMessage = "삭제를 되돌리지 못했습니다."
        }
    }

    func clearValidationMessage() {
        validationMessage = nil
    }

    private func scheduleUndoExpiration() {
        undoExpirationTask?.cancel()
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.recentlyDeleted = nil
        }
    }

    private func validationText(for error: TodoValidationError) -> String {
        switch error {
        case .emptyTitle: "제목을 입력해 주세요."
        case .titleTooLong: "제목은 200자 이하여야 합니다."
        case .invalidEstimatedMinutes: "예상 시간은 1~1440분이어야 합니다."
        case .invalidRelatedURL: "URL은 http, https 또는 file 형식이어야 합니다."
        case .invalidCompletionState: "완료 상태가 올바르지 않습니다."
        }
    }

    deinit {
        observationTask?.cancel()
        undoExpirationTask?.cancel()
    }
}

struct TodoEditDraft: Identifiable, Equatable, Sendable {
    let id: TodoID
    var title: String
    var priority: TodoPriority
    var estimatedMinutes: String
    var relatedURL: String
    var projectPath: String

    init(item: TodoItem) {
        id = item.id
        title = item.title
        priority = item.priority
        estimatedMinutes = item.estimatedMinutes.map(String.init) ?? ""
        relatedURL = item.relatedURL?.absoluteString ?? ""
        projectPath = item.projectPath ?? ""
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
