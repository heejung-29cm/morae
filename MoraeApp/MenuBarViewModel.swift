import Foundation
import MoraeCore
import Observation

enum BriefingViewState: Equatable, Sendable {
    case idle(previous: GeneratedBriefing?)
    case loading(previous: GeneratedBriefing?)
    case success(GeneratedBriefing)
    case failure(FailedBriefing, previous: GeneratedBriefing?)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var latestSuccess: GeneratedBriefing? {
        switch self {
        case let .idle(previous), let .loading(previous):
            previous
        case let .success(briefing):
            briefing
        case let .failure(_, previous):
            previous
        }
    }
}

extension BriefingErrorCode {
    var title: String {
        switch self {
        case .noEnabledFeeds: "사용 가능한 피드가 없습니다"
        case .noCandidates: "추천할 아티클이 없습니다"
        case .feedUnavailable: "피드를 불러오지 못했습니다"
        case .persistenceFailed: "브리핑을 저장하지 못했습니다"
        }
    }

    var message: String {
        switch self {
        case .noEnabledFeeds:
            "설정에서 하나 이상의 피드를 활성화해 주세요."
        case .noCandidates:
            "현재 피드에서 추천할 새 아티클을 찾지 못했습니다."
        case .feedUnavailable:
            "이번 실행에서 아티클을 가져오지 못했습니다."
        case .persistenceFailed:
            "로컬 데이터 처리 중 문제가 발생했습니다."
        }
    }

    var recovery: String {
        switch self {
        case .noEnabledFeeds:
            "피드 설정을 확인한 뒤 다음 브리핑을 직접 실행할 수 있습니다."
        case .noCandidates:
            "다음에 브리핑 버튼을 누르면 최신 피드를 다시 확인합니다."
        case .feedUnavailable:
            "이번 실행에서는 자동 재시도하지 않았습니다."
        case .persistenceFailed:
            "앱을 다시 연 뒤 브리핑을 직접 실행해 주세요."
        }
    }
}

@MainActor
@Observable
final class MenuBarViewModel {
    private(set) var todayTodos: [TodoItem] = []
    private(set) var yesterdayCompleted: [TodoItem] = []
    private(set) var yesterdayPending: [TodoItem] = []
    private(set) var selectedCarryOverIDs: Set<TodoID> = []
    private(set) var errorMessage: String?
    private(set) var validationMessage: String?
    private(set) var deletionCandidate: TodoItem?
    private(set) var recentlyDeleted: TodoItem?
    private(set) var briefingState: BriefingViewState = .idle(previous: nil)

    let today: LocalDay
    let yesterday: LocalDay

    private let repository: (any TodoRepository)?
    private let briefingRepository: (any BriefingRepository)?
    private let briefingGenerator: (any BriefingGenerating)?
    private let clock: any Clock
    private let uuidGenerator: any UUIDGenerating
    private let calendar: Calendar
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var undoExpirationTask: Task<Void, Never>?
    private var didLoadLatestBriefing = false

    init(
        repository: (any TodoRepository)?,
        briefingRepository: (any BriefingRepository)? = nil,
        briefingGenerator: (any BriefingGenerating)? = nil,
        clock: any Clock,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.briefingRepository = briefingRepository
        self.briefingGenerator = briefingGenerator
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.calendar = calendar
        let currentDay = clock.localDay(for: clock.now(), calendar: calendar)
        today = currentDay
        yesterday = Self.previousDay(of: currentDay, calendar: calendar)
    }

