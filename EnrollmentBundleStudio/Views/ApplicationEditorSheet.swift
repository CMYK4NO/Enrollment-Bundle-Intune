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
    /// Details read from the chosen package (never from the installed system).
    @State private var packageMetadata: PackageMetadata?
    @State private var packageApplication: PackageApplication?
    @State private var packageNote: String?
    /// The display name this sheet filled in from the package. It is replaced when another package is chosen,
    /// but a name the administrator typed or edited is never overwritten.
    @State private var autoFilledName: String?

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
                deliverySection
                identitySection
                groupSection
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
                packageMetadata = nil
                packageApplication = nil
                packageNote = nil
            }
            .disabled(shownName == nil || isInspectingInstaller)
        }
        packageDetails
        Text("Flat .pkg files only. The package is copied into the project's Installers folder when you save the project, and it runs on the device during enrollment. It is never installed or run on this Mac; only its small PackageInfo files are read to suggest the application path, bundle identifier and receipt.")
            .font(.caption)
            .foregroundStyle(.secondary)
        if shownName == nil {
            FieldIssueLabel(message: "Choose a package, or this app can never complete.", severity: .warning)
        }
    }

    /// What the package says about itself: the application it installs and its installer receipt.
    @ViewBuilder
    private var packageDetails: some View {
        if let packageNote {
            Text(packageNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let metadata = packageMetadata {
            if metadata.applications.count > 1 {
                Picker("Application in package", selection: Binding(
                    get: { packageApplication },
                    set: { if let application = $0 { useApplication(application, overwrite: true) } }
                )) {
                    Text("Choose…").tag(PackageApplication?.none)
                    ForEach(metadata.applications) { application in
                        Text("\(application.name) (\(application.path))").tag(Optional(application))
                    }
                }
            }
            if let application = packageApplication {
                LabeledContent("Path in package") {
                    Text(application.path).font(.callout.monospaced()).textSelection(.enabled)
                }
                if !application.bundleIdentifier.isEmpty {
                    LabeledContent("Bundle identifier in package") {
                        Text(application.bundleIdentifier).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
            }
            if let receipt = metadata.receiptIdentifier(for: packageApplication) {
                LabeledContent("Installer receipt") {
                    Text(receipt).font(.callout.monospaced()).textSelection(.enabled)
                }
                if draft.detection.method != .packageReceipt || draft.detection.value != receipt {
                    Button("Use Receipt for Detection") {
                        draft.detection.method = .packageReceipt
                        draft.detection.value = receipt
                    }
                }
            }
            if let application = packageApplication, packageValuesDiffer(from: application) {
                FieldIssueLabel(
                    message: "The application path or bundle identifier above differs from the package.",
                    severity: .warning
                )
                Button("Use Package Values") {
                    useApplication(application, overwrite: true)
                }
            }
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
        .onChange(of: draft.detection.method) { _ in
            fillReceiptIfNeeded()
        }
    }

    // MARK: Package details

    /// Fills the application path and bundle identifier from the package. Empty (or placeholder) fields are
    /// always filled; fields the administrator already set are replaced only when `overwrite` is true.
    private func useApplication(_ application: PackageApplication, overwrite: Bool) {
        packageApplication = application
        defer { fillDisplayNameIfAllowed() }
        let path = draft.applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if overwrite || path.isEmpty || path == "/Applications/" {
            draft.applicationPath = application.path
        }
        if !application.bundleIdentifier.isEmpty,
           overwrite || draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.bundleIdentifier = application.bundleIdentifier
        }
        fillReceiptIfNeeded()
    }

    private var currentPackageFilename: String {
        pendingInstaller?.inspection.originalFilename ?? draft.installer?.originalFilename ?? ""
    }

    /// Names the app after the application in the package or the Application path, or after the package file
    /// when there is no application. Only an empty name, or one this sheet filled in earlier, is replaced.
    private func fillDisplayNameIfAllowed() {
        let current = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || draft.displayName == autoFilledName else { return }
        let suggestion = DisplayNameSuggestion.suggest(
            packageApplicationPath: packageApplication?.path,
            applicationPath: draft.applicationPath,
            packageFilename: currentPackageFilename
        )
        guard !suggestion.isEmpty else { return }
        draft.displayName = suggestion
        autoFilledName = suggestion
    }

    /// With receipt detection selected and no value yet, uses the package's receipt identifier.
    private func fillReceiptIfNeeded() {
        guard draft.detection.method == .packageReceipt,
              draft.detection.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let receipt = packageMetadata?.receiptIdentifier(for: packageApplication) else { return }
        draft.detection.value = receipt
    }

    private func packageValuesDiffer(from application: PackageApplication) -> Bool {
        let path = draft.applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return path != application.path || (!application.bundleIdentifier.isEmpty && identifier != application.bundleIdentifier)
    }

    private func readPackageDetails(from url: URL) async {
        packageMetadata = nil
        packageApplication = nil
        packageNote = nil
        do {
            let metadata = try await PackageMetadataReader.live().read(at: url)
            packageMetadata = metadata
            switch metadata.applications.count {
            case 0:
                if let receipt = metadata.receiptIdentifier(for: nil), draft.detection.method == .applicationPath,
                   draft.applicationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.applicationPath == "/Applications/" {
                    draft.detection.method = .packageReceipt
                    draft.detection.value = receipt
                    packageNote = "No application bundle was found in this package (for example a fonts or driver package), so detection now uses its installer receipt. The application path can stay empty."
                } else {
                    packageNote = "No application bundle was found in this package. Enter the application path and bundle identifier yourself, or use the receipt for detection."
                }
            case 1:
                useApplication(metadata.applications[0], overwrite: false)
                if metadata.applications[0].bundleIdentifier.isEmpty {
                    packageNote = "The package does not record this app's bundle identifier and it could not be read from the package's payload. Enter it yourself."
                }
            default:
                packageNote = "This package installs several applications. Choose the one this item represents."
            }
            fillReceiptIfNeeded()
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            packageNote = "\(reason) Enter the application path and bundle identifier yourself."
        }
        fillDisplayNameIfAllowed()
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
                Text("swiftDialog shows the icon of the installed app. Before the app arrives it shows a generic icon. Use Embed App Icons on the Applications page, or a project image, to show it from the start.")
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
        let pathIsPlaceholder = path.isEmpty || path == "/Applications/"
        // Only path and bundle identifier detection use the path. A package that installs no application
        // (fonts, drivers) can leave it empty and be detected by its receipt.
        let detectionUsesPath = draft.detection.method == .applicationPath || draft.detection.method == .bundleIdentifier
        let pathProblem = detectionUsesPath
            ? (!path.hasPrefix("/") || path == "/" || pathIsPlaceholder)
            : (!pathIsPlaceholder && (!path.hasPrefix("/") || path == "/"))
        if pathProblem {
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
        if result.applicationPath == "/Applications/" && result.detection.method != .applicationPath && result.detection.method != .bundleIdentifier {
            result.applicationPath = ""
        }
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
                await readPackageDetails(from: url)
            } catch {
                importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
