import AppKit
import SwiftUI

/// Builds the unsigned flat installer package, exports the framework for manual testing, and copies
/// ready-to-paste test commands.
struct PackageBuilderView: View {
    @Binding var document: EnrollmentProjectDocument
    let report: ValidationReport
    @ObservedObject var workspace: WorkspaceViewModel

    @State private var isWorking = false
    @State private var progressText = ""
    @State private var lastBuild: PackageBuildResult?
    @State private var lastExport: FrameworkExportResult?
    @State private var lastExportPaths: [String] = []
    @State private var pendingAction: PendingAction?
    @State private var copiedCommands = false
    @State private var showIntuneUpload = false

    private enum PendingAction: Equatable {
        case replacePackage(String)
        case replaceExport(URL)
    }

    private var outputDirectory: URL? {
        URL(fileURLWithPath: document.project.settings.effectiveOutputDirectoryPath, isDirectory: true)
    }

    private var plan: PackagePlan? {
        outputDirectory.map { PackagePlan(project: document.project, outputDirectory: $0) }
    }

    private var exportDestination: URL? {
        outputDirectory?.appendingPathComponent(FrameworkGenerator.rootName(for: document.project), isDirectory: true)
    }

    private var blockingReason: String? {
        if report.blocksBuild { return "\(report.errorCount) validation error(s) must be fixed first. See Validation." }
        if document.isReadOnly { return "This project is read-only." }
        return nil
    }

