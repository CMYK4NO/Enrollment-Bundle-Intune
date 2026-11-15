import AppKit
import Foundation

/// Holds what must be cleaned up even when the app quits: termination notifications arrive outside the
/// main actor's task scheduling, so cleanup there has to be synchronous and thread-safe.
private final class PreviewCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var directory: URL?
    var observer: NSObjectProtocol?

    func track(process: Process?, directory: URL?) {
        lock.lock()
        self.process = process
        self.directory = directory
        lock.unlock()
    }

    func cleanUpNow() {
        lock.lock()
        let process = self.process
        let directory = self.directory
        self.process = nil
        self.directory = nil
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// Runs the real swiftDialog as a preview. It writes a temporary configuration and icons, launches
/// swiftDialog as the current user, and mirrors the static preview's simulated statuses through the
/// command file. It never runs enrollment scripts, needs no administrator rights and never installs
/// swiftDialog. Temporary files are removed when the preview stops, the page closes or the app quits.
@MainActor
final class LiveDialogPreviewController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case running
        case unavailable(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var process: Process?
    private var workingDirectory: URL?
    private var commandFile: URL?
    private var listIndexes: [String: Int] = [:]
    private var lastState: PreviewState?
    private let cleanup = PreviewCleanup()

    var isRunning: Bool { phase == .running }

    init() {
        let cleanup = self.cleanup
        cleanup.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            cleanup.cleanUpNow()
        }
    }

    deinit {
        cleanup.cleanUpNow()
        if let observer = cleanup.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Start and stop

    func start(project: EnrollmentProject, assets: [String: Data], deviceValues: [Placeholder: String], state: PreviewState) async {
        stop()
        phase = .checking
        let dialogPath = project.settings.swiftDialogPath
        guard FileManager.default.isExecutableFile(atPath: dialogPath) else {
            phase = .unavailable("swiftDialog is not installed at \(dialogPath), so only the static preview is available. Install swiftDialog on this Mac to use the live preview.")
            return
        }
        let runner = ProcessCommandRunner(allowedExecutables: [dialogPath])
        let version: String
        do {
            let result = try await runner.run(executable: URL(fileURLWithPath: dialogPath), arguments: ["--version"], standardInput: nil, timeout: 10)
            version = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }
        let minimum = project.settings.swiftDialogMinimumVersion
        guard !version.isEmpty, VersionComparison.isAtLeast(version, minimum) else {
            phase = .unavailable("swiftDialog \(version.isEmpty ? "(unknown version)" : version) is older than the project's minimum \(minimum).")
            return
        }

        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EnrollmentBundleStudio-Preview-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            workingDirectory = directory

            let iconDirectory = directory.appendingPathComponent("icons", isDirectory: true)
            try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
            func iconFile(_ assetPath: String) -> String? {
                guard let data = assets[assetPath] else { return nil }
                let url = directory.appendingPathComponent(FrameworkGenerator.iconRelativePath(for: assetPath))
                guard (try? data.write(to: url)) != nil else { return nil }
                return url.path
            }
            func iconValue(_ icon: IconSource, _ applicationPath: String) -> String {
                switch icon.kind {
                case .applicationBundle: return applicationPath.isEmpty ? "SF=app.dashed" : applicationPath
                case .projectAsset: return iconFile(icon.value) ?? "SF=photo"
                case .sfSymbol: return "SF=\(icon.value)"
                }
            }

            let entries = DialogConfigBuilder.listEntries(project: project, iconPath: iconValue)
            listIndexes = [:]
            for entry in entries {
                for id in entry.taskIdentifiers where !entry.isSummary {
                    listIndexes[id] = entry.index
                }
            }
            let configuration = DialogConfigBuilder.configuration(
                project: project,
                entries: entries,
                totalTasks: state.totalCount,
                logoPath: project.branding.logoPath.flatMap(iconFile),
                bannerPath: project.branding.bannerPath.flatMap(iconFile),
                overlayIconPath: project.branding.overlayIconPath.flatMap(iconFile),
                resolve: { PlaceholderResolver.resolve($0, values: deviceValues) }
            )
            let jsonURL = directory.appendingPathComponent("dialog.json")
            try DialogConfigBuilder.jsonData(configuration).write(to: jsonURL)
            let commandURL = directory.appendingPathComponent("commands.log")
            try Data().write(to: commandURL)
            commandFile = commandURL

            let process = Process()
            process.executableURL = URL(fileURLWithPath: dialogPath)
            var arguments = ["--jsonfile", jsonURL.path, "--commandfile", commandURL.path]
            if project.settings.lockCompletionButtonUntilRequiredComplete {
                arguments.append("--button1disabled")
            }
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.processEnded()
                }
            }
            try process.run()
            self.process = process
            cleanup.track(process: process, directory: directory)
            phase = .running
            lastState = nil
            apply(state: state, project: project, deviceValues: deviceValues)
        } catch {
            stop()
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func stop() {
        if let process, process.isRunning {
            send([DialogCommand.quit])
            process.terminate()
        }
        process = nil
        commandFile = nil
        lastState = nil
        if let workingDirectory {
            try? FileManager.default.removeItem(at: workingDirectory)
        }
        workingDirectory = nil
        cleanup.track(process: nil, directory: nil)
        if phase == .running || phase == .checking {
            phase = .idle
        }
    }

    private func processEnded() {
        // The user closed the window, or it quit.
        process = nil
        stop()
        phase = .idle
    }

    // MARK: Mirroring the static preview

    /// Sends only what changed since the last state, in the same vocabulary as the device framework.
    func apply(state: PreviewState, project: EnrollmentProject, deviceValues: [Placeholder: String]) {
        guard phase == .running else { return }
        var commands: [String] = []
        let previous = lastState
        for (index, item) in state.displayItems.enumerated() {
            let old = previous?.displayItems.indices.contains(index) == true ? previous?.displayItems[index] : nil
            if old?.status != item.status || old?.statusText != item.statusText {
                commands.append(DialogCommand.listItem(index: index, status: item.status, text: item.statusText))
            }
        }
        if previous?.finishedCount != state.finishedCount || previous?.outcome != state.outcome {
            commands.append(DialogCommand.progress(state.finishedCount))
            commands.append(DialogCommand.progressText(progressText(for: state)))
        }
        if previous?.outcome != state.outcome {
            let branding = project.branding
            let message: String
            switch state.outcome {
            case .inProgress: message = branding.welcomeMessage
            case .success: message = branding.completionMessage
            case .successWithWarnings: message = branding.warningMessage
            case .failed: message = branding.failureMessage
            }
            commands.append(DialogCommand.message(PlaceholderResolver.resolve(message, values: deviceValues)))
            if state.outcome == .success || state.outcome == .successWithWarnings {
                commands.append(DialogCommand.icon("SF=\(branding.completionSymbol)"))
            }
        }
        if previous?.isButtonEnabled != state.isButtonEnabled {
            if state.isButtonEnabled {
                commands.append(DialogCommand.buttonText(project.branding.buttonText))
                commands.append(DialogCommand.buttonEnable)
            } else {
                commands.append(DialogCommand.buttonText(project.branding.inProgressButtonText))
                commands.append(DialogCommand.buttonDisable)
            }
        }
        lastState = state
        send(commands)
    }

    private func progressText(for state: PreviewState) -> String {
        switch state.outcome {
        case .inProgress: return "\(state.finishedCount) of \(state.totalCount) complete"
        case .success: return "Setup complete"
        case .successWithWarnings: return "Setup complete with warnings"
        case .failed: return "Setup needs attention"
        }
    }

    private func send(_ commands: [String]) {
        guard !commands.isEmpty, let commandFile, let handle = try? FileHandle(forWritingTo: commandFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let text = commands.joined(separator: "\n") + "\n"
        try? handle.write(contentsOf: Data(text.utf8))
    }
}
