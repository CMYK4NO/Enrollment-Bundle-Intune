import Foundation

/// Canned task-state scenarios for the static preview.
enum PreviewScenario: String, CaseIterable, Identifiable {
    case initial
    case inProgress
    case allComplete
    case completeWithWarnings
    case requiredFailure
    case requiredTimeout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .initial: return "Just started"
        case .inProgress: return "In progress"
        case .allComplete: return "All complete"
        case .completeWithWarnings: return "Optional item failed"
        case .requiredFailure: return "Required item failed"
        case .requiredTimeout: return "Required item timed out"
        }
    }
}

/// One row in the preview list, or one hidden background task.
struct PreviewListItem: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: IconSource
    let applicationPath: String
    let isRequired: Bool
    let allowSkip: Bool
    let isVisible: Bool
    let isSummary: Bool
    /// Task identifiers represented by this row (more than one for a group summary).
    let memberIDs: [String]
    var status: TaskStatus
    var statusText: String

    var stateInput: TaskStateInput {
        TaskStateInput(isRequired: isRequired, allowSkip: allowSkip, status: status)
    }
}

/// Everything the static preview needs to draw one frame.
struct PreviewState: Equatable {
    var displayItems: [PreviewListItem]
    /// Every task, including hidden ones, used for unlock and outcome decisions.
    var evaluationItems: [PreviewListItem]
    var isButtonEnabled: Bool
    var isButtonLockActive: Bool
    var outcome: CompletionOutcome
    var finishedCount: Int
    var totalCount: Int

    var progress: Double {
        totalCount == 0 ? 1 : Double(finishedCount) / Double(totalCount)
    }

    var hiddenCount: Int {
        evaluationItems.filter { !$0.isVisible }.count
    }
}

private struct PreviewMember {
    var item: PreviewListItem
    let groupID: UUID?
    let messages: TaskMessages
    let isFinalValidation: Bool
}

/// Builds preview state from a project without touching the file system or running anything.
enum PreviewBuilder {
    static func makeState(project: EnrollmentProject, scenario: PreviewScenario, overrides: [String: TaskStatus]) -> PreviewState {
        var members = collectMembers(project)

        let regularIndices = members.indices.filter { !members[$0].isFinalValidation }
        let statuses = scenarioStatuses(scenario, requiredFlags: regularIndices.map { members[$0].item.isRequired })
        for (offset, index) in regularIndices.enumerated() {
            members[index].item.status = overrides[members[index].item.id] ?? statuses[offset]
        }

        // Final validation mirrors its runtime dependency on every other task.
        let regularInputs = regularIndices.map { members[$0].item.stateInput }
        let prerequisitesMet = regularInputs.allSatisfy { $0.status.isTerminal } && CompletionEvaluator.canUnlock(regularInputs)
        for index in members.indices where members[index].isFinalValidation {
            members[index].item.status = overrides[members[index].item.id] ?? (prerequisitesMet ? .complete : .pending)
        }

        for index in members.indices {
            members[index].item.statusText = statusText(members[index].item.status, messages: members[index].messages)
        }

        let evaluation = members.map { $0.item }
        let inputs = evaluation.map { $0.stateInput }
        let lockActive = project.settings.lockCompletionButtonUntilRequiredComplete
        return PreviewState(
            displayItems: displayItems(project: project, members: members),
            evaluationItems: evaluation,
            isButtonEnabled: !lockActive || CompletionEvaluator.canUnlock(inputs),
            isButtonLockActive: lockActive,
            outcome: CompletionEvaluator.outcome(inputs),
            finishedCount: inputs.filter { $0.status.isTerminal }.count,
            totalCount: inputs.count
        )
    }

    static func scenarioStatuses(_ scenario: PreviewScenario, requiredFlags: [Bool]) -> [TaskStatus] {
        let count = requiredFlags.count
        switch scenario {
        case .initial:
            return Array(repeating: .pending, count: count)
        case .inProgress:
            let runningIndex = count / 2
            return (0..<count).map { index in
                if index < runningIndex { return .complete }
                return index == runningIndex ? .running : .waiting
            }
        case .allComplete:
            return Array(repeating: .complete, count: count)
        case .completeWithWarnings:
            var statuses = Array(repeating: TaskStatus.complete, count: count)
            if let optionalIndex = requiredFlags.firstIndex(of: false) {
                statuses[optionalIndex] = .failed
            } else if count > 0 {
                statuses[count - 1] = .completeWithWarnings
            }
            return statuses
        case .requiredFailure, .requiredTimeout:
            var statuses = Array(repeating: TaskStatus.complete, count: count)
            if let requiredIndex = requiredFlags.firstIndex(of: true) {
                statuses[requiredIndex] = scenario == .requiredFailure ? .failed : .timedOut
            }
            return statuses
        }
    }

