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
