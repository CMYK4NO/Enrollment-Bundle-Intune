import SwiftUI
import UniformTypeIdentifiers

/// Imported scripts. Importing copies and inspects a file; the app never executes scripts.
struct ScriptsView: View {
    @Binding var document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel
    let shellCheckURL: URL?

    private enum ImportMode {
        case add
        case replace(UUID)
    }

    @State private var editContext: TaskEditContext?
    @State private var pendingRemoval: ScriptItem?
    @State private var selectedScriptID: UUID?

    /// Display name of the application that runs this script as part of its own task, if any.
    private func usedByName(of script: ScriptItem) -> String? {
        guard let owner = TaskPlanner.foldedScripts(in: document.project)[script.taskIdentifier] else { return nil }
        return document.project.allApplications.first { $0.taskIdentifier == owner }?.displayName
    }

    private var sortedScripts: [ScriptItem] {
        document.project.scripts.sorted { lhs, rhs in
            if lhs.execution.executionOrder != rhs.execution.executionOrder {
                return lhs.execution.executionOrder < rhs.execution.executionOrder
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            NoticeBanner(
                symbolName: "lock.shield",
                message: "Importing copies a script into the project and checks it as text. This app never runs scripts; they run only on devices after the package is installed.",
                tint: .blue
            )
            Divider()
            if document.project.scripts.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    scriptList
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(item: $editContext) { context in
            TaskEditorSheet(context: context, project: document.project) { draft in
                document.project.apply(draft)
            }
        }
        .confirmationDialog(
            "Remove \"\(pendingRemoval?.displayName ?? "")\"?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { script in
            Button("Remove", role: .destructive) {
                var updated = document
                updated.removeScript(id: script.id)
                document = updated
                if selectedScriptID == script.id {
                    selectedScriptID = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { script in
            let dependents = document.project.dependents(of: script.taskIdentifier)
            Text(dependents.isEmpty
                 ? "The script and its file are removed from the project. You can undo this with Edit > Undo."
                 : "The script and its file are removed, and \(dependents.count) task(s) stop depending on it. You can undo this with Edit > Undo.")
        }
    }

    // MARK: Subviews

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                chooseScripts(.add)
            } label: {
                Label("Import Scripts…", systemImage: "square.and.arrow.down")
            }
            Spacer()
            if let shellCheckURL {
                Label("ShellCheck: \(shellCheckURL.path)", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("ShellCheck not installed (optional)", systemImage: "seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No scripts")
                .font(.title3.bold())
            Text("Import .sh or .zsh files. They are copied into the project, hashed and checked for Bash 3.2 and security problems.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Button("Import Scripts…") {
                chooseScripts(.add)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var scriptList: some View {
        List(selection: $selectedScriptID) {
            ForEach(sortedScripts) { script in
                ScriptRow(script: script, data: document.assets[script.relativePath], usedBy: usedByName(of: script))
                    .tag(script.id)
                    .contextMenu {
                        Button("Edit…") { editContext = TaskEditContext(taskIdentifier: script.taskIdentifier) }
                        Button("Replace File…") { beginReplace(script.id) }
                        Button("Accept Current File") { acceptCurrentFile(script.id) }
                            .disabled(!hashMismatch(script))
                        Divider()
                        Button("Remove…", role: .destructive) { pendingRemoval = script }
                    }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedScriptID, let script = document.project.script(id: id) {
            ScriptDetailView(
                script: script,
                data: document.assets[script.relativePath],
                shellCheckURL: shellCheckURL,
                onEdit: { editContext = TaskEditContext(taskIdentifier: script.taskIdentifier) },
                onReplace: { beginReplace(script.id) },
                onAccept: { acceptCurrentFile(script.id) },
                onRemove: { pendingRemoval = script }
            )
            .id(script.id)
        } else {
            Text("Select a script to see its checks and contents.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Actions

    private func hashMismatch(_ script: ScriptItem) -> Bool {
        guard let data = document.assets[script.relativePath] else { return false }
        return Hashing.sha256Hex(data) != script.sha256
    }

    private func beginReplace(_ id: UUID) {
        chooseScripts(.replace(id))
    }

    /// Shows an open panel. Choosing files only copies and inspects them; nothing is executed.
    private func chooseScripts(_ mode: ImportMode) {
        let isAdd: Bool
        if case .add = mode { isAdd = true } else { isAdd = false }
        Task {
            let urls = await FilePanels.openFiles(
                title: isAdd ? "Import Scripts" : "Replace Script File",
                allowedContentTypes: FilePanels.shellScriptTypes,
                allowsMultipleSelection: isAdd
            )
            if !urls.isEmpty {
                importScripts(urls, mode: mode)
            }
        }
    }

    private func acceptCurrentFile(_ id: UUID) {
        document.acceptCurrentScriptFile(id: id)
    }

    private func importScripts(_ urls: [URL], mode: ImportMode) {
        var updated = document
        var failures: [String] = []
        var lastImported: UUID?
        for url in urls {
            do {
                let file = try ScriptImporter.readScript(at: url)
                switch mode {
                case .add:
                    let made = try ScriptImporter.makeScriptItem(
                        data: file.data,
                        originalFilename: url.lastPathComponent,
                        wasExecutable: file.wasExecutable,
                        project: updated.project,
                        existingAssetPaths: Set(updated.assets.keys)
                    )
                    try updated.addImportedScript(made.item, data: file.data)
                    lastImported = made.item.id
                case .replace(let id):
                    try updated.replaceScriptFile(id: id, data: file.data, originalFilename: url.lastPathComponent, wasExecutable: file.wasExecutable)
                    lastImported = id
                }
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append("\(url.lastPathComponent): \(reason)")
            }
        }
        document = updated
        if let lastImported {
            selectedScriptID = lastImported
        }
        if !failures.isEmpty {
            workspace.alert = AppAlert(title: "Some Files Were Not Imported", message: failures.joined(separator: "\n"))
        }
    }
}

private struct ScriptRow: View {
    let script: ScriptItem
    let data: Data?
    let usedBy: String?

    var body: some View {
        let inspection = data.map { ScriptInspectionCache.shared.inspection(for: $0) }
        let mismatch = data.map { Hashing.sha256Hex($0) != script.sha256 } ?? false
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(script.displayName)
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(script.execution.executionOrder)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Order \(script.execution.executionOrder)")
            }
            Text(script.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let usedBy {
                Label("Runs as part of \(usedBy)", systemImage: "app.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            HStack(spacing: 8) {
                Text(script.execution.isRequired ? "Required" : "Optional")
                Text(script.execution.context == .user ? "User" : "Root")
                if !script.execution.isVisible { Text("Hidden") }
                if data == nil {
                    Label("Missing", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                } else if mismatch {
                    Label("Changed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if let inspection {
                    if inspection.count(.error) > 0 {
                        Label("\(inspection.count(.error))", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    if inspection.count(.warning) > 0 {
                        Label("\(inspection.count(.warning))", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
