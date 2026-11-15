import SwiftUI

/// Shown for sections whose editor ships in a later implementation phase.
struct PhasePendingView: View {
    let section: SidebarSection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(section.title)
                .font(.title2.bold())
            Text(section.pendingDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Text("Planned for Phase \(section.availablePhase)")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
