import SwiftUI

enum FieldIssueSeverity {
    case error
    case warning

    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        }
    }

    var symbolName: String {
        switch self {
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

/// Inline issue message shown under a field.
struct FieldIssueLabel: View {
    let message: String
    var severity: FieldIssueSeverity = .error

    var body: some View {
        Label(message, systemImage: severity.symbolName)
            .font(.caption)
            .foregroundStyle(severity.color)
    }
}

/// Text field with an inline validation message.
struct ValidatedTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    let issue: String?
    var severity: FieldIssueSeverity = .error

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $text, prompt: prompt.isEmpty ? nil : Text(prompt))
            if let issue {
                FieldIssueLabel(message: issue, severity: severity)
            }
        }
    }
}
