import SwiftUI

/// Status glyph used in the preview list.
struct StatusIndicator: View {
    let status: TaskStatus

    var body: some View {
        Group {
            if status == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.symbolName)
                    .foregroundStyle(tint)
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(status.title)
    }

    private var tint: Color {
        switch status {
        case .complete: return .green
        case .completeWithWarnings: return .orange
        case .failed, .timedOut: return .red
        case .pending, .waiting, .running, .skipped: return .secondary
        }
    }
}
