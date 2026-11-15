import Foundation

/// Lifecycle state of an enrollment task. Shared by the preview, simulation and generated framework.
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case waiting
    case running
    case complete
    case completeWithWarnings
    case skipped
    case failed
    case timedOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .complete: return "Complete"
        case .completeWithWarnings: return "Complete with warnings"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        case .timedOut: return "Timed out"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .complete, .completeWithWarnings, .skipped, .failed, .timedOut: return true
        case .pending, .waiting, .running: return false
        }
    }

    var isFailure: Bool {
        self == .failed || self == .timedOut
    }

    /// Whether this state lets a required task count toward unlocking the completion button.
    func isAcceptableForRequiredTask(allowSkip: Bool) -> Bool {
        switch self {
        case .complete, .completeWithWarnings: return true
        case .skipped: return allowSkip
        case .pending, .waiting, .running, .failed, .timedOut: return false
        }
    }

    var symbolName: String {
        switch self {
        case .pending: return "circle.dotted"
        case .waiting: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .complete: return "checkmark.circle.fill"
        case .completeWithWarnings: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle"
        case .failed: return "xmark.circle.fill"
        case .timedOut: return "exclamationmark.octagon.fill"
        }
    }
}
