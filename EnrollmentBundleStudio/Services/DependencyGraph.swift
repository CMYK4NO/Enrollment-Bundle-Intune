import Foundation

enum DependencyIssue: Equatable {
    case emptyIdentifier(displayName: String)
    case duplicateIdentifier(String)
    case selfDependency(String)
    case missingDependency(task: String, dependency: String)
    case disabledDependency(task: String, dependency: String)
    case cycle([String])
    /// The dependency is scheduled after the task by execution order.
    case orderConflict(task: String, dependency: String)
    /// Two tasks in the same parallel group depend on each other, so they cannot run together.
    case parallelGroupDependency(task: String, dependency: String, group: String)

    var isCritical: Bool {
        switch self {
        case .parallelGroupDependency: return false
        case .emptyIdentifier, .duplicateIdentifier, .selfDependency, .missingDependency,
             .disabledDependency, .cycle, .orderConflict:
            return true
        }
    }
}

struct DependencyAnalysis: Equatable {
    let issues: [DependencyIssue]
    /// Enabled tasks in resolved run order. Tasks caught in a cycle are appended last.
    let orderedTaskIDs: [String]
    /// Consecutive tasks that may run together (same parallel group, no dependency between them).
    let batches: [[String]]
    /// Every task identifier that is part of a dependency cycle.
    let tasksInCycles: Set<String>

    var hasCriticalIssues: Bool { issues.contains { $0.isCritical } }

    /// Enabled tasks that can never start because a dependency is missing, disabled, cyclic or itself blocked.
    let blockedTaskIDs: Set<String>
}

enum DependencyGraph {
    static func analyze(_ tasks: [PlannedTask]) -> DependencyAnalysis {
        var issues: [DependencyIssue] = []

        var counts: [String: Int] = [:]
        for task in tasks {
            if task.taskIdentifier.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(.emptyIdentifier(displayName: task.displayName))
            } else {
                counts[task.taskIdentifier, default: 0] += 1
            }
        }
        for (identifier, count) in counts.sorted(by: { $0.key < $1.key }) where count > 1 {
            issues.append(.duplicateIdentifier(identifier))
        }

        var byID: [String: PlannedTask] = [:]
        for task in tasks where byID[task.taskIdentifier] == nil {
            byID[task.taskIdentifier] = task
        }
        var seenEnabled = Set<String>()
        let enabled = tasks.filter { task in
            task.isEnabled && !task.taskIdentifier.isEmpty && seenEnabled.insert(task.taskIdentifier).inserted
        }
        let enabledIDs = Set(enabled.map { $0.taskIdentifier })

        // Edges among enabled tasks only; missing and disabled dependencies are reported instead.
        var edges: [String: [String]] = [:]
        var directlyBlocked = Set<String>()
        for task in enabled {
            var valid: [String] = []
            for dependency in task.allDependencies {
                if dependency == task.taskIdentifier {
                    issues.append(.selfDependency(task.taskIdentifier))
                    directlyBlocked.insert(task.taskIdentifier)
                } else if let target = byID[dependency] {
                    if target.isEnabled {
                        valid.append(dependency)
                    } else {
                        issues.append(.disabledDependency(task: task.taskIdentifier, dependency: dependency))
                        directlyBlocked.insert(task.taskIdentifier)
                    }
                } else {
                    issues.append(.missingDependency(task: task.taskIdentifier, dependency: dependency))
                    directlyBlocked.insert(task.taskIdentifier)
                }
            }
            edges[task.taskIdentifier] = valid
        }

        for task in enabled {
            for dependency in task.execution.dependencies where enabledIDs.contains(dependency) && dependency != task.taskIdentifier {
                guard let target = byID[dependency] else { continue }
                if target.execution.executionOrder > task.execution.executionOrder {
                    issues.append(.orderConflict(task: task.taskIdentifier, dependency: dependency))
                }
                let group = task.execution.parallelGroup
                if !group.isEmpty && group == target.execution.parallelGroup {
                    issues.append(.parallelGroupDependency(task: task.taskIdentifier, dependency: dependency, group: group))
                }
            }
        }

        let cycles = findCycles(nodes: enabled.map { $0.taskIdentifier }, edges: edges)
        issues.append(contentsOf: cycles.map { DependencyIssue.cycle($0) })
        let inCycles = Set(cycles.flatMap { $0 })

