import SwiftUI

/// Read-only view of one script: metadata, built-in checks, optional ShellCheck and a text preview.
struct ScriptDetailView: View {
    let script: ScriptItem
    let data: Data?
    let shellCheckURL: URL?
    let onEdit: () -> Void
    let onReplace: () -> Void
    let onAccept: () -> Void
    let onRemove: () -> Void

    @State private var shellCheckComments: [ShellCheckComment]?
    @State private var shellCheckError: String?
    @State private var isRunningShellCheck = false

    private static let previewLineLimit = 400

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                importedFileSection
                checksSection
                shellCheckSection
                previewSection
                deviceSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inspection: ScriptInspection? {
        data.map { ScriptInspectionCache.shared.inspection(for: $0) }
    }

    private var currentHash: String? {
        data.map { Hashing.sha256Hex($0) }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.displayName)
                    .font(.title2.bold())
                Text(script.taskIdentifier)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Edit…", action: onEdit)
            Button("Replace File…", action: onReplace)
            Button("Remove…", role: .destructive, action: onRemove)
        }
    }

    private var importedFileSection: some View {
        GroupBox("Imported file") {
            VStack(alignment: .leading, spacing: 6) {
                row("Project file", script.relativePath)
                row("Original name", script.originalFilename)
                row("Imported", script.importedAt.formatted(date: .abbreviated, time: .shortened))
                row("Interpreter", inspection?.interpreter ?? (script.interpreter.isEmpty ? "None" : script.interpreter))
                row("Executable when imported", script.sourceWasExecutable ? "Yes" : "No (the package sets 755 on every script)")
                row("Recorded SHA-256", script.sha256)
                if let currentHash, currentHash != script.sha256 {
                    HStack {
                        FieldIssueLabel(message: "The file changed outside the app. Current SHA-256: \(currentHash)", severity: .error)
                        Spacer()
                        Button("Accept Current File", action: onAccept)
                    }
                }
                if data == nil {
                    FieldIssueLabel(message: "The file is missing from the project. Use Replace File.", severity: .error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var checksSection: some View {
        GroupBox("Validation (text checks only, nothing is run)") {
            VStack(alignment: .leading, spacing: 6) {
                if let inspection {
                    if inspection.findings.isEmpty {
                        Label("No problems found by the built-in checks.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(inspection.findings) { finding in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: finding.severity.symbolName)
                                .foregroundStyle(color(for: finding.severity))
                                .accessibilityLabel(finding.severity.title)
                            Text(finding.line > 0 ? "Line \(finding.line)" : "File")
                                .font(.caption.monospacedDigit())
                                .frame(width: 56, alignment: .leading)
                            Text(finding.message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("No file to check.").foregroundStyle(.secondary)
                }
                Text("These heuristic checks look for Bash 3.2 incompatibilities and risky patterns. They do not replace ShellCheck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var shellCheckSection: some View {
        GroupBox("ShellCheck (optional)") {
            VStack(alignment: .leading, spacing: 6) {
                if let shellCheckURL, let data, let inspection {
                    HStack {
                        Button(isRunningShellCheck ? "Running…" : "Run ShellCheck") {
                            runShellCheck(executable: shellCheckURL, data: data, shell: inspection.shell)
                        }
                        .disabled(isRunningShellCheck || ShellCheckService.arguments(for: inspection.shell) == nil)
                        if ShellCheckService.arguments(for: inspection.shell) == nil {
                            Text("Not available for zsh scripts.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let shellCheckError {
                        FieldIssueLabel(message: shellCheckError, severity: .error)
                    }
                    if let comments = shellCheckComments {
                        if comments.isEmpty {
                            Label("ShellCheck reported no issues.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        ForEach(comments) { comment in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: comment.severity.symbolName)
                                    .foregroundStyle(color(for: comment.severity))
                                    .accessibilityLabel(comment.level)
                                Text("Line \(comment.line)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 56, alignment: .leading)
                                Text("SC\(comment.code): \(comment.message)")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    Text("ShellCheck is not installed on this Mac. The app works without it; install it if you want deeper analysis.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var previewSection: some View {
        GroupBox("Preview (read-only)") {
            if let data {
                let text = String(decoding: data, as: UTF8.self)
                let lines = text.components(separatedBy: "\n")
                let shown = lines.prefix(Self.previewLineLimit)
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal) {
                        Text(shown.enumerated().map { index, line in
                            String(format: "%4d  ", index + 1) + line
                        }.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if lines.count > Self.previewLineLimit {
                        Text("Showing the first \(Self.previewLineLimit) of \(lines.count) lines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            } else {
                Text("No file.").foregroundStyle(.secondary)
            }
        }
    }

    private var deviceSection: some View {
        GroupBox("Execution on the device") {
            VStack(alignment: .leading, spacing: 6) {
                row("Runs as", script.execution.context.title)
                row("Required", script.execution.isRequired ? "Yes" : "No")
                row("Timeout", DurationFormatter.format(seconds: script.execution.timeoutSeconds))
                row("Retries", "\(script.execution.retryCount)")
                row("Success exit codes", script.successExitCodes.map(String.init).joined(separator: ", "))
                row("Depends on", script.execution.dependencies.isEmpty ? "Nothing" : script.execution.dependencies.joined(separator: ", "))
                Text("Packaging (Phase 4) copies this exact file into the installer with permissions 755. It runs only on devices, under Intune, after installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(for severity: ValidationSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .information: return .secondary
        }
    }

    private func runShellCheck(executable: URL, data: Data, shell: ScriptShell) {
        isRunningShellCheck = true
        shellCheckError = nil
        Task {
            do {
                let runner = ProcessCommandRunner(allowedExecutables: [executable.path])
                shellCheckComments = try await ShellCheckService.run(script: data, shell: shell, executable: executable, runner: runner)
            } catch {
                shellCheckComments = nil
                shellCheckError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isRunningShellCheck = false
        }
    }
}
