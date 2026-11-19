import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    let project: EnrollmentProject
    var validationErrorCount = 0

    var body: some View {
        List {
            Section("Project") {
                row(.overview)
                row(.branding)
                row(.scripts, badge: project.scripts.count)
                row(.applications, badge: project.allApplications.filter { $0.isEnabled }.count)
                row(.execution)
                row(.dock)
            }
            Section("Review") {
                row(.preview)
                row(.validation, badge: validationErrorCount)
            }
            Section("Build") {
                row(.packageBuilder)
                row(.buildHistory)
            }
        }
        .listStyle(.sidebar)
    }

    private func helpText(_ section: SidebarSection, badge: Int) -> String {
        guard section.isAvailable else { return "\(section.title) is planned for Phase \(section.availablePhase)" }
        if section == .validation && badge > 0 { return "\(badge) validation error(s) block building" }
        return section.title
    }

    /// Each row is a button that sets the selection directly, the same mechanism the keyboard shortcuts
    /// use. List(selection:) and NavigationLink(value:) are not used: on macOS 26 their selection
    /// handling did not reliably update the selected section.
    @ViewBuilder
    private func row(_ section: SidebarSection, badge: Int = 0) -> some View {
        let isSelected = selection == section
        Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.symbolName)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.white : (section.isAvailable ? Color.accentColor : Color.secondary))
                Text(section.title)
                    .foregroundStyle(isSelected ? Color.white : (section.isAvailable ? Color.primary : Color.secondary))
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .help(helpText(section, badge: badge))
        .accessibilityLabel(badge > 0 ? "\(section.title), \(badge)" : section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