    func onAppear() async {
        await loadLatestBriefing()

        guard observationTask == nil, let repository else {
            return
        }

        do {
            async let todayRequest = repository.list(day: today)
            async let yesterdayRequest = repository.list(day: yesterday)
            async let carryOverRequest = repository.listCarryOverCandidates(
                from: yesterday,
                to: today
            )
            let (todayItems, yesterdayItems, carryOverItems) = try await (
                todayRequest,
                yesterdayRequest,
                carryOverRequest
            )
            todayTodos = todayItems
            yesterdayCompleted = yesterdayItems.filter { $0.status == .completed }
            yesterdayPending = carryOverItems
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

    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
    }

    func generateBriefing() async {
        guard !briefingState.isLoading, let briefingGenerator else {
            return
        }
        let previous = briefingState.latestSuccess
        briefingState = .loading(previous: previous)

        switch await briefingGenerator.execute(day: today) {
        case let .generated(briefing):
            briefingState = .success(briefing)
        case let .failed(failure):
            briefingState = .failure(failure, previous: previous)
        case .alreadyRunning:
            briefingState = .idle(previous: previous)
        }
    }

    func requestBriefing() async {
        guard !briefingState.isLoading, briefingGenerator != nil else {
            return
        }
        await generateBriefing()
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

    func addTodo(
        title: String,
        priority: TodoPriority = .normal
    ) async -> Bool {
        guard let repository else { return false }
        do {
            let instant = clock.now()
            let item = try TodoItem(
                id: TodoID(rawValue: uuidGenerator.next()),
                title: title,
                day: today,
                status: .pending,
                priority: priority,
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

    func movePending(id: TodoID, direction: TodoMoveDirection) async {
        var pending = todayTodos.filter { $0.status == .pending }
        guard let sourceIndex = pending.firstIndex(where: { $0.id == id }) else {
            return
        }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = sourceIndex - 1
        case .down:
            targetIndex = sourceIndex + 1
        }
        guard pending.indices.contains(targetIndex) else { return }
        pending.swapAt(sourceIndex, targetIndex)
        await persistPendingOrder(pending)
    }

    func movePending(id: TodoID, before targetID: TodoID?) async {
        let pending = todayTodos.filter { $0.status == .pending }
        guard let plan = TodoReorderPlan.moving(
            id,
            before: targetID,
            in: pending.map(\.id)
        ) else {
            return
        }
        let itemsByID = Dictionary(
            uniqueKeysWithValues: pending.map { ($0.id, $0) }
        )
        await persistPendingOrder(
            plan.orderedIDs.compactMap { itemsByID[$0] }
        )
    }

    func toggleCarryOverSelection(id: TodoID) {
        if selectedCarryOverIDs.contains(id) {
            selectedCarryOverIDs.remove(id)
        } else if yesterdayPending.contains(where: { $0.id == id }) {
            selectedCarryOverIDs.insert(id)
        }
    }

    func carryOverSelected() async {
        guard let repository, !selectedCarryOverIDs.isEmpty else { return }
        let carriedSourceIDs = selectedCarryOverIDs
        do {
            _ = try await CarryOverPendingTodos(
                repository: repository,
                clock: clock,
                uuidGenerator: uuidGenerator
            )
            .execute(
                from: yesterday,
                to: today,
                selectedIDs: yesterdayPending
                    .filter { selectedCarryOverIDs.contains($0.id) }
                    .map(\.id)
            )
            selectedCarryOverIDs = []
            yesterdayPending.removeAll {
                carriedSourceIDs.contains($0.id)
            }
        } catch {
            errorMessage = "어제 할 일을 가져오지 못했습니다."
        }
    }

    private func persistPendingOrder(_ pendingItems: [TodoItem]) async {
        guard let repository else { return }
        var reorderedPending = pendingItems
        var completed = todayTodos.filter { $0.status == .completed }
        for index in reorderedPending.indices {
            reorderedPending[index].sortOrder = index
        }
        for index in completed.indices {
            completed[index].sortOrder = reorderedPending.count + index
        }
        let allItems = reorderedPending + completed
        do {
            try await repository.reorder(
                day: today,
                orderedIDs: allItems.map(\.id)
            )
            todayTodos = allItems
        } catch {
            errorMessage = "할 일 순서를 변경하지 못했습니다."
        }
    }

    private func scheduleUndoExpiration() {
        undoExpirationTask?.cancel()
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.recentlyDeleted = nil
        }
    }

    private func loadLatestBriefing() async {
        guard !didLoadLatestBriefing else { return }
        didLoadLatestBriefing = true
        guard let repository,
              let briefingRepository else {
            return
        }

        do {
            guard let stored = try await briefingRepository.latest(day: today)
            else {
                briefingState = .idle(previous: nil)
                return
            }
            let localTasks = try await BuildLocalTaskSummary(
                repository: repository
            )
            .execute(today: today, calendar: calendar)
            switch stored.run.status {
            case .succeeded:
                briefingState = .success(
                    GeneratedBriefing(
                        stored: stored,
                        localTasks: localTasks,
                        failedFeedCount: 0
                    )
                )
            case .failed:
                briefingState = .failure(
                    FailedBriefing(
                        run: stored.run,
                        localTasks: localTasks,
                        code: stored.run.errorCode ?? .persistenceFailed,
                        failedFeedCount: 0
                    ),
                    previous: nil
                )
            case .running:
                briefingState = .idle(previous: nil)
            }
        } catch {
            briefingState = .failure(
                FailedBriefing(
                    run: nil,
                    localTasks: nil,
                    code: .persistenceFailed,
                    failedFeedCount: 0
                ),
                previous: nil
            )
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

    private static func previousDay(
        of day: LocalDay,
        calendar: Calendar
    ) -> LocalDay {
        let parts = day.rawValue.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = calendar.date(from: components),
              let previous = calendar.date(byAdding: .day, value: -1, to: date) else {
            return day
        }
        return LocalDay(date: previous, calendar: calendar)
    }

    deinit {
        observationTask?.cancel()
        undoExpirationTask?.cancel()
    }
}

enum TodoMoveDirection: Sendable {
    case up
    case down
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
