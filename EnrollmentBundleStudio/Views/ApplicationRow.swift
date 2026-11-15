import SwiftUI

struct ApplicationRow: View {
    let application: ApplicationItem
    let isRequired: Bool
    let requiredByGroup: Bool
    let assets: [String: Data]
    @Binding var isEnabled: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconSourceImage(icon: application.icon, applicationPath: application.applicationPath, assets: assets, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(application.displayName.isEmpty ? "Untitled application" : application.displayName)
                        .font(.body.weight(.medium))
                    badge(isRequired ? (requiredByGroup ? "Required by group" : "Required") : "Optional", highlighted: isRequired)
                    if !application.execution.isVisible {
                        badge("Hidden", highlighted: false)
                    }
                    if application.installStrategy == .bundledInstaller {
                        badge(application.installer.map { "Package: \($0.originalFilename)" } ?? "No package", highlighted: application.installer != nil)
                    }
                }
                Text(application.applicationPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(application.installStrategy.title)
                    .font(.caption)
                Text("Timeout \(DurationFormatter.format(seconds: application.execution.timeoutSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Enabled", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enable \(application.displayName)")
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit application")
            .accessibilityLabel("Edit \(application.displayName)")
        }
        .opacity(application.isEnabled ? 1 : 0.55)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityElement(children: .contain)
    }

    private func badge(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(highlighted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15)))
    }
}
