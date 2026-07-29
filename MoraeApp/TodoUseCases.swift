import Foundation
import MoraeCore

struct CarryOverPendingTodos: Sendable {
    let repository: any TodoRepository
    let clock: any Clock
    let uuidGenerator: any UUIDGenerating

    func execute(
        from: LocalDay,
        to: LocalDay,
        selectedIDs: [TodoID]
    ) async throws -> [TodoItem] {
        try await repository.carryOverPending(
            from: from,
            to: to,
            selectedIDs: selectedIDs,
            newIDs: selectedIDs.map { _ in
                TodoID(rawValue: uuidGenerator.next())
            },
            at: clock.now()
        )
    }
}

struct LocalTaskSummary: Equatable, Sendable {
    let yesterdayCompleted: [TodoItem]
    let todayPending: [TodoItem]
    let todayCompletedCount: Int
    let todayEstimatedMinutes: Int
    let mostImportantTodoID: TodoID?
}

struct BuildLocalTaskSummary: Sendable {
    let repository: any TodoRepository

    func execute(
        today: LocalDay,
        calendar: Calendar
    ) async throws -> LocalTaskSummary {
        let yesterday = try previousDay(of: today, calendar: calendar)
        async let yesterdayCompletedRequest = repository.listCompleted(day: yesterday)
        async let todayRequest = repository.list(day: today)

        let yesterdayCompleted = try await yesterdayCompletedRequest
        let todayItems = try await todayRequest
        let todayPending = todayItems
            .filter { $0.status == .pending }
            .sorted(by: TodoItem.summaryOrder)

        return LocalTaskSummary(
            yesterdayCompleted: yesterdayCompleted.sorted(by: TodoItem.summaryOrder),
            todayPending: todayPending,
            todayCompletedCount: todayItems.count(where: { $0.status == .completed }),
            todayEstimatedMinutes: todayPending.compactMap(\.estimatedMinutes).reduce(0, +),
            mostImportantTodoID: todayPending
                .first(where: { $0.priority == .important })?
                .id
        )
    }

    private func previousDay(
        of day: LocalDay,
        calendar: Calendar
    ) throws -> LocalDay {
        let parts = day.rawValue.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12

        guard let date = calendar.date(from: components),
              let previousDate = calendar.date(byAdding: .day, value: -1, to: date) else {
            throw CoreValueError.invalidLocalDay(day.rawValue)
        }
        return LocalDay(date: previousDate, calendar: calendar)
    }
}

private extension TodoItem {
    static func summaryOrder(lhs: TodoItem, rhs: TodoItem) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority == .important
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id.storageValue < rhs.id.storageValue
    }
}