        let blocked = propagateBlocked(seed: directlyBlocked.union(inCycles), nodes: enabled.map { $0.taskIdentifier }, edges: edges)
        let ordered = topologicalOrder(enabled, edges: edges)
        let batches = makeBatches(ordered: ordered, byID: byID, edges: edges)

        return DependencyAnalysis(issues: issues, orderedTaskIDs: ordered, batches: batches,
                                  tasksInCycles: inCycles, blockedTaskIDs: blocked)
    }

    /// Depth-first search that reports each distinct cycle once, rotated to start at its smallest identifier.
    static func findCycles(nodes: [String], edges: [String: [String]]) -> [[String]] {
        enum Mark { case visiting, done }
        var marks: [String: Mark] = [:]
        var stack: [String] = []
        var found: [[String]] = []
        var seen = Set<String>()

        func visit(_ node: String) {
            marks[node] = .visiting
            stack.append(node)
            for next in edges[node] ?? [] {
                switch marks[next] {
                case .visiting?:
                    if let start = stack.firstIndex(of: next) {
                        let cycle = Array(stack[start...])
                        let normalized = normalize(cycle)
                        let key = normalized.joined(separator: ">")
                        if seen.insert(key).inserted {
                            found.append(normalized)
                        }
                    }
                case .done?:
                    continue
                case nil:
                    visit(next)
                }
            }
            stack.removeLast()
            marks[node] = .done
        }

        for node in nodes where marks[node] == nil {
            visit(node)
        }
        return found
    }

    private static func normalize(_ cycle: [String]) -> [String] {
        guard let minimum = cycle.min(), let index = cycle.firstIndex(of: minimum) else { return cycle }
        return Array(cycle[index...] + cycle[..<index])
    }

    /// A task is blocked when it, or anything it depends on (transitively), can never complete.
    private static func propagateBlocked(seed: Set<String>, nodes: [String], edges: [String: [String]]) -> Set<String> {
        var blocked = seed
        var changed = true
        while changed {
            changed = false
            for node in nodes where !blocked.contains(node) {
                if (edges[node] ?? []).contains(where: { blocked.contains($0) }) {
                    blocked.insert(node)
                    changed = true
                }
            }
        }
        return blocked
    }

    /// Stable Kahn ordering by execution order, then original position.
    static func topologicalOrder(_ tasks: [PlannedTask], edges: [String: [String]]) -> [String] {
        // Duplicate identifiers are reported elsewhere; keep the first occurrence here instead of trapping.
        let position = Dictionary(tasks.enumerated().map { ($0.element.taskIdentifier, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(tasks.map { ($0.taskIdentifier, $0.execution.executionOrder) }, uniquingKeysWith: { first, _ in first })
        var remaining: [String: Set<String>] = [:]
        for task in tasks where remaining[task.taskIdentifier] == nil {
            remaining[task.taskIdentifier] = Set((edges[task.taskIdentifier] ?? []).filter { position[$0] != nil })
        }

        func priority(_ id: String) -> (Int, Int) {
            (order[id] ?? 0, position[id] ?? 0)
        }

        var result: [String] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { $0.value.isEmpty }.map { $0.key }
            guard let next = ready.min(by: { priority($0) < priority($1) }) else {
                // Cycle: append the rest in priority order so the list stays complete.
                result.append(contentsOf: remaining.keys.sorted { priority($0) < priority($1) })
                break
            }
            result.append(next)
            remaining.removeValue(forKey: next)
            for key in Array(remaining.keys) {
                remaining[key]?.remove(next)
            }
        }
        return result
    }

    private static func makeBatches(ordered: [String], byID: [String: PlannedTask], edges: [String: [String]]) -> [[String]] {
        var batches: [[String]] = []
        var currentGroup = ""
        for id in ordered {
            let group = byID[id]?.execution.parallelGroup ?? ""
            if !group.isEmpty, group == currentGroup, var last = batches.last,
               !last.contains(where: { (edges[id] ?? []).contains($0) || (edges[$0] ?? []).contains(id) }) {
                last.append(id)
                batches[batches.count - 1] = last
            } else {
                batches.append([id])
                currentGroup = group
            }
        }
        return batches
    }
}
