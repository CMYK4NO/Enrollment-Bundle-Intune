import SwiftUI

/// Project identity and package identity.
struct OverviewView: View {
    @Binding var document: EnrollmentProjectDocument
    let fileURL: URL?
    @ObservedObject var workspace: WorkspaceViewModel

    private var settings: ProjectSettings { document.project.settings }

    private func chooseOutputDirectory() {
        Task {
            if let url = await FilePanels.openDirectory(title: "Choose the Output Folder") {
                document.project.settings.outputDirectoryPath = url.standardizedFileURL.path
            }
        }
    }

    private var outputDirectoryIssue: String? {
        let path = settings.effectiveOutputDirectoryPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The output folder does not exist."
        }
        return FileManager.default.isWritableFile(atPath: path) ? nil : "The output folder is not writable."
    }

    var body: some View {
        Form {
            if let fromVersion = document.migratedFromVersion {
                Section("Migrated from schema \(fromVersion) to \(AppInfo.currentSchemaVersion)") {
                    ForEach(Array(document.migrationSummary.enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "arrow.up.circle")
                    }
                }
            }
            if !document.loadNotes.isEmpty {
                Section("Opened with notes") {
                    ForEach(Array(document.loadNotes.enumerated()), id: \.offset) { _, note in
                        FieldIssueLabel(message: note, severity: .warning)
                    }
                }
            }

            Section("Project") {
                ValidatedTextField(
                    title: "Project name",
                    text: $document.project.settings.projectName,
                    issue: FieldValidator.requiredTextIssue(settings.projectName)
                )
                ValidatedTextField(
                    title: "Organization name",
                    text: $document.project.settings.organizationNameLinkedToIdentifiers,
                    prompt: "Contoso",
                    issue: FieldValidator.requiredTextIssue(settings.organizationName)
                )
                LabeledContent("Project file") {
                    Text(fileURL?.path ?? "Not saved yet")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                LabeledContent("Project ID") {
                    Text(document.project.id.uuidString)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Package identity") {
                ValidatedTextField(
                    title: "Package display name",
                    text: $document.project.settings.packageDisplayName,
                    issue: FieldValidator.requiredTextIssue(settings.packageDisplayName)
                )
                ValidatedTextField(
                    title: "Package identifier",
                    text: $document.project.settings.packageIdentifier,
                    prompt: "com.company.enrollment.bundle",
                    issue: FieldValidator.reverseDNSIssue(settings.packageIdentifier)
                )
                ValidatedTextField(
                    title: "Bundle identifier",
                    text: $document.project.settings.bundleIdentifier,
                    prompt: "com.company.enrollment",
                    issue: FieldValidator.reverseDNSIssue(settings.bundleIdentifier)
                )
                ValidatedTextField(
                    title: "Version",
                    text: Binding(
                        get: { document.project.settings.packageVersion },
                        set: { document.project.setVersion($0) }
                    ),
                    prompt: "1.0.0",
                    issue: FieldValidator.versionIssue(settings.packageVersion)
                )
                Text("One version for the installer package and the enrollment bundle. Raise it when devices should re-evaluate tasks they already completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Minimum macOS", selection: $document.project.settings.minimumMacOSVersion.deferringWrites()) {
                    ForEach(ProjectSettings.supportedMinimumMacOSVersions) { release in
                        Text(release.name).tag(release.version)
                    }
                }
            }

            Section("Output folder") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.effectiveOutputDirectoryPath)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseOutputDirectory() }
                            .disabled(document.isReadOnly)
                        Button("Use Downloads") { document.project.settings.outputDirectoryPath = "" }
                            .disabled(document.isReadOnly || settings.outputDirectoryPath.isEmpty)
                    }
                }
                if let issue = outputDirectoryIssue {
                    FieldIssueLabel(message: issue, severity: .error)
                }
                Text(settings.outputDirectoryPath.isEmpty
                     ? "Downloads is the default. The installer package, its build report and framework exports are written here."
                     : "The installer package, its build report and framework exports are written here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Copies and transfer") {
                HStack {
                    Button("Export Configuration…") { workspace.request(.exportConfiguration) }
                    Button("Import Configuration…") { workspace.request(.importConfiguration) }
                    Button("Duplicate as New Project…") { workspace.request(.duplicateProject) }
                }
                Text("An export is one readable .enrollmentconfig file with project.json, the referenced icons and scripts, and their SHA-256 hashes. Duplicate as New Project assigns a new project ID; File > Duplicate keeps the same ID, which devices use to track enrollment state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Summary") {
                LabeledContent("Application groups", value: "\(document.project.applicationGroups.count)")
                LabeledContent("Enabled applications", value: "\(enabledApplications.count)")
                LabeledContent("Required applications", value: "\(requiredApplicationCount)")
                LabeledContent("Scripts", value: "\(document.project.scripts.count)")
                LabeledContent("System tasks", value: "\(document.project.systemTasks.count)")
                LabeledContent("Schema version", value: "\(document.project.schemaVersion)")
            }
        }
        .formStyle(.grouped)
    }

    private var enabledApplications: [ApplicationItem] {
        document.project.allApplications.filter { $0.isEnabled }
    }

    private var requiredApplicationCount: Int {
        document.project.applicationGroups.reduce(0) { total, group in
            total + group.applications.filter { $0.isEnabled && (group.isRequired || $0.execution.isRequired) }.count
        }
    }

}
