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
