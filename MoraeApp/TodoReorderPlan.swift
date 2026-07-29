import MoraeCore

struct TodoReorderPlan: Equatable, Sendable {
    let orderedIDs: [TodoID]

    static func moving(
        _ sourceID: TodoID,
        before targetID: TodoID,
        in orderedIDs: [TodoID]
    ) -> TodoReorderPlan? {
        guard sourceID != targetID,
              let sourceIndex = orderedIDs.firstIndex(of: sourceID),
              let targetIndex = orderedIDs.firstIndex(of: targetID) else {
            return nil
        }

        var result = orderedIDs
        let moved = result.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex
            ? targetIndex - 1
            : targetIndex
        result.insert(moved, at: insertionIndex)

        guard result != orderedIDs else {
            return nil
        }
        return TodoReorderPlan(orderedIDs: result)
    }
}
