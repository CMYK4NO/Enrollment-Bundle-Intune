import SwiftUI

/// Shows what a configuration export contains and every problem found, before anything is created.
struct ImportReviewSheet: View {
    let pending: PendingImport
    let onCreate: (_ assignNewProjectID: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assignNewProjectID = true

    private var result: ConfigurationImportResult { pending.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Import Configuration")
                    .font(.title2.bold())
                Text(pending.fileName)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            Form {
                Section("Contents") {
                    LabeledContent("Project", value: result.project.settings.projectName)
                    LabeledContent("Organization", value: result.project.settings.organizationName)
                    LabeledContent("Package identifier", value: result.project.settings.packageIdentifier)
                    LabeledContent("Applications", value: "\(result.project.allApplications.count)")
                    LabeledContent("Scripts", value: "\(result.project.scripts.count)")
                    LabeledContent("Files", value: "\(result.assets.count)")
                    LabeledContent("Exported", value: result.exportedAt)
                    LabeledContent("Exported by version", value: result.sourceApplicationVersion)
                    LabeledContent("Schema", value: result.sourceSchemaVersion == result.project.schemaVersion
                                   ? "\(result.project.schemaVersion)"
                                   : "\(result.sourceSchemaVersion), migrated to \(result.project.schemaVersion)")
                }
                Section("Checks") {
                    if result.issues.isEmpty {
                        Label("Paths, sizes, hashes, images and identifiers all checked out.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(result.issues) { issue in
                        FieldIssueLabel(message: issue.message, severity: issue.severity == .error ? .error : .warning)
                    }
                }
                Section("New project") {
                    Toggle("Assign a new project ID", isOn: $assignNewProjectID)
                    Text(assignNewProjectID
                         ? "Recommended. Devices keep enrollment state per project ID, so a copy should not share it."
                         : "Keep the original ID only when this import replaces the original project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if result.hasErrors {
                    FieldIssueLabel(message: "Fix the errors in the export and try again.", severity: .error)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save as New Project…") {
                    onCreate(assignNewProjectID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result.hasErrors)
            }
            .padding(14)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 620)
    }
}
