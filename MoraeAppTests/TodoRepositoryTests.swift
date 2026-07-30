import Foundation
import GRDB
import MoraeCore
import XCTest
@testable import MoraeApp

final class TodoRepositoryTests: XCTestCase {
    func testInsertAndListUsesDayStatusAndSortOrder() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let firstDay = try LocalDay(rawValue: "2026-07-29")
        let otherDay = try LocalDay(rawValue: "2026-07-30")

        try await repository.insert(
            makeTodo(title: "Pending second", day: firstDay, sortOrder: 1)
        )
        try await repository.insert(
            makeTodo(
                title: "Completed",
                day: firstDay,
                status: .completed,
                sortOrder: 0
            )
        )
        try await repository.insert(
            makeTodo(title: "Pending first", day: firstDay, sortOrder: 0)
        )
        try await repository.insert(
            makeTodo(title: "Different day", day: otherDay, sortOrder: 0)
        )

        let all = try await repository.list(day: firstDay)
        let completed = try await repository.listCompleted(day: firstDay)

        XCTAssertEqual(
            all.map(\.title),
            ["Pending first", "Pending second", "Completed"]
        )
        XCTAssertEqual(completed.map(\.title), ["Completed"])
    }

    func testTodoValidationRejectsEmptyAndOverlongTitles() throws {
        let day = try LocalDay(rawValue: "2026-07-29")

        XCTAssertThrowsError(
            try makeTodo(title: " \n ", day: day, sortOrder: 0)
        ) { error in
            XCTAssertEqual(error as? TodoValidationError, .emptyTitle)
        }
        XCTAssertThrowsError(
            try makeTodo(
                title: String(repeating: "가", count: 201),
                day: day,
                sortOrder: 0
            )
        ) { error in
            XCTAssertEqual(error as? TodoValidationError, .titleTooLong)
        }
    }

    func testUpdatePersistsTitleMetadataAndUpdatedAt() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-29")
        let original = try makeTodo(
            title: "Original",
            day: day,
            sortOrder: 0
        )
        try await repository.insert(original)

        let updatedAt = Date(unixMilliseconds: original.updatedAt.unixMilliseconds + 500)
        let updated = try TodoItem(
            id: original.id,
            title: "Updated",
            day: day,
            status: .pending,
            priority: .important,
            sortOrder: 0,
            estimatedMinutes: 90,
            relatedURL: URL(string: "file:///tmp/result.txt"),
            projectPath: "/tmp/project",
            createdAt: original.createdAt,
            updatedAt: updatedAt
        )
        try await repository.update(updated)

        let items = try await repository.list(day: day)
        let restored = try XCTUnwrap(items.first)
        XCTAssertEqual(restored.title, "Updated")
        XCTAssertEqual(restored.priority, .important)
        XCTAssertEqual(restored.estimatedMinutes, 90)
        XCTAssertEqual(restored.relatedURL, URL(string: "file:///tmp/result.txt"))
        XCTAssertEqual(restored.projectPath, "/tmp/project")
        XCTAssertEqual(restored.updatedAt, updatedAt)
        XCTAssertEqual(restored.createdAt, original.createdAt)
    }

    func testCompletionTransitionKeepsStatusInvariantInOneTransaction() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-29")
        let original = try makeTodo(
            title: "Toggle me",
            day: day,
            sortOrder: 0
        )
        try await repository.insert(original)

        let completionTime = Date(unixMilliseconds: 1_775_039_900_000)
        let completed = try await repository.setCompletion(
            id: original.id,
            isCompleted: true,
            at: completionTime
        )
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.completedAt, completionTime)
        XCTAssertEqual(completed.updatedAt, completionTime)

        let reopenedAt = Date(unixMilliseconds: 1_775_040_000_000)
        let pending = try await repository.setCompletion(
            id: original.id,
            isCompleted: false,
            at: reopenedAt
        )
        XCTAssertEqual(pending.status, .pending)
        XCTAssertNil(pending.completedAt)
        XCTAssertEqual(pending.updatedAt, reopenedAt)

        let stored = try await repository.list(day: day)
        XCTAssertEqual(stored, [pending])
    }

    func testDeleteRemovesOnlyTargetAndMissingIDIsNoOp() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-29")
        let retained = try makeTodo(
            title: "Retained",
            day: day,
            sortOrder: 0
        )
        let deleted = try makeTodo(
            title: "Deleted",
            day: day,
            sortOrder: 1
        )
        try await repository.insert(retained)
        try await repository.insert(deleted)

        try await repository.delete(id: deleted.id)
        try await repository.delete(id: TodoID(rawValue: UUID()))

        let remaining = try await repository.list(day: day)
        XCTAssertEqual(remaining, [retained])
    }

    func testReorderAssignsUniqueContiguousOrderInTransaction() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-29")
        let first = try makeTodo(title: "First", day: day, sortOrder: 4)
        let second = try makeTodo(title: "Second", day: day, sortOrder: 4)
        let third = try makeTodo(title: "Third", day: day, sortOrder: 9)
        for item in [first, second, third] {
            try await repository.insert(item)
        }

        try await repository.reorder(
            day: day,
            orderedIDs: [third.id, first.id, second.id]
        )

        let stored = try await repository.list(day: day)
        XCTAssertEqual(stored.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(stored.map(\.sortOrder), [0, 1, 2])
    }

    func testReorderMismatchRollsBackWithoutChangingOrder() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-29")
        let first = try makeTodo(title: "First", day: day, sortOrder: 0)
        let second = try makeTodo(title: "Second", day: day, sortOrder: 1)
        try await repository.insert(first)
        try await repository.insert(second)

        do {
            try await repository.reorder(
                day: day,
                orderedIDs: [first.id, first.id]
            )
            XCTFail("Expected reorderMismatch")
        } catch {
            XCTAssertEqual(error as? TodoRepositoryError, .reorderMismatch)
        }

        let stored = try await repository.list(day: day)
        XCTAssertEqual(stored.map(\.id), [first.id, second.id])
        XCTAssertEqual(stored.map(\.sortOrder), [0, 1])
    }

    func testCarryOverCopiesSelectedPendingOnceWithoutChangingOriginals() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let yesterday = try LocalDay(rawValue: "2026-07-29")
        let today = try LocalDay(rawValue: "2026-07-30")
        let selected = try makeTodo(
            title: "Selected",
            day: yesterday,
            priority: .important,
            sortOrder: 0,
            estimatedMinutes: 30
        )
        let unselected = try makeTodo(
            title: "Unselected",
            day: yesterday,
            sortOrder: 1
        )
        let completed = try makeTodo(
            title: "Completed",
            day: yesterday,
            status: .completed,
            sortOrder: 2
        )
        for item in [selected, unselected, completed] {
            try await repository.insert(item)
        }

        let newID = TodoID(
            rawValue: UUID(uuidString: "AD48D4DB-8B28-4BF0-99D2-899B65D73DB2")!
        )
        let instant = Date(unixMilliseconds: 1_775_040_000_000)
        let useCase = CarryOverPendingTodos(
            repository: repository,
            clock: FixedClock(instant: instant),
            uuidGenerator: FixedUUIDGenerator(uuid: newID.rawValue)
        )
        let copies = try await useCase.execute(
            from: yesterday,
            to: today,
            selectedIDs: [selected.id]
        )

        XCTAssertEqual(copies.map(\.id), [newID])
        XCTAssertEqual(copies.map(\.title), ["Selected"])
        XCTAssertEqual(copies.first?.day, today)
        XCTAssertEqual(copies.first?.status, .pending)
        XCTAssertNil(copies.first?.completedAt)
        let repeatedCopies = try await useCase.execute(
            from: yesterday,
            to: today,
            selectedIDs: [selected.id]
        )
        XCTAssertTrue(repeatedCopies.isEmpty)
        let originals = try await repository.list(day: yesterday)
        let todayItems = try await repository.list(day: today)
        let remainingCandidates = try await repository.listCarryOverCandidates(
            from: yesterday,
            to: today
        )
        XCTAssertEqual(originals.count, 3)
        XCTAssertEqual(todayItems, copies)
        XCTAssertEqual(remainingCandidates.map(\.id), [unselected.id])
    }

    func testLocalSummaryUsesCalendarAndPrioritizesImportantTodos() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let yesterday = try LocalDay(rawValue: "2026-03-07")
        let today = try LocalDay(rawValue: "2026-03-08")
        let yesterdayDone = try makeTodo(
            title: "Yesterday done",
            day: yesterday,
            status: .completed,
            sortOrder: 0
        )
        let normal = try makeTodo(
            title: "Normal",
            day: today,
            sortOrder: 0,
            estimatedMinutes: 20
        )
        let important = try makeTodo(
            title: "Important",
            day: today,
            priority: .important,
            sortOrder: 5,
            estimatedMinutes: 40
        )
        let todayDone = try makeTodo(
            title: "Today done",
            day: today,
            status: .completed,
            sortOrder: 9
        )
        for item in [yesterdayDone, normal, important, todayDone] {
            try await repository.insert(item)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let summary = try await BuildLocalTaskSummary(repository: repository)
            .execute(today: today, calendar: calendar)

        XCTAssertEqual(summary.yesterdayCompleted, [yesterdayDone])
        XCTAssertEqual(summary.todayPending.map(\.id), [important.id, normal.id])
        XCTAssertEqual(summary.todayCompletedCount, 1)
        XCTAssertEqual(summary.todayEstimatedMinutes, 60)
        XCTAssertEqual(summary.mostImportantTodoID, important.id)
    }

    func testTodoObservationEmitsInsertAndCompletionChanges() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-29")
        let item = try makeTodo(title: "Observed", day: day, sortOrder: 0)
        var iterator = repository.observation(day: day).makeAsyncIterator()

        let initial = try await iterator.next()
        XCTAssertEqual(initial, [])
        try await repository.insert(item)
        let afterInsert = try await iterator.next()
        XCTAssertEqual(afterInsert, [item])

        let completedAt = Date(unixMilliseconds: 1_775_040_000_000)
        let completed = try await repository.setCompletion(
            id: item.id,
            isCompleted: true,
            at: completedAt
        )
        let afterCompletion = try await iterator.next()
        XCTAssertEqual(afterCompletion, [completed])
    }

    @MainActor
    func testMenuBarViewModelAddEditDeleteConfirmAndUndoFlow() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let instant = Date(unixMilliseconds: 1_775_040_000_000)
        let uuid = UUID(uuidString: "F47ADFE1-0AAE-42D6-9D38-9EC1FBDBE35C")!
        let viewModel = MenuBarViewModel(
            repository: repository,
            clock: FixedClock(instant: instant),
            uuidGenerator: FixedUUIDGenerator(uuid: uuid),
            calendar: Calendar(identifier: .gregorian)
        )

        let invalidAddResult = await viewModel.addTodo(title: "  ")
        XCTAssertFalse(invalidAddResult)
        XCTAssertEqual(viewModel.validationMessage, "제목을 입력해 주세요.")
        let addResult = await viewModel.addTodo(title: "New todo")
        XCTAssertTrue(addResult)

        let created = try XCTUnwrap(viewModel.todayTodos.first)
        var draft = TodoEditDraft(item: created)
        draft.title = "Edited todo"
        draft.priority = .important
        draft.estimatedMinutes = "45"
        draft.relatedURL = "https://example.com"
        let updateResult = await viewModel.updateTodo(draft)
        XCTAssertTrue(updateResult)
        XCTAssertEqual(viewModel.todayTodos.first?.title, "Edited todo")
        XCTAssertEqual(viewModel.todayTodos.first?.estimatedMinutes, 45)

        viewModel.requestDelete(id: created.id)
        XCTAssertEqual(viewModel.deletionCandidate?.id, created.id)
        viewModel.cancelDelete()
        XCTAssertNil(viewModel.deletionCandidate)

        viewModel.requestDelete(id: created.id)
        await viewModel.confirmDelete()
        XCTAssertTrue(viewModel.todayTodos.isEmpty)
        XCTAssertEqual(viewModel.recentlyDeleted?.id, created.id)

        await viewModel.undoDelete()
        XCTAssertEqual(viewModel.todayTodos.map(\.id), [created.id])
        let stored = try await repository.list(day: viewModel.today)
        XCTAssertEqual(stored.map(\.id), [created.id])
    }

    @MainActor
    func testMenuBarViewModelReordersAndCarriesOverWithKeyboardPath() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let instant = Date(unixMilliseconds: 1_775_040_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let newUUID = UUID(uuidString: "D411AB16-06F6-4A26-9EF1-C757690943AB")!
        let viewModel = MenuBarViewModel(
            repository: repository,
            clock: FixedClock(instant: instant),
            uuidGenerator: FixedUUIDGenerator(uuid: newUUID),
            calendar: calendar
        )
        let first = try makeTodo(
            title: "First",
            day: viewModel.today,
            sortOrder: 0
        )
        let second = try makeTodo(
            title: "Second",
            day: viewModel.today,
            sortOrder: 1
        )
        let yesterdayPending = try makeTodo(
            title: "Carry",
            day: viewModel.yesterday,
            sortOrder: 0
        )
        for item in [first, second, yesterdayPending] {
            try await repository.insert(item)
        }
        await viewModel.onAppear()

        await viewModel.movePending(id: first.id, direction: .down)
        let reordered = try await repository.list(day: viewModel.today)
        XCTAssertEqual(reordered.prefix(2).map(\.id), [second.id, first.id])

        viewModel.toggleCarryOverSelection(id: yesterdayPending.id)
        XCTAssertEqual(viewModel.selectedCarryOverIDs, [yesterdayPending.id])
        await viewModel.carryOverSelected()

        let carried = try await repository.list(day: viewModel.today)
        XCTAssertTrue(carried.contains(where: { $0.id.rawValue == newUUID }))
        XCTAssertTrue(viewModel.selectedCarryOverIDs.isEmpty)
        XCTAssertTrue(viewModel.yesterdayPending.isEmpty)
        let originals = try await repository.list(day: viewModel.yesterday)
        XCTAssertEqual(originals.map(\.id), [yesterdayPending.id])
    }

    func testSprintOneDemoPersistsAndRollsCompletedIntoYesterday() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("morae.sqlite")
        let dayOne = try LocalDay(rawValue: "2026-07-29")
        let dayTwo = try LocalDay(rawValue: "2026-07-30")
        let first = try makeTodo(
            title: "Plan demo",
            day: dayOne,
            sortOrder: 0
        )
        let completed = try makeTodo(
            title: "Complete demo",
            day: dayOne,
            sortOrder: 1
        )
        let deleted = try makeTodo(
            title: "Delete demo",
            day: dayOne,
            sortOrder: 2
        )

        do {
            let database = try AppDatabase.open(at: databaseURL)
            let repository = GRDBTodoRepository(database: database)
            for item in [first, completed, deleted] {
                try await repository.insert(item)
            }
            let edited = try TodoItem(
                id: first.id,
                title: "Edited demo",
                day: dayOne,
                status: .pending,
                priority: .important,
                sortOrder: first.sortOrder,
                estimatedMinutes: 25,
                createdAt: first.createdAt,
                updatedAt: Date(unixMilliseconds: 1_775_039_500_000)
            )
            try await repository.update(edited)
            try await repository.reorder(
                day: dayOne,
                orderedIDs: [completed.id, first.id, deleted.id]
            )
            _ = try await repository.setCompletion(
                id: completed.id,
                isCompleted: true,
                at: Date(unixMilliseconds: 1_775_039_600_000)
            )
            try await repository.delete(id: deleted.id)
        }

        let reopenedDatabase = try AppDatabase.open(at: databaseURL)
        let reopenedRepository = GRDBTodoRepository(database: reopenedDatabase)
        let persisted = try await reopenedRepository.list(day: dayOne)
        XCTAssertEqual(persisted.map(\.id), [first.id, completed.id])
        XCTAssertEqual(persisted.first?.title, "Edited demo")
        XCTAssertEqual(persisted.first?.priority, .important)
        XCTAssertEqual(persisted.first?.estimatedMinutes, 25)
        XCTAssertEqual(persisted.last?.status, .completed)

        let persistedSortOrder = try reopenedDatabase.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT id FROM tasks WHERE task_day = ? ORDER BY sort_order",
                arguments: [dayOne.rawValue]
            )
        }
        XCTAssertEqual(
            persistedSortOrder,
            [completed.id.storageValue, first.id.storageValue]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let nextDaySummary = try await BuildLocalTaskSummary(
            repository: reopenedRepository
        )
        .execute(today: dayTwo, calendar: calendar)
        XCTAssertEqual(nextDaySummary.yesterdayCompleted.map(\.id), [completed.id])
        XCTAssertTrue(nextDaySummary.todayPending.isEmpty)
    }

    @MainActor
    func testDragDropPersistsExactlyOnceAndSkipsNoOp() async throws {
        let database = try AppDatabase.inMemory()
        let baseRepository = GRDBTodoRepository(database: database)
        let repository = CountingTodoRepository(base: baseRepository)
        let day = try LocalDay(rawValue: "2026-04-01")
        let first = try makeTodo(title: "First", day: day, sortOrder: 0)
        let second = try makeTodo(title: "Second", day: day, sortOrder: 1)
        let third = try makeTodo(title: "Third", day: day, sortOrder: 2)
        for item in [first, second, third] {
            try await baseRepository.insert(item)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let viewModel = MenuBarViewModel(
            repository: repository,
            clock: FixedClock(
                instant: Date(unixMilliseconds: 1_775_001_600_000)
            ),
            calendar: calendar
        )
        XCTAssertEqual(viewModel.today, day)
        await viewModel.onAppear()

        await viewModel.movePending(id: third.id, before: first.id)
        XCTAssertEqual(repository.reorderCallCount, 1)

        await viewModel.movePending(id: first.id, before: second.id)
        XCTAssertEqual(repository.reorderCallCount, 1)
    }
}