    static func statusText(_ status: TaskStatus, messages: TaskMessages) -> String {
        switch status {
        case .pending, .waiting: return messages.waiting
        case .running: return messages.progress
        case .complete: return messages.success
        case .completeWithWarnings: return messages.warning
        case .skipped: return "Skipped"
        case .failed: return messages.failure
        case .timedOut: return "Timed out"
        }
    }

    private static func collectMembers(_ project: EnrollmentProject) -> [PreviewMember] {
        var members: [PreviewMember] = []
        // A script an application runs as part of its own task has no row of its own.
        let foldedScripts = TaskPlanner.foldedScripts(in: project)
        for group in project.applicationGroups {
            for application in group.applications where application.isEnabled {
                let item = PreviewListItem(
                    id: application.taskIdentifier,
                    title: application.displayName,
                    icon: application.icon,
                    applicationPath: application.applicationPath,
                    isRequired: group.isRequired || application.execution.isRequired,
                    allowSkip: application.execution.allowSkip,
                    isVisible: application.execution.isVisible && group.displayBehavior != .hidden,
                    isSummary: false,
                    memberIDs: [application.taskIdentifier],
                    status: .pending,
                    statusText: ""
                )
                members.append(PreviewMember(item: item, groupID: group.id, messages: application.execution.messages, isFinalValidation: false))
            }
        }
        for script in project.scripts where foldedScripts[script.taskIdentifier] == nil {
            let item = PreviewListItem(
                id: script.taskIdentifier,
                title: script.displayName,
                icon: IconSource(kind: .sfSymbol, value: "terminal"),
                applicationPath: "",
                isRequired: script.execution.isRequired,
                allowSkip: script.execution.allowSkip,
                isVisible: script.execution.isVisible,
                isSummary: false,
                memberIDs: [script.taskIdentifier],
                status: .pending,
                statusText: ""
            )
            members.append(PreviewMember(item: item, groupID: nil, messages: script.execution.messages, isFinalValidation: false))
        }
        for task in project.systemTasks {
            let item = PreviewListItem(
                id: task.taskIdentifier,
                title: task.displayName,
                icon: task.icon,
                applicationPath: "",
                isRequired: task.execution.isRequired,
                allowSkip: task.execution.allowSkip,
                isVisible: task.execution.isVisible,
                isSummary: false,
                memberIDs: [task.taskIdentifier],
                status: .pending,
                statusText: ""
            )
            members.append(PreviewMember(item: item, groupID: nil, messages: task.execution.messages, isFinalValidation: task.type == .finalValidation))
        }
        return members
    }

    private static func displayItems(project: EnrollmentProject, members: [PreviewMember]) -> [PreviewListItem] {
        var result: [PreviewListItem] = []
        for group in project.applicationGroups {
            let groupItems = members.filter { $0.groupID == group.id }.map { $0.item }
            guard !groupItems.isEmpty else { continue }
            switch group.displayBehavior {
            case .individualItems:
                result.append(contentsOf: groupItems.filter { $0.isVisible })
            case .singleSummaryItem:
                let status = StatusAggregator.aggregate(groupItems.map { $0.status })
                let finished = groupItems.filter { $0.status.isTerminal }.count
                result.append(PreviewListItem(
                    id: "group.\(group.id.uuidString)",
                    title: group.name,
                    icon: IconSource(kind: .sfSymbol, value: group.symbolName),
                    applicationPath: "",
                    isRequired: groupItems.contains { $0.isRequired },
                    allowSkip: false,
                    isVisible: true,
                    isSummary: true,
                    memberIDs: groupItems.map { $0.id },
                    status: status,
                    statusText: "\(finished) of \(groupItems.count) complete"
                ))
            case .hidden:
                continue
            }
        }
        result.append(contentsOf: members.filter { $0.groupID == nil }.map { $0.item }.filter { $0.isVisible })
        return sortedByExecutionOrder(result, project: project)
    }

    /// The list follows the run order from Execution. A group summary sits where its first member runs.
    /// Rows the plan does not know keep their relative position at the end.
    private static func sortedByExecutionOrder(_ items: [PreviewListItem], project: EnrollmentProject) -> [PreviewListItem] {
        let orderedIDs = DependencyGraph.analyze(TaskPlanner.plan(project)).orderedTaskIDs
        var rank: [String: Int] = [:]
        for (index, id) in orderedIDs.enumerated() where rank[id] == nil { rank[id] = index }
        func position(_ item: PreviewListItem) -> Int {
            item.memberIDs.compactMap { rank[$0] }.min() ?? Int.max
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                let left = position(lhs.element), right = position(rhs.element)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { $0.element }
    }
}
