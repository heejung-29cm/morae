import Foundation
import GRDB
import MoraeCore

protocol TodoRepository: Sendable {
    func list(day: LocalDay) async throws -> [TodoItem]
    func listCompleted(day: LocalDay) async throws -> [TodoItem]
    func listCarryOverCandidates(
        from: LocalDay,
        to: LocalDay
    ) async throws -> [TodoItem]
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
    func importJira(
        _ issues: [JiraIssueSnapshot],
        day: LocalDay,
        displayBaseURL: URL,
        newIDs: [TodoID],
        at: Date
    ) async throws -> JiraTodoImportResult
    func observation(day: LocalDay) -> AsyncValueObservation<[TodoItem]>
}

struct JiraTodoImportResult: Equatable, Sendable {
    let importedCount: Int
    let refreshedCount: Int
}

enum TodoMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidDay(String)
    case invalidStatus(String)
    case invalidPriority(Int)
    case invalidURL(String)
    case invalidExternalMetadata
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
    var externalProvider: String?
    var externalID: String?
    var externalKey: String?
    var externalStatusCategory: String?
    var externalStatusName: String?
    var externalStartDay: String?
    var externalDueDay: String?
    var externalSyncedAtMs: Int64?
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
        case externalProvider = "external_provider"
        case externalID = "external_id"
        case externalKey = "external_key"
        case externalStatusCategory = "external_status_category"
        case externalStatusName = "external_status_name"
        case externalStartDay = "external_start_day"
        case externalDueDay = "external_due_day"
        case externalSyncedAtMs = "external_synced_at_ms"
        case completedAtMs = "completed_at_ms"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    init(item: TodoItem) {
        let source: String
        switch item.origin {
        case .manual, .jira:
            source = item.origin.isJira ? "jira" : "manual"
        case let .carryOver(sourceID):
            source = "carryover:\(sourceID.storageValue)"
        }
        self.init(item: item, source: source)
    }

    init(item: TodoItem, source: String) {
        id = item.id.storageValue
        title = item.title
        taskDay = item.day.rawValue
        status = item.status.rawValue
        priority = item.priority.rawValue
        sortOrder = item.sortOrder
        estimatedMinutes = item.estimatedMinutes
        relatedURL = item.relatedURL?.absoluteString
        projectPath = item.projectPath
        self.source = source
        switch item.origin {
        case let .jira(metadata):
            externalProvider = "jira"
            externalID = metadata.issueID
            externalKey = metadata.issueKey
            externalStatusCategory = metadata.statusCategory
            externalStatusName = metadata.statusName
            externalStartDay = metadata.startDay?.rawValue
            externalDueDay = metadata.dueDay?.rawValue
            externalSyncedAtMs = metadata.syncedAt.unixMilliseconds
        case .manual, .carryOver:
            externalProvider = nil
            externalID = nil
            externalKey = nil
            externalStatusCategory = nil
            externalStatusName = nil
            externalStartDay = nil
            externalDueDay = nil
            externalSyncedAtMs = nil
        }
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

        let origin: TodoOrigin
        if externalProvider == "jira" {
            guard let externalID,
                  let externalKey,
                  let externalStatusCategory,
                  let externalStatusName,
                  let externalSyncedAtMs else {
                throw TodoMappingError.invalidExternalMetadata
            }
            let startDay = try externalStartDay.map {
                do {
                    return try LocalDay(rawValue: $0)
                } catch {
                    throw TodoMappingError.invalidDay($0)
                }
            }
            let dueDay = try externalDueDay.map {
                do {
                    return try LocalDay(rawValue: $0)
                } catch {
                    throw TodoMappingError.invalidDay($0)
                }
            }
            origin = .jira(
                JiraTodoMetadata(
                    issueID: externalID,
                    issueKey: externalKey,
                    statusCategory: externalStatusCategory,
                    statusName: externalStatusName,
                    startDay: startDay,
                    dueDay: dueDay,
                    syncedAt: Date(unixMilliseconds: externalSyncedAtMs)
                )
            )
        } else {
            guard externalProvider == nil,
                  externalID == nil,
                  externalKey == nil,
                  externalStatusCategory == nil,
                  externalStatusName == nil,
                  externalStartDay == nil,
                  externalDueDay == nil,
                  externalSyncedAtMs == nil else {
                throw TodoMappingError.invalidExternalMetadata
            }
            if source.hasPrefix("carryover:"),
               let sourceID = UUID(
                uuidString: String(source.dropFirst("carryover:".count))
               ) {
                origin = .carryOver(
                    sourceID: TodoID(rawValue: sourceID)
                )
            } else {
                origin = .manual
            }
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
                origin: origin,
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

    func listCarryOverCandidates(
        from: LocalDay,
        to: LocalDay
    ) async throws -> [TodoItem] {
        try await writer.read { database in
            try TodoRecord.fetchAll(
                database,
                sql: """
                    SELECT source_task.*
                    FROM tasks AS source_task
                    WHERE source_task.task_day = ?
                      AND source_task.status = 'pending'
                      AND source_task.external_provider IS NULL
                      AND NOT EXISTS (
                          SELECT 1
                          FROM tasks AS carried
                          WHERE carried.task_day = ?
                            AND carried.source = 'carryover:' || source_task.id
                      )
                    ORDER BY
                        source_task.sort_order ASC,
                        source_task.created_at_ms ASC,
                        source_task.id ASC
                    """,
                arguments: [from.rawValue, to.rawValue]
            )
            .map { try $0.domain() }
        }
    }

    func insert(_ item: TodoItem) async throws {
        try await writer.write { database in
            if case let .jira(metadata) = item.origin {
                try database.execute(
                    sql: """
                        DELETE FROM jira_task_dismissals
                        WHERE task_day = ? AND issue_id = ?
                        """,
                    arguments: [item.day.rawValue, metadata.issueID]
                )
            }
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
            guard let record = try TodoRecord.fetchOne(
                database,
                key: id.storageValue
            ) else {
                return
            }
            if record.externalProvider == "jira",
               let issueID = record.externalID {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO jira_task_dismissals (
                            task_day,
                            issue_id
                        ) VALUES (?, ?)
                        """,
                    arguments: [record.taskDay, issueID]
                )
            }
            _ = try record.delete(database)
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
        let pending = try await listCarryOverCandidates(from: from, to: to)
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
                    WHERE task_day = ?
                      AND status = 'pending'
                      AND external_provider IS NULL
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
            let existingCarrySources = Set(
                try String.fetchAll(
                    database,
                    sql: """
                        SELECT source
                        FROM tasks
                        WHERE task_day = ? AND source LIKE 'carryover:%'
                        """,
                    arguments: [to.rawValue]
                )
            )

            let nextSortOrder = (
                try Int.fetchOne(
                    database,
                    sql: "SELECT MAX(sort_order) FROM tasks WHERE task_day = ?",
                    arguments: [to.rawValue]
                ) ?? -1
            ) + 1

            return try zip(requestedStorageIDs, newIDs)
                .filter { pair in
                    let (sourceID, _) = pair
                    return !existingCarrySources.contains(
                        "carryover:\(sourceID)"
                    )
                }
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
                        origin: .carryOver(sourceID: source.id),
                        createdAt: date,
                        updatedAt: date
                    )
                    try TodoRecord(
                        item: copy,
                        source: "carryover:\(sourceID)"
                    )
                    .insert(database)
                    return copy
                }
        }
    }

    func importJira(
        _ issues: [JiraIssueSnapshot],
        day: LocalDay,
        displayBaseURL: URL,
        newIDs: [TodoID],
        at date: Date
    ) async throws -> JiraTodoImportResult {
        guard issues.count == newIDs.count else {
            throw TodoRepositoryError.reorderMismatch
        }

        var seenIssueIDs = Set<String>()
        let uniquePairs = zip(issues, newIDs).filter {
            seenIssueIDs.insert($0.0.issueID).inserted
        }

        return try await writer.write { database in
            let dismissedIssueIDs = Set(
                try String.fetchAll(
                    database,
                    sql: """
                        SELECT issue_id
                        FROM jira_task_dismissals
                        WHERE task_day = ?
                        """,
                    arguments: [day.rawValue]
                )
            )
            let existing = try TodoRecord.fetchAll(
                database,
                sql: """
                    SELECT *
                    FROM tasks
                    WHERE task_day = ? AND external_provider = 'jira'
                    """,
                arguments: [day.rawValue]
            )
            let existingByExternalID = Dictionary(
                uniqueKeysWithValues: existing.compactMap {
                    record in
                    record.externalID.map { ($0, record) }
                }
            )
            var nextSortOrder = (
                try Int.fetchOne(
                    database,
                    sql: "SELECT MAX(sort_order) FROM tasks WHERE task_day = ?",
                    arguments: [day.rawValue]
                ) ?? -1
            ) + 1
            var importedCount = 0
            var refreshedCount = 0

            for (issue, newID) in uniquePairs {
                guard !dismissedIssueIDs.contains(issue.issueID) else {
                    continue
                }
                let issueURL = displayBaseURL
                    .appendingPathComponent("browse", isDirectory: true)
                    .appendingPathComponent(issue.issueKey)
                let metadata = JiraTodoMetadata(
                    issueID: issue.issueID,
                    issueKey: issue.issueKey,
                    statusCategory: issue.statusCategory,
                    statusName: issue.statusName,
                    startDay: issue.startDay,
                    dueDay: issue.dueDay,
                    syncedAt: date
                )
                let normalizedTitle = String(issue.summary.prefix(200))

                if var record = existingByExternalID[issue.issueID] {
                    record.title = normalizedTitle
                    record.relatedURL = issueURL.absoluteString
                    record.externalKey = issue.issueKey
                    record.externalStatusCategory = issue.statusCategory
                    record.externalStatusName = issue.statusName
                    record.externalStartDay = issue.startDay?.rawValue
                    record.externalDueDay = issue.dueDay?.rawValue
                    record.externalSyncedAtMs = date.unixMilliseconds
                    record.updatedAtMs = date.unixMilliseconds
                    try record.update(database)
                    refreshedCount += 1
                } else {
                    let item = try TodoItem(
                        id: newID,
                        title: normalizedTitle,
                        day: day,
                        status: .pending,
                        priority: .normal,
                        sortOrder: nextSortOrder,
                        relatedURL: issueURL,
                        origin: .jira(metadata),
                        createdAt: date,
                        updatedAt: date
                    )
                    try TodoRecord(item: item).insert(database)
                    nextSortOrder += 1
                    importedCount += 1
                }
            }
            return JiraTodoImportResult(
                importedCount: importedCount,
                refreshedCount: refreshedCount
            )
        }
    }
}

extension GRDBTodoRepository: TodoRepository {}
