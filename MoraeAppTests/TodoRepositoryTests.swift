import Foundation
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
        let originals = try await repository.list(day: yesterday)
        let todayItems = try await repository.list(day: today)
        XCTAssertEqual(originals.count, 3)
        XCTAssertEqual(todayItems, copies)
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
