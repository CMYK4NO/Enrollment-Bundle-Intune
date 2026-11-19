import Foundation

enum ValidationSeverity: Int, Comparable, CaseIterable, Identifiable {
    case information = 0
    case warning = 1
    case error = 2

    var id: Int { rawValue }

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .information: return "Information"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var pluralTitle: String {
        switch self {
        case .information: return "Information"
        case .warning: return "Warnings"
        case .error: return "Errors"
        }
    }

    var symbolName: String {
        switch self {
        case .information: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// Part of the project an issue belongs to, used for navigation.
enum ValidationArea: String, CaseIterable {
    case project
    case branding
    case applications
    case scripts
    case execution
    case dock
    case environment
}

struct ValidationIssue: Identifiable, Equatable {
    let severity: ValidationSeverity
    let area: ValidationArea
    /// The affected component, for example "Package identifier" or "Script CheckDefender".
    let component: String
    let message: String
    let remediation: String

    var id: String { "\(area.rawValue)|\(component)|\(message)" }
}

struct ValidationReport: Equatable {
    let issues: [ValidationIssue]

    init(issues: [ValidationIssue]) {
        var seen = Set<String>()
        var unique: [ValidationIssue] = []
        for issue in issues where seen.insert(issue.id).inserted {
            unique.append(issue)
        }
        self.issues = unique.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.area != rhs.area {
                let order = ValidationArea.allCases
                return (order.firstIndex(of: lhs.area) ?? 0) < (order.firstIndex(of: rhs.area) ?? 0)
            }
            return lhs.component.localizedStandardCompare(rhs.component) == .orderedAscending
        }
    }

    func count(_ severity: ValidationSeverity) -> Int {
        issues.filter { $0.severity == severity }.count
    }

    var errorCount: Int { count(.error) }
    var warningCount: Int { count(.warning) }
    var informationCount: Int { count(.information) }

    /// Errors block exporting and building.
    var blocksBuild: Bool { errorCount > 0 }
}
