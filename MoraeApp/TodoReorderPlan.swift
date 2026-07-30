import MoraeCore

struct TodoReorderPlan: Equatable, Sendable {
    let orderedIDs: [TodoID]

    static func moving(
        _ sourceID: TodoID,
        before targetID: TodoID?,
        in orderedIDs: [TodoID]
    ) -> TodoReorderPlan? {
        guard sourceID != targetID,
              let sourceIndex = orderedIDs.firstIndex(of: sourceID) else {
            return nil
        }

        var result = orderedIDs
        let moved = result.remove(at: sourceIndex)
        if let targetID {
            guard let targetIndex = result.firstIndex(of: targetID) else {
                return nil
            }
            result.insert(moved, at: targetIndex)
        } else {
            result.append(moved)
        }

        guard result != orderedIDs else {
            return nil
        }
        return TodoReorderPlan(orderedIDs: result)
    }
}
