import Foundation

enum TaskMoveDirection {
    case up
    case down
}

/// Moves one task up or down in the resolved run order.
///
/// The run order is the dependency-respecting sequence shown on the Execution page. A task cannot run before
/// something it depends on, so a move never separates a task from its dependencies: moving a task up also moves
/// the rows directly above it that it depends on, and moving a task down also moves the rows directly below it
/// that depend on it. The group moves together past the one row that is not related to it.
enum TaskReordering {
    /// The new run order after moving `identifier`, or nil when it cannot move (at an edge, not in the order,
    /// or the plan has dependency cycles or duplicate identifiers, where an order is not well defined).
    static func moved(
        in plan: [PlannedTask],
        analysis: DependencyAnalysis,
        identifier: String,
        direction: TaskMoveDirection
    ) -> [String]? {
        guard analysis.tasksInCycles.isEmpty else { return nil }
        let unusable = analysis.issues.contains { issue in
            switch issue {
            case .duplicateIdentifier, .emptyIdentifier: return true
            default: return false
            }
        }
        guard !unusable else { return nil }
        var dependencies: [String: Set<String>] = [:]
        for task in plan where task.isEnabled {
            dependencies[task.taskIdentifier] = Set(task.allDependencies)
        }
        return moved(analysis.orderedTaskIDs, identifier, direction, dependencies: dependencies)
    }

    /// Pure ordering step. `dependencies[id]` holds the identifiers `id` waits for.
    static func moved(
        _ sequence: [String],
        _ identifier: String,
        _ direction: TaskMoveDirection,
        dependencies: [String: Set<String>]
    ) -> [String]? {
        guard let index = sequence.firstIndex(of: identifier) else { return nil }
        var result = sequence
        switch direction {
        case .up:
            var start = index
            var members: Set<String> = [identifier]
            while start > 0 {
                let above = sequence[start - 1]
                let isNeeded = members.contains { (dependencies[$0] ?? []).contains(above) }
                if !isNeeded { break }
                members.insert(above)
                start -= 1
            }
            guard start > 0 else { return nil }
            let block = Array(sequence[start...index])
            let passed = sequence[start - 1]
            result.removeSubrange((start - 1)...index)
            result.insert(contentsOf: block + [passed], at: start - 1)
        case .down:
            var end = index
            var members: Set<String> = [identifier]
            while end < sequence.count - 1 {
                let below = sequence[end + 1]
                let dependsOnGroup = !(dependencies[below] ?? []).isDisjoint(with: members)
                if !dependsOnGroup { break }
                members.insert(below)
                end += 1
            }
            guard end < sequence.count - 1 else { return nil }
            let block = Array(sequence[index...end])
            let passed = sequence[end + 1]
            result.removeSubrange(index...(end + 1))
            result.insert(contentsOf: [passed] + block, at: index)
        }
        return result
    }
}

extension EnrollmentProject {
    /// Moves a task up or down in the run order and rewrites the execution orders so the order shown on the
    /// Execution page is exactly the new one. Returns false when the task cannot move.
    ///
    /// Orders are renumbered in steps (10 when there is room) from 100 in the new sequence, so every task keeps
    /// its place relative to the others and every dependency has a lower order than the task that waits for it.
    /// Final validation keeps an order of at least its current one, so it stays after tasks added later.
    @discardableResult
    mutating func moveTask(_ identifier: String, _ direction: TaskMoveDirection) -> Bool {
        let plan = TaskPlanner.plan(self)
        let analysis = DependencyGraph.analyze(plan)
        guard let sequence = TaskReordering.moved(in: plan, analysis: analysis, identifier: identifier, direction: direction) else {
            return false
        }
        let finalValidationIDs = Set(plan.filter { $0.type == .finalValidation }.map { $0.taskIdentifier })
        let step = max(1, min(10, 380 / max(sequence.count, 1)))
        var next = 100
        for id in sequence {
            guard var options = executionOptions(forTask: id) else { continue }
            var assigned = next
            if finalValidationIDs.contains(id) {
                assigned = max(assigned, options.executionOrder)
            }
            options.executionOrder = assigned
            setExecutionOptions(options, forTask: id)
            next = assigned + step
        }
        return true
    }
}
