import Foundation
import GRDB
import MoraeCore

protocol TodoRepository: Sendable {
    func list(day: LocalDay) async throws -> [TodoItem]
    func listCompleted(day: LocalDay) async throws -> [TodoItem]
    func insert(_ item: TodoItem) async throws
    func update(_ item: TodoItem) async throws
    func setCompletion(id: TodoID, isCompleted: Bool, at: Date) async throws -> TodoItem
    func delete(id: TodoID) async throws
    func reorder(day: LocalDay, orderedIDs: [TodoID]) async throws
    func carryOverPending(from: LocalDay, to: LocalDay) async throws
    func carryOverPending(
        from: LocalDay,
        to: LocalDay,
        selectedIDs: [TodoID],
        newIDs: [TodoID],
        at: Date
    ) async throws -> [TodoItem]
    func observation(day: LocalDay) -> AsyncValueObservation<[TodoItem]>
}

enum TodoMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidDay(String)
    case invalidStatus(String)
    case invalidPriority(Int)
    case invalidURL(String)
    case invalidDomainValue(TodoValidationError)
}

enum TodoRepositoryError: Error, Equatable, Sendable {
    case notFound(TodoID)
    case reorderMismatch
}

struct TodoRecord: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "tasks"

    let id: String
    var title: String
    var taskDay: String
    var status: String
    var priority: Int
    var sortOrder: Int
    var estimatedMinutes: Int?
    var relatedURL: String?
    var projectPath: String?
    var source: String
    var completedAtMs: Int64?
    let createdAtMs: Int64
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case taskDay = "task_day"
        case status
        case priority
        case sortOrder = "sort_order"
        case estimatedMinutes = "estimated_minutes"
        case relatedURL = "related_url"
        case projectPath = "project_path"
        case source
        case completedAtMs = "completed_at_ms"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    init(item: TodoItem) {
        id = item.id.storageValue
        title = item.title
        taskDay = item.day.rawValue
        status = item.status.rawValue
        priority = item.priority.rawValue
        sortOrder = item.sortOrder
        estimatedMinutes = item.estimatedMinutes
        relatedURL = item.relatedURL?.absoluteString
        projectPath = item.projectPath
        source = "manual"
        completedAtMs = item.completedAt?.unixMilliseconds
        createdAtMs = item.createdAt.unixMilliseconds
        updatedAtMs = item.updatedAt.unixMilliseconds
    }

    func domain() throws -> TodoItem {
        guard let rawID = UUID(uuidString: id) else {
            throw TodoMappingError.invalidID(id)
        }

        let day: LocalDay
        do {
            day = try LocalDay(rawValue: taskDay)
        } catch {
            throw TodoMappingError.invalidDay(taskDay)
        }

        guard let domainStatus = TodoStatus(rawValue: status) else {
            throw TodoMappingError.invalidStatus(status)
        }
        guard let domainPriority = TodoPriority(rawValue: priority) else {
            throw TodoMappingError.invalidPriority(priority)
        }

        let domainURL: URL?
        if let relatedURL {
            guard let parsedURL = URL(string: relatedURL) else {
                throw TodoMappingError.invalidURL(relatedURL)
            }
            domainURL = parsedURL
        } else {
            domainURL = nil
        }

        do {
            return try TodoItem(
                id: TodoID(rawValue: rawID),
                title: title,
                day: day,
                status: domainStatus,
                priority: domainPriority,
                sortOrder: sortOrder,
                estimatedMinutes: estimatedMinutes,
                relatedURL: domainURL,
                projectPath: projectPath,
                completedAt: completedAtMs.map(Date.init(unixMilliseconds:)),
                createdAt: Date(unixMilliseconds: createdAtMs),
                updatedAt: Date(unixMilliseconds: updatedAtMs)
            )
        } catch let error as TodoValidationError {
            throw TodoMappingError.invalidDomainValue(error)
        }
    }
}

