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

enum AIReportViewState: Equatable, Sendable {
    case idle(previous: AIReport?)
    case loading(previous: AIReport?)
    case success(AIReport)
    case failure(code: AIReportErrorCode, previous: AIReport?)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var latestSuccess: AIReport? {
        switch self {
        case let .idle(previous), let .loading(previous):
            previous
        case let .success(report):
            report
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
        case .persistenceFailed: "추천 아티클을 저장하지 못했습니다"
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
            "피드 설정을 확인한 뒤 아티클 추천을 다시 실행해 주세요."
        case .noCandidates:
            "다음에 아티클 추천받기를 누르면 최신 피드를 다시 확인합니다."
        case .feedUnavailable:
            "이번 실행에서는 자동 재시도하지 않았습니다."
        case .persistenceFailed:
            "앱을 다시 연 뒤 아티클 추천을 실행해 주세요."
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
    private(set) var aiReportState: AIReportViewState = .idle(previous: nil)
    private(set) var savedArticles: [Article] = []
    private(set) var jiraSyncMessage: String?
    private(set) var isJiraConnected = false
    private(set) var isJiraSyncing = false

    private(set) var today: LocalDay
    private(set) var yesterday: LocalDay

    private let repository: (any TodoRepository)?
    private let briefingRepository: (any BriefingRepository)?
    private let briefingGenerator: (any BriefingGenerating)?
    private let aiReportRepository: (any AIReportRepository)?
    private let aiReportGenerator: (any AIReportGenerating)?
    private let articleRepository: (any ArticleRepository)?
    private let clock: any Clock
    private let uuidGenerator: any UUIDGenerating
    private let jiraIntegration: JiraIntegrationService?
    private let calendar: Calendar
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var undoExpirationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var validationExpirationTask: Task<Void, Never>?
    private let validationMessageDuration: Duration
    private var didLoadLatestBriefing = false
    private var didLoadLatestAIReport = false
    private var isRefreshingDay = false
    private var dayRefreshRequested = false

    init(
        repository: (any TodoRepository)?,
        briefingRepository: (any BriefingRepository)? = nil,
        briefingGenerator: (any BriefingGenerating)? = nil,
        aiReportRepository: (any AIReportRepository)? = nil,
        aiReportGenerator: (any AIReportGenerating)? = nil,
        articleRepository: (any ArticleRepository)? = nil,
        clock: any Clock,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator(),
        calendar: Calendar = .autoupdatingCurrent,
        jiraIntegration: JiraIntegrationService? = nil,
        validationMessageDuration: Duration = .seconds(3)
    ) {
        self.repository = repository
        self.briefingRepository = briefingRepository
        self.briefingGenerator = briefingGenerator
        self.aiReportRepository = aiReportRepository
        self.aiReportGenerator = aiReportGenerator
        self.articleRepository = articleRepository
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.calendar = calendar
        self.jiraIntegration = jiraIntegration
        self.validationMessageDuration = validationMessageDuration
        let currentDay = clock.localDay(for: clock.now(), calendar: calendar)
        today = currentDay
        yesterday = Self.previousDay(of: currentDay, calendar: calendar)
    }

    func onAppear() async {
        await refreshDayIfNeeded()
    }

    func refreshDayIfNeeded() async {
        if isRefreshingDay {
            dayRefreshRequested = true
            return
        }

        isRefreshingDay = true
        repeat {
            dayRefreshRequested = false
            await refreshCurrentDay()
        } while dayRefreshRequested
        isRefreshingDay = false
    }

    private func refreshCurrentDay() async {
        let currentDay = clock.localDay(for: clock.now(), calendar: calendar)
        if currentDay != today {
            switchToDay(currentDay)
        }

        await loadLatestBriefing()
        await loadLatestAIReport()
        await loadSavedArticles()
        await refreshJiraConnectionState()
        await syncJiraAutomatically(day: currentDay)

        guard observationTask == nil, let repository else {
            return
        }

        let targetToday = today
        let targetYesterday = yesterday
        do {
            async let todayRequest = repository.list(day: targetToday)
            async let yesterdayRequest = repository.list(day: targetYesterday)
            async let carryOverRequest = repository.listCarryOverCandidates(
                from: targetYesterday,
                to: targetToday
            )
            let (todayItems, yesterdayItems, carryOverItems) = try await (
                todayRequest,
                yesterdayRequest,
                carryOverRequest
            )
            guard today == targetToday else { return }
            todayTodos = todayItems
            yesterdayCompleted = yesterdayItems.filter { $0.status == .completed }
            yesterdayPending = carryOverItems
        } catch {
            errorMessage = "할 일 요약을 불러오지 못했습니다."
        }

        guard today == targetToday else { return }
        observationTask = Task { [weak self, repository, targetToday] in
            do {
                for try await items in repository.observation(day: targetToday) {
                    guard !Task.isCancelled else { return }
                    guard self?.today == targetToday else { return }
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

    private func switchToDay(_ day: LocalDay) {
        observationTask?.cancel()
        observationTask = nil
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        validationExpirationTask?.cancel()
        validationExpirationTask = nil

        today = day
        yesterday = Self.previousDay(of: day, calendar: calendar)
        todayTodos = []
        yesterdayCompleted = []
        yesterdayPending = []
        selectedCarryOverIDs = []
        deletionCandidate = nil
        recentlyDeleted = nil
        errorMessage = nil
        validationMessage = nil
        briefingState = .idle(previous: nil)
        didLoadLatestBriefing = false
        jiraSyncMessage = nil
    }

    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
        clearValidationMessage()
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

    /// 어제 하루치 AI 활용 리포트를 요청한다. 오늘이 아니라 어제를 쓰는 이유는
    /// 진행 중인 하루는 백분위 같은 비교 지표가 아직 확정되지 않기 때문이다.
    func requestAIReport() async {
        guard !aiReportState.isLoading, let aiReportGenerator else {
            return
        }
        let previous = aiReportState.latestSuccess
        aiReportState = .loading(previous: previous)

        switch await aiReportGenerator.execute(day: yesterday) {
        case let .generated(report):
            aiReportState = .success(report)
        case let .failed(_, code):
            aiReportState = .failure(code: code, previous: previous)
        case .alreadyRunning:
            aiReportState = .idle(previous: previous)
        }
    }

    func markArticleRead(_ article: Article) async {
        guard let articleRepository else { return }
        do {
            try await articleRepository.setRead(
                canonicalURL: article.canonicalURL,
                isRead: true,
                at: clock.now()
            )
        } catch {
            errorMessage = "읽음 상태를 저장하지 못했습니다."
        }
    }

    func toggleArticleSaved(_ article: Article) async {
        guard let articleRepository else { return }
        do {
            try await articleRepository.setLiked(
                canonicalURL: article.canonicalURL,
                isLiked: !article.isLiked,
                at: clock.now()
            )
            await reloadArticleState()
        } catch {
            errorMessage = "나중에 읽기 상태를 저장하지 못했습니다."
        }
    }

    func toggleMoreLikeThis(_ article: Article) async {
        let feedback: ArticleFeedback = article.feedback == .moreLikeThis
            ? .neutral
            : .moreLikeThis
        await updateArticleFeedback(article, feedback: feedback)
    }

    func dismissArticle(_ article: Article) async {
        guard let articleRepository else { return }
        do {
            try await articleRepository.setFeedback(
                canonicalURL: article.canonicalURL,
                feedback: .notInterested,
                at: clock.now()
            )
            briefingState = .idle(previous: nil)
            await loadSavedArticles()
            await generateBriefing()
        } catch {
            errorMessage = "아티클 피드백을 저장하지 못했습니다."
        }
    }

    private func updateArticleFeedback(
        _ article: Article,
        feedback: ArticleFeedback
    ) async {
        guard let articleRepository else { return }
        do {
            try await articleRepository.setFeedback(
                canonicalURL: article.canonicalURL,
                feedback: feedback,
                at: clock.now()
            )
            await reloadArticleState()
        } catch {
            errorMessage = "아티클 피드백을 저장하지 못했습니다."
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
            clearValidationMessage()
            return true
        } catch let error as TodoValidationError {
            showValidationMessage(validationText(for: error))
            return false
        } catch {
            errorMessage = "할 일을 저장하지 못했습니다."
            return false
        }
    }

    func updateTodo(_ draft: TodoEditDraft) async -> Bool {
        guard let repository,
              let original = todayTodos.first(where: { $0.id == draft.id }),
              !original.origin.isJira else {
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
                origin: original.origin,
                completedAt: original.completedAt,
                createdAt: original.createdAt,
                updatedAt: clock.now()
            )
            try await repository.update(updated)
            if let index = todayTodos.firstIndex(where: { $0.id == updated.id }) {
                todayTodos[index] = updated
            }
            clearValidationMessage()
            return true
        } catch let error as TodoValidationError {
            showValidationMessage(validationText(for: error))
            return false
        } catch {
            errorMessage = "할 일을 수정하지 못했습니다."
            return false
        }
    }

    func requestDelete(id: TodoID) {
        deletionCandidate = todayTodos.first { $0.id == id }
    }

    func cancelDelete() {
        deletionCandidate = nil
    }

    func confirmDelete() async {
        guard let repository,
              let item = deletionCandidate else {
            return
        }
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
        validationExpirationTask?.cancel()
        validationExpirationTask = nil
        validationMessage = nil
    }

    func syncJiraNow() async {
        guard let jiraIntegration, isJiraConnected, !isJiraSyncing else {
            return
        }
        isJiraSyncing = true
        jiraSyncMessage = nil
        defer { isJiraSyncing = false }
        do {
            let result = try await jiraIntegration.sync(
                day: today,
                mode: .manual
            )
            jiraSyncMessage = result.importedCount == 0
                ? "새 Jira 항목 없이 \(result.refreshedCount)개를 확인했습니다."
                : "Jira에서 \(result.importedCount)개를 추가하고 \(result.refreshedCount)개를 갱신했습니다."
        } catch JiraIntegrationError.notConnected {
            isJiraConnected = false
            jiraSyncMessage = "Jira 연결이 해제되었습니다. 설정에서 다시 연결해 주세요."
        } catch {
            jiraSyncMessage = (error as? LocalizedError)?.errorDescription
                ?? "Jira 항목을 가져오지 못했습니다."
        }
    }

    private func showValidationMessage(_ message: String) {
        validationExpirationTask?.cancel()
        validationMessage = message
        validationExpirationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: validationMessageDuration)
            guard !Task.isCancelled else { return }
            validationMessage = nil
            validationExpirationTask = nil
        }
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

    /// 저장된 마지막 리포트를 복원한다. 리포트는 날짜별로 한 행만 유지되므로
    /// 어제 것을 아직 받지 않았다면 그 이전 리포트가 그대로 남아 있다.
    private func loadLatestAIReport() async {
        guard !didLoadLatestAIReport else { return }
        didLoadLatestAIReport = true
        guard let aiReportRepository else { return }

        do {
            guard let report = try await aiReportRepository.latest() else {
                aiReportState = .idle(previous: nil)
                return
            }
            switch report.status {
            case .succeeded:
                aiReportState = .success(report)
            case .failed:
                aiReportState = .failure(
                    code: report.errorCode ?? .scriptFailed,
                    previous: nil
                )
            case .running:
                aiReportState = .idle(previous: nil)
            }
        } catch {
            aiReportState = .idle(previous: nil)
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

    private func reloadArticleState() async {
        didLoadLatestBriefing = false
        await loadLatestBriefing()
        await loadSavedArticles()
    }

    private func loadSavedArticles() async {
        guard let articleRepository else { return }
        do {
            savedArticles = try await articleRepository.savedArticles(limit: 5)
        } catch {
            errorMessage = "저장한 아티클을 불러오지 못했습니다."
        }
    }

    private func syncJiraAutomatically(day: LocalDay) async {
        guard let jiraIntegration, isJiraConnected, !isJiraSyncing else {
            return
        }
        isJiraSyncing = true
        defer { isJiraSyncing = false }
        do {
            let result = try await jiraIntegration.sync(
                day: day,
                mode: .automatic
            )
            guard !result.skippedBecauseAlreadyAttempted else { return }
            jiraSyncMessage = result.importedCount > 0
                ? "Jira에서 \(result.importedCount)개를 추가했습니다."
                : nil
        } catch JiraIntegrationError.notConnected {
            isJiraConnected = false
            return
        } catch {
            jiraSyncMessage =
                "Jira 자동 가져오기에 실패했습니다. Jira 버튼으로 다시 시도할 수 있습니다."
        }
    }

    private func refreshJiraConnectionState() async {
        guard let jiraIntegration else {
            isJiraConnected = false
            return
        }
        isJiraConnected = await jiraIntegration.snapshot().connection != nil
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
        validationExpirationTask?.cancel()
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