private final class CountingTodoRepository: TodoRepository, @unchecked Sendable {
    private let base: GRDBTodoRepository
    private let lock = NSLock()
    private var storedReorderCallCount = 0

    init(base: GRDBTodoRepository) {
        self.base = base
    }

    var reorderCallCount: Int {
        lock.withLock { storedReorderCallCount }
    }

    func list(day: LocalDay) async throws -> [TodoItem] {
        try await base.list(day: day)
    }

    func listCompleted(day: LocalDay) async throws -> [TodoItem] {
        try await base.listCompleted(day: day)
    }

    func listCarryOverCandidates(
        from: LocalDay,
        to: LocalDay
    ) async throws -> [TodoItem] {
        try await base.listCarryOverCandidates(from: from, to: to)
    }

    func insert(_ item: TodoItem) async throws {
        try await base.insert(item)
    }

    func update(_ item: TodoItem) async throws {
        try await base.update(item)
    }

    func setCompletion(
        id: TodoID,
        isCompleted: Bool,
        at date: Date
    ) async throws -> TodoItem {
        try await base.setCompletion(
            id: id,
            isCompleted: isCompleted,
            at: date
        )
    }

    func delete(id: TodoID) async throws {
        try await base.delete(id: id)
    }

    func reorder(day: LocalDay, orderedIDs: [TodoID]) async throws {
        lock.withLock {
            storedReorderCallCount += 1
        }
        try await base.reorder(day: day, orderedIDs: orderedIDs)
    }