    var body: some View {
        Form {
            packageSection
            if let lastBuild {
                buildResultSection(lastBuild)
            }
            exportSection
            if let lastExport {
                exportResultSection(lastExport)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showIntuneUpload) {
            if let lastBuild {
                IntuneUploadSheet(
                    packageURL: lastBuild.packageURL,
                    identifier: lastBuild.verification.identifier,
                    version: lastBuild.verification.version,
                    minimumMacOS: document.project.settings.minimumMacOSVersion,
                    displayName: document.project.settings.packageDisplayName,
                    publisher: document.project.settings.organizationName
                )
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                let action = pendingAction
                pendingAction = nil
                switch action {
                case .replacePackage?: buildPackage(replacing: true)
                case .replaceExport?: export(replacing: true)
                case nil: break
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The existing files are moved to the Trash and written again.")
        }
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .replacePackage?: return "Replace the existing package and report?"
        case .replaceExport?: return "Replace the existing export?"
        case nil: return ""
        }
    }

    // MARK: Package

    private var packageSection: some View {
        Section("Installer package") {
            Text("Builds an unsigned flat component package with pkgbuild. It installs the framework and its LaunchDaemon; the postinstall script starts enrollment. Building needs no administrator rights and never installs anything on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Validation") {
                if report.blocksBuild {
                    Label("\(report.errorCount) error(s)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                } else {
                    Label("Ready (\(report.warningCount) warning(s))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            LabeledContent("Identifier", value: document.project.settings.packageIdentifier)
            LabeledContent("Version", value: document.project.settings.packageVersion)
            LabeledContent("Installs to", value: FrameworkGenerator.trimmedDirectory(document.project.settings.installLocation))
            LabeledContent("Package") {
                Text(plan?.packageURL.path ?? "No output folder chosen")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack {
                Button("Build Package…") {
                    buildPackage(replacing: false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(blockingReason != nil || isWorking)
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text(progressText).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let blockingReason {
                FieldIssueLabel(message: blockingReason, severity: .warning)
            }
        }
    }

    private func buildResultSection(_ build: PackageBuildResult) -> some View {
        let verification = build.verification
        return Section("Last build") {
            LabeledContent("Package") {
                Text(build.packageURL.path).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
            LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: verification.sizeBytes, countStyle: .file))
            LabeledContent("SHA-256") {
                HStack {
                    Text(verification.sha256).font(.caption.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Button("Copy") { copyToClipboard(verification.sha256) }
                }
            }
            LabeledContent("Identifier", value: verification.identifier)
            LabeledContent("Version", value: verification.version)
            LabeledContent("Signature", value: verification.signatureStatus)
            LabeledContent("Payload files", value: "\(verification.payloadFileCount)")
            DisclosureGroup(verification.passed ? "Verification passed" : "Verification failed") {
                ForEach(verification.checks) { check in
                    Label("\(check.title): \(check.detail)", systemImage: check.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.passed ? Color.green : Color.red)
                        .font(.caption)
                }
            }
            HStack {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([build.packageURL]) }
                Button("Open Report") { NSWorkspace.shared.open(build.reportURL) }
                Button("Upload to Intune…") { showIntuneUpload = true }
                    .disabled(!build.verification.passed || !FileManager.default.fileExists(atPath: build.packageURL.path))
            }
            Text("Installing this package on a Mac starts enrollment immediately. Test on a test Mac, or use the exported framework with --dry-run and --preview below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section("Framework export for testing") {
            Text("Writes the framework files to a folder so you can inspect them or test with --dry-run and --preview without installing the package.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Destination") {
                Text(exportDestination?.path ?? "No output folder chosen")
                    .font(.callout.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
            HStack {
                Button("Export Generated Files…") {
                    export(replacing: false)
                }
                .disabled(blockingReason != nil || isWorking)
                Button(copiedCommands ? "Copied" : "Copy Test Commands") {
                    copyTestCommands()
                }
                .disabled(exportDestination == nil)
                .help("Copies the Terminal commands that install this export into the install location and run --dry-run and --preview.")
            }
        }
    }

    private func exportResultSection(_ result: FrameworkExportResult) -> some View {
        Section("Last export") {
            LabeledContent("Folder") {
                Text(result.destination.path).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
            LabeledContent("Files", value: "\(result.fileCount)")
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.destination]) }
            DisclosureGroup("Generated files") {
                ForEach(lastExportPaths, id: \.self) { path in
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    // MARK: Actions

    private func copyTestCommands() {
        guard let exportDestination else { return }
        copyToClipboard(TestCommands.make(
            exportFolder: exportDestination.path,
            installLocation: FrameworkGenerator.trimmedDirectory(document.project.settings.installLocation)
        ))
        copiedCommands = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedCommands = false
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func buildPackage(replacing: Bool) {
        guard blockingReason == nil, let outputDirectory, let plan else { return }
        let fileManager = FileManager.default
        if !replacing && (fileManager.fileExists(atPath: plan.packageURL.path) || fileManager.fileExists(atPath: plan.reportURL.path)) {
            pendingAction = .replacePackage(plan.packageURL.path)
            return
        }
        let project = document.project
        let assets = document.assets
        let installers = document.installerSources
        let validation = report
        isWorking = true
        progressText = "Starting…"
        Task {
            do {
                let result = try await PackageBuilder.live().build(
                    project: project,
                    assets: assets,
                    installerSources: installers,
                    validation: validation,
                    outputDirectory: outputDirectory,
                    replaceExisting: replacing,
                    progress: { message in
                        Task { @MainActor in progressText = message }
                    }
                )
                lastBuild = result
                do {
                    try BuildHistoryStore.standard().append(result.record, for: project.id)
                } catch {
                    workspace.present(error, title: "The Package Was Built but Build History Could Not Be Updated")
                }
            } catch {
                workspace.present(error, title: "Could Not Build the Package")
            }
            isWorking = false
        }
    }

    private func export(replacing: Bool) {
        guard blockingReason == nil, let outputDirectory else { return }
        let framework: GeneratedFramework
        do {
            framework = try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)
        } catch {
            workspace.present(error, title: "Could Not Generate the Framework")
            return
        }
        let target = FrameworkExporter.destination(for: framework, in: outputDirectory)
        if FileManager.default.fileExists(atPath: target.path) && !replacing {
            pendingAction = .replaceExport(target)
            return
        }
        isWorking = true
        progressText = "Writing files…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                try FrameworkExporter.write(framework, to: target, replacingExisting: replacing)
            }.result
            isWorking = false
            switch result {
            case .success(let exported):
                lastExport = exported
                lastExportPaths = framework.allPaths
            case .failure(let error):
                workspace.present(error, title: "Could Not Export the Framework")
            }
        }
    }
}
