import SwiftUI

extension ValidationArea {
    var sidebarSection: SidebarSection {
        switch self {
        case .project: return .overview
        case .branding: return .branding
        case .applications: return .applications
        case .scripts: return .scripts
        case .execution: return .execution
        case .dock: return .dock
        case .environment: return .settings
        }
    }
}

/// Project-wide checks. Errors block exporting and building.
struct ValidationView: View {
    let report: ValidationReport
    @Binding var selection: SidebarSection?
    @State private var filter: ValidationSeverity?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if report.issues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("No issues found").font(.title3.bold())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleSeverities) { severity in
                        let issues = report.issues.filter { $0.severity == severity }
                        if !issues.isEmpty {
                            Section("\(severity.pluralTitle) (\(issues.count))") {
                                ForEach(issues) { issue in
                                    ValidationIssueRow(issue: issue) {
                                        selection = issue.area.sidebarSection
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var visibleSeverities: [ValidationSeverity] {
        if let filter {
            return [filter]
        }
        return [.error, .warning, .information]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                countLabel(.error, report.errorCount, .red)
                countLabel(.warning, report.warningCount, .orange)
                countLabel(.information, report.informationCount, .secondary)
                Spacer()
                Picker("Show", selection: $filter) {
                    Text("All").tag(ValidationSeverity?.none)
                    Text("Errors").tag(Optional(ValidationSeverity.error))
                    Text("Warnings").tag(Optional(ValidationSeverity.warning))
                    Text("Information").tag(Optional(ValidationSeverity.information))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            if report.blocksBuild {
                Label("Errors block exporting and building. Fix them first.", systemImage: "hand.raised.fill")
                    .foregroundStyle(.red)
            } else {
                Label("No blocking errors. Warnings are worth reviewing before deployment.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
    }

    private func countLabel(_ severity: ValidationSeverity, _ count: Int, _ color: Color) -> some View {
        Label("\(count) \(severity.pluralTitle)", systemImage: severity.symbolName)
            .foregroundStyle(color)
            .font(.headline)
    }
}

private struct ValidationIssueRow: View {
    let issue: ValidationIssue
    let onShow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity.symbolName)
                .foregroundStyle(tint)
                .accessibilityLabel(issue.severity.title)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.component)
                    .font(.body.weight(.semibold))
                Text(issue.message)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issue.remediation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Show", action: onShow)
                .accessibilityLabel("Show \(issue.component)")
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        switch issue.severity {
        case .error: return .red
        case .warning: return .orange
        case .information: return .secondary
        }
    }
}
