import Foundation

/// Minimal task state used by completion and unlock logic.
struct TaskStateInput: Equatable {
    var isRequired: Bool
    var allowSkip: Bool
    var status: TaskStatus
}

enum CompletionOutcome: String, Equatable {
    case inProgress
    case success
    case successWithWarnings
    case failed
}

/// Decides when the completion button unlocks and which final message applies.
/// The generated Bash framework implements the same rules (Phase 3).
enum CompletionEvaluator {
    /// True when every required task is in an acceptable terminal state.
    static func canUnlock(_ tasks: [TaskStateInput]) -> Bool {
        tasks.filter { $0.isRequired }.allSatisfy { $0.status.isAcceptableForRequiredTask(allowSkip: $0.allowSkip) }
    }

    static func outcome(_ tasks: [TaskStateInput]) -> CompletionOutcome {
        let requiredFailed = tasks.contains { task in
            task.isRequired && (task.status.isFailure || (task.status == .skipped && !task.allowSkip))
        }
        if requiredFailed {
            return .failed
        }
        if tasks.contains(where: { !$0.status.isTerminal }) {
            return .inProgress
        }
        if tasks.contains(where: { $0.status.isFailure || $0.status == .completeWithWarnings }) {
            return .successWithWarnings
        }
        return .success
    }
}

/// Combines member statuses into one status for a summary row.
enum StatusAggregator {
    static func aggregate(_ statuses: [TaskStatus]) -> TaskStatus {
        guard !statuses.isEmpty else { return .complete }
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.timedOut) { return .timedOut }
        if statuses.contains(.running) { return .running }
        let unfinished = statuses.contains(.pending) || statuses.contains(.waiting)
        if unfinished {
            let started = statuses.contains { $0.isTerminal }
            if started { return .running }
            return statuses.contains(.waiting) ? .waiting : .pending
        }
        if statuses.contains(.completeWithWarnings) { return .completeWithWarnings }
        if statuses.allSatisfy({ $0 == .skipped }) { return .skipped }
        return .complete
    }
}
