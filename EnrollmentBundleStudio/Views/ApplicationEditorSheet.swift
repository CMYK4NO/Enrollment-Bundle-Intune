import AppKit
import SwiftUI

/// A group the application can be placed in. `nil` id in the editor means "create a new group".
struct GroupChoice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let isRequired: Bool
}

/// What the editor returns when the administrator saves.
struct ApplicationEditResult {
    let item: ApplicationItem
    let pendingIcon: PendingAsset?
    let pendingInstaller: PendingInstaller?
    /// Target group, or nil to create the new-group option.
    let groupID: UUID?
    let newGroupName: String
}

/// Edits a draft copy of an application. Nothing changes in the project until Save.
struct ApplicationEditorSheet: View {
    static let newGroupName = "Custom Applications"

    let context: ApplicationEditContext
    let assets: [String: Data]
    let onSave: (ApplicationEditResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ApplicationItem
    @State private var selectedGroupID: UUID?
    @State private var pendingIcon: PendingAsset?
    @State private var pendingInstaller: PendingInstaller?
    @State private var isInspectingInstaller = false
    @State private var importError: String?

    init(context: ApplicationEditContext, assets: [String: Data], onSave: @escaping (ApplicationEditResult) -> Void) {
        self.context = context
        self.assets = assets
        self.onSave = onSave
        _draft = State(initialValue: context.draft)
        _selectedGroupID = State(initialValue: context.groupID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                identitySection
                groupSection
                deliverySection
                detectionSection
                behaviorSection
                iconSection
                messagesSection
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 560, idealHeight: 760)
    }

    private var selectedGroup: GroupChoice? {
        context.groups.first { $0.id == selectedGroupID }
    }

    private var requiredLocked: Bool {
        selectedGroup?.isRequired ?? false
    }

    // MARK: Sections

    private var identitySection: some View {
        Section(context.isNew ? "New application" : "Application") {
            TextField("Display name", text: $draft.displayName, prompt: Text("Microsoft Edge"))
            TextField("Application path", text: $draft.applicationPath, prompt: Text("/Applications/Example.app"))
            TextField("Bundle identifier", text: $draft.bundleIdentifier, prompt: Text("com.vendor.app"))
            LabeledContent("Task identifier") {
                Text(context.isNew ? "Assigned when added" : draft.taskIdentifier)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !draft.applicationPath.isEmpty && draft.applicationPath != "/Applications/"
                && !FileManager.default.fileExists(atPath: draft.applicationPath) {
                FieldIssueLabel(message: "Not installed on this Mac. That is fine; detection runs on the device.", severity: .warning)
            }
        }
    }

    private var groupSection: some View {
        Section("Group") {
            Picker("Group", selection: $selectedGroupID) {
                ForEach(context.groups) { group in
                    Text(group.isRequired ? "\(group.name) (required group)" : group.name).tag(Optional(group.id))
                }
                if !context.groups.contains(where: { $0.name == Self.newGroupName }) {
                    Text("New group: \(Self.newGroupName)").tag(UUID?.none)
                }
            }
            if requiredLocked {
                Text("Every app in a required group is required. Choose another group to make this app optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deliverySection: some View {
        Section("Delivery") {
            Picker("Strategy", selection: $draft.installStrategy) {
                ForEach(ApplicationInstallStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            Text(draft.installStrategy.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if draft.installStrategy == .bundledInstaller {
                installerControls
            }
            if draft.installStrategy == .customScript {
                Picker("Script", selection: $draft.customScriptTaskIdentifier) {
                    Text("None").tag(String?.none)
                    ForEach(context.scripts) { script in
                        Text(script.name).tag(Optional(script.id))
                    }
                    if let linked = draft.customScriptTaskIdentifier, !context.scripts.contains(where: { $0.id == linked }) {
                        Text("Missing: \(linked)").tag(Optional(linked))
                    }
                }
                if draft.customScriptTaskIdentifier == nil {
                    FieldIssueLabel(
                        message: context.scripts.isEmpty
                            ? "Import a script in Scripts first, then choose it here."
                            : "Choose the script to run. Without one, the app is only detected, like Wait for Intune.",
                        severity: .warning
                    )
                } else {
                    Text("The script runs first, then the app is checked with the detection settings below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var installerControls: some View {
        let shownName = pendingInstaller?.inspection.originalFilename ?? draft.installer?.originalFilename
        let shownSize = pendingInstaller?.inspection.sizeBytes ?? draft.installer?.sizeBytes
        let shownHash = pendingInstaller?.inspection.sha256 ?? draft.installer?.sha256
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shownName ?? "No package chosen")
                if let shownSize {
                    Text(ByteCountFormatter.string(fromByteCount: shownSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let shownHash {
                    Text("SHA-256 \(shownHash)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if isInspectingInstaller {
                ProgressView().controlSize(.small)
            }
            Button("Choose Package…") {
                chooseInstaller()
            }
            .disabled(isInspectingInstaller)
            Button("Remove") {
                pendingInstaller = nil
                draft.installer = nil
            }
            .disabled(shownName == nil || isInspectingInstaller)
        }
        Text("Flat .pkg files only. The package is copied into the project's Installers folder when you save the project, and it runs on the device during enrollment. It is never opened or installed on this Mac.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if shownName == nil {
            FieldIssueLabel(message: "Choose a package, or this app can never complete.", severity: .warning)
        }
    }

    private var detectionSection: some View {
        Section("Detection") {
            Picker("Method", selection: $draft.detection.method) {
                ForEach(ValidationMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            Text(draft.detection.method.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if draft.detection.method.requiresValue {
                TextField(
                    draft.detection.method == .packageReceipt ? "Receipt identifier" : "Command",
                    text: $draft.detection.value,
                    prompt: Text(draft.detection.method.valuePrompt)
                )
                .font(.body.monospaced())
            }
            if draft.detection.method == .processRunning {
                TextField("Process name", text: $draft.processName, prompt: Text("Company Portal"))
            }
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Required", isOn: requiredBinding)
                .disabled(requiredLocked)
            Toggle("Enabled", isOn: $draft.isEnabled)
            Toggle("Show in the enrollment list", isOn: $draft.execution.isVisible)
            Toggle("Allow Skipped as an acceptable result", isOn: $draft.execution.allowSkip)
            Stepper(value: $draft.execution.timeoutSeconds, in: ProjectSettings.taskTimeoutRange, step: 30) {
                LabeledContent("Timeout", value: DurationFormatter.format(seconds: draft.execution.timeoutSeconds))
            }
        }
    }

    /// Shows the effective state: a required group forces Required on.
    private var requiredBinding: Binding<Bool> {
        Binding(
            get: { requiredLocked || draft.execution.isRequired },
            set: { draft.execution.isRequired = $0 }
        )
    }

    private var iconSection: some View {
        Section("Icon") {
            HStack(spacing: 12) {
                IconSourceImage(icon: draft.icon, applicationPath: draft.applicationPath, assets: previewAssets, size: 44)
                Picker("Source", selection: $draft.icon.kind) {
                    ForEach(IconSource.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            switch draft.icon.kind {
            case .applicationBundle:
                Text("swiftDialog shows the icon of the installed app. Before the app arrives it shows a generic icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .projectAsset:
                HStack {
                    Text(draft.icon.value.isEmpty ? "No image chosen" : draft.icon.value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose Image…") {
                        chooseIcon()
                    }
                }
            case .sfSymbol:
                TextField("Symbol name", text: $draft.icon.value, prompt: Text("app.badge"))
            }
        }
    }

    private var messagesSection: some View {
        Section("Status messages") {
            TextField("Waiting", text: $draft.execution.messages.waiting)
            TextField("In progress", text: $draft.execution.messages.progress)
            TextField("Success", text: $draft.execution.messages.success)
            TextField("Warning", text: $draft.execution.messages.warning)
            TextField("Failure", text: $draft.execution.messages.failure)
        }
    }

    private var footer: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                if let importError {
                    FieldIssueLabel(message: importError, severity: .error)
                }
                ForEach(validationIssues, id: \.self) { issue in
                    FieldIssueLabel(message: issue, severity: .error)
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(context.isNew ? "Add" : "Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!validationIssues.isEmpty || isInspectingInstaller)
        }
        .padding(14)
    }

    // MARK: Logic

    private var previewAssets: [String: Data] {
        var combined = assets
        if let pendingIcon {
            combined[pendingIcon.path] = pendingIcon.data
        }
        return combined
    }

    private var validationIssues: [String] {
        var issues: [String] = []
        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter a display name.")
        }
        let path = draft.applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.hasPrefix("/") || path == "/" || path == "/Applications/" {
            issues.append("Enter the full application path, for example /Applications/Example.app.")
        }
        switch draft.detection.method {
        case .bundleIdentifier:
            if !FieldValidator.isValidReverseDNS(draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)) {
                issues.append("Bundle identifier detection needs a valid bundle identifier.")
            }
        case .processRunning:
            if draft.processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Process detection needs a process name.")
            }
        case .packageReceipt, .customCommand:
            if draft.detection.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Enter a value for the detection method.")
            }
        case .applicationPath:
            break
        }
        switch draft.icon.kind {
        case .projectAsset:
            if draft.icon.value.isEmpty || previewAssets[draft.icon.value] == nil {
                issues.append("Choose an icon image, or change the icon source.")
            }
        case .sfSymbol:
            if NSImage(systemSymbolName: draft.icon.value, accessibilityDescription: nil) == nil {
                issues.append("Enter a valid SF Symbol name.")
            }
        case .applicationBundle:
            break
        }
        return issues
    }

    private func save() {
        var result = draft
        result.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.applicationPath = draft.applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        result.bundleIdentifier = draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.icon.kind == .applicationBundle {
            result.icon.value = ""
        }
        if requiredLocked {
            result.execution.isRequired = true
        }
        let iconToSave = (result.icon.kind == .projectAsset && pendingIcon?.path == result.icon.value) ? pendingIcon : nil
        onSave(ApplicationEditResult(
            item: result,
            pendingIcon: iconToSave,
            pendingInstaller: result.installStrategy == .bundledInstaller ? pendingInstaller : nil,
            groupID: selectedGroupID,
            newGroupName: Self.newGroupName
        ))
        dismiss()
    }

    private func chooseIcon() {
        Task {
            let urls = await FilePanels.openFiles(title: "Choose an Icon", allowedContentTypes: AssetImporter.allowedImageTypes)
            guard let url = urls.first else { return }
            importError = nil
            do {
                let data = try AssetImporter.readFile(at: url)
                let format = try AssetImporter.validateImage(data)
                let baseName = draft.displayName.isEmpty ? url.deletingPathExtension().lastPathComponent : draft.displayName
                let path = AssetImporter.iconPath(for: baseName, format: format, existingPaths: Set(assets.keys))
                pendingIcon = PendingAsset(path: path, data: data)
                draft.icon = IconSource(kind: .projectAsset, value: path)
            } catch {
                importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func chooseInstaller() {
        Task {
            let urls = await FilePanels.openFiles(title: "Choose an Installer Package", allowedContentTypes: FilePanels.installerPackageTypes)
            guard let url = urls.first else { return }
            importError = nil
            isInspectingInstaller = true
            defer { isInspectingInstaller = false }
            do {
                // Hashing a large package takes a moment, so it runs off the main thread.
                let inspection = try await Task.detached(priority: .userInitiated) {
                    try InstallerImporter.inspect(at: url)
                }.value
                pendingInstaller = PendingInstaller(sourceURL: url, inspection: inspection)
            } catch {
                importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