    func carryOverPending(
        from: LocalDay,
        to: LocalDay
    ) async throws {
        try await base.carryOverPending(from: from, to: to)
    }

    func carryOverPending(
        from: LocalDay,
        to: LocalDay,
        selectedIDs: [TodoID],
        newIDs: [TodoID],
        at date: Date
    ) async throws -> [TodoItem] {
        try await base.carryOverPending(
            from: from,
            to: to,
            selectedIDs: selectedIDs,
            newIDs: newIDs,
            at: date
        )
    }

    func observation(day: LocalDay) -> AsyncValueObservation<[TodoItem]> {
        base.observation(day: day)
    }
}

func makeTodo(
    id: UUID = UUID(),
    title: String,
    day: LocalDay,
    status: TodoStatus = .pending,
    priority: TodoPriority = .normal,
    sortOrder: Int,
    estimatedMinutes: Int? = nil,
    relatedURL: URL? = nil,
    projectPath: String? = nil,
    completedAt: Date? = nil,
    createdAt: Date = Date(unixMilliseconds: 1_775_039_000_000),
    updatedAt: Date = Date(unixMilliseconds: 1_775_039_000_000)
) throws -> TodoItem {
    try TodoItem(
        id: TodoID(rawValue: id),
        title: title,
        day: day,
        status: status,
        priority: priority,
        sortOrder: sortOrder,
        estimatedMinutes: estimatedMinutes,
        relatedURL: relatedURL,
        projectPath: projectPath,
        completedAt: status == .completed
            ? (completedAt ?? updatedAt)
            : nil,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}