final class GRDBTodoRepository: @unchecked Sendable {
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        writer = database.writer
    }

    func list(day: LocalDay) async throws -> [TodoItem] {
        try await writer.read { database in
            try TodoRecord.fetchAll(
                database,
                sql: """
                    SELECT *
                    FROM tasks
                    WHERE task_day = ?
                    ORDER BY
                        CASE status WHEN 'pending' THEN 0 ELSE 1 END,
                        sort_order ASC,
                        created_at_ms ASC,
                        id ASC
                    """,
                arguments: [day.rawValue]
            )
            .map { try $0.domain() }
        }
    }

    func observation(day: LocalDay) -> AsyncValueObservation<[TodoItem]> {
        ValueObservation
            .tracking { database in
                try TodoRecord.fetchAll(
                    database,
                    sql: """
                        SELECT *
                        FROM tasks
                        WHERE task_day = ?
                        ORDER BY
                            CASE status WHEN 'pending' THEN 0 ELSE 1 END,
                            sort_order ASC,
                            created_at_ms ASC,
                            id ASC
                        """,
                    arguments: [day.rawValue]
                )
                .map { try $0.domain() }
            }
            .values(in: writer, bufferingPolicy: .bufferingNewest(1))
    }

    func listCompleted(day: LocalDay) async throws -> [TodoItem] {
        try await writer.read { database in
            try TodoRecord.fetchAll(
                database,
                sql: """
                    SELECT *
                    FROM tasks
                    WHERE task_day = ? AND status = ?
                    ORDER BY sort_order ASC, created_at_ms ASC, id ASC
                    """,
                arguments: [day.rawValue, TodoStatus.completed.rawValue]
            )
            .map { try $0.domain() }
        }
    }

    func insert(_ item: TodoItem) async throws {
        try await writer.write { database in
            try TodoRecord(item: item).insert(database)
        }
    }

    func update(_ item: TodoItem) async throws {
        try await writer.write { database in
            try TodoRecord(item: item).update(database)
        }
    }

    func setCompletion(
        id: TodoID,
        isCompleted: Bool,
        at date: Date
    ) async throws -> TodoItem {
        try await writer.write { database in
            guard var record = try TodoRecord.fetchOne(
                database,
                key: id.storageValue
            ) else {
                throw TodoRepositoryError.notFound(id)
            }

            record.status = isCompleted
                ? TodoStatus.completed.rawValue
                : TodoStatus.pending.rawValue
            record.completedAtMs = isCompleted ? date.unixMilliseconds : nil
            record.updatedAtMs = date.unixMilliseconds
            try record.update(database)
            return try record.domain()
        }
    }

    func delete(id: TodoID) async throws {
        try await writer.write { database in
            _ = try TodoRecord.deleteOne(database, key: id.storageValue)
        }
    }

    func reorder(day: LocalDay, orderedIDs: [TodoID]) async throws {
        try await writer.write { database in
            let storedIDs = try String.fetchAll(
                database,
                sql: "SELECT id FROM tasks WHERE task_day = ?",
                arguments: [day.rawValue]
            )
            let requestedIDs = orderedIDs.map(\.storageValue)
            guard requestedIDs.count == Set(requestedIDs).count,
                  Set(requestedIDs) == Set(storedIDs) else {
                throw TodoRepositoryError.reorderMismatch
            }

            for (sortOrder, id) in requestedIDs.enumerated() {
                try database.execute(
                    sql: """
                        UPDATE tasks
                        SET sort_order = ?
                        WHERE id = ? AND task_day = ?
                        """,
                    arguments: [sortOrder, id, day.rawValue]
                )
            }
        }
    }

    func carryOverPending(from: LocalDay, to: LocalDay) async throws {
        let pending = try await list(day: from).filter { $0.status == .pending }
        _ = try await carryOverPending(
            from: from,
            to: to,
            selectedIDs: pending.map(\.id),
            newIDs: pending.map { _ in TodoID(rawValue: UUID()) },
            at: Date()
        )
    }

    func carryOverPending(
        from: LocalDay,
        to: LocalDay,
        selectedIDs: [TodoID],
        newIDs: [TodoID],
        at date: Date
    ) async throws -> [TodoItem] {
        guard selectedIDs.count == Set(selectedIDs).count,
              selectedIDs.count == newIDs.count,
              newIDs.count == Set(newIDs).count else {
            throw TodoRepositoryError.reorderMismatch
        }
        guard !selectedIDs.isEmpty else {
            return []
        }

        return try await writer.write { database in
            let records = try TodoRecord.fetchAll(
                database,
                sql: """
                    SELECT *
                    FROM tasks
                    WHERE task_day = ? AND status = 'pending'
                    ORDER BY sort_order ASC, created_at_ms ASC, id ASC
                    """,
                arguments: [from.rawValue]
            )
            let recordsByID = Dictionary(
                uniqueKeysWithValues: records.map { ($0.id, $0) }
            )
            let requestedStorageIDs = selectedIDs.map(\.storageValue)
            guard requestedStorageIDs.allSatisfy({ recordsByID[$0] != nil }) else {
                throw TodoRepositoryError.reorderMismatch
            }

            let nextSortOrder = (
                try Int.fetchOne(
                    database,
                    sql: "SELECT MAX(sort_order) FROM tasks WHERE task_day = ?",
                    arguments: [to.rawValue]
                ) ?? -1
            ) + 1

            return try zip(requestedStorageIDs, newIDs)
                .enumerated()
                .map { offset, pair in
                    let (sourceID, newID) = pair
                    let source = try recordsByID[sourceID]!.domain()
                    let copy = try TodoItem(
                        id: newID,
                        title: source.title,
                        day: to,
                        status: .pending,
                        priority: source.priority,
                        sortOrder: nextSortOrder + offset,
                        estimatedMinutes: source.estimatedMinutes,
                        relatedURL: source.relatedURL,
                        projectPath: source.projectPath,
                        createdAt: date,
                        updatedAt: date
                    )
                    try TodoRecord(item: copy).insert(database)
                    return copy
                }
        }
    }
}

extension GRDBTodoRepository: TodoRepository {}
