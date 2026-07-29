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
