import Foundation

/// Where a list item's icon comes from. Stored as a small readable object in project.json.
struct IconSource: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// Use the icon of the installed application (swiftDialog accepts an .app path as an icon).
        case applicationBundle
        /// Use an image copied into the project's Icons folder. `value` is the relative path.
        case projectAsset
        /// Use an SF Symbol. `value` is the symbol name.
        case sfSymbol

        var id: String { rawValue }

        var title: String {
            switch self {
            case .applicationBundle: return "Installed app icon"
            case .projectAsset: return "Project image"
            case .sfSymbol: return "SF Symbol"
            }
        }
    }

    var kind: Kind
    var value: String
}

/// A detection or validation rule.
struct TaskCheck: Codable, Equatable {
    var method: ValidationMethod
    /// Receipt identifier or command for methods where `method.requiresValue` is true; otherwise empty.
    var value: String
}

/// Text shown next to a list item for each status.
struct TaskMessages: Codable, Equatable {
    var waiting: String
    var progress: String
    var success: String
    var warning: String
    var failure: String

    static let standard = TaskMessages(
        waiting: "Waiting for Intune",
        progress: "Installing…",
        success: "Installed",
        warning: "Installed with warnings",
        failure: "Not installed"
    )

    static let script = TaskMessages(
        waiting: "Waiting",
        progress: "Running…",
        success: "Done",
        warning: "Done with warnings",
        failure: "Failed"
    )

    static let system = TaskMessages(
        waiting: "Waiting",
        progress: "Checking…",
        success: "Complete",
        warning: "Complete with warnings",
        failure: "Failed"
    )
}

/// Execution properties shared by every kind of enrollment task.
struct TaskExecutionOptions: Codable, Equatable {
    var isRequired: Bool = true
    /// Hidden tasks run in the background and still count toward unlocking the completion button.
    var isVisible: Bool = true
    var context: ExecutionContext = .root
    var timeoutSeconds: Int = 900
    var retryCount: Int = 0
    /// Task identifiers this task waits for.
    var dependencies: [String] = []
    var executionOrder: Int = 100
    /// Where new applications start. Scripts are numbered from 100 upward (see `nextScriptExecutionOrder`), so
    /// by default scripts run before applications; final validation stays last at 900.
    static let defaultApplicationOrder = 500
    /// Tasks with the same non-empty group name may run concurrently. Empty means sequential.
    var parallelGroup: String = ""
    /// Whether a "Skipped" result is acceptable for a required task.
    var allowSkip: Bool = false
    /// Whether the task runs again on a later run after it already completed.
    var allowRerun: Bool = false
    var messages: TaskMessages = .standard
}

/// An application that the enrollment experience detects and displays.
struct ApplicationItem: Codable, Equatable, Identifiable {
    var id: UUID
    /// Stable, human-readable identifier used for dependencies and state files (e.g. "app.microsoft-edge").
    var taskIdentifier: String
    /// Catalogue entry this item was created from, if any.
    var catalogID: String?
    var displayName: String
    var applicationPath: String
    var bundleIdentifier: String
    var processName: String
    var icon: IconSource
    var detection: TaskCheck
    var installStrategy: ApplicationInstallStrategy
    var isEnabled: Bool
    var execution: TaskExecutionOptions
    /// Installer package copied into the project's Installers folder, used by the
    /// "Run bundled installer" strategy (schema 3). Optional, so older projects decode unchanged.
    var installer: InstallerReference?
    /// Task identifier of the imported script that "Run custom script" runs for this app. The script runs
    /// first; the app is then detected. Optional, so older projects decode unchanged.
    var customScriptTaskIdentifier: String?

    static func makeCustom(strategy: ApplicationInstallStrategy, timeoutSeconds: Int) -> ApplicationItem {
        var execution = TaskExecutionOptions()
        execution.isRequired = false
        execution.timeoutSeconds = timeoutSeconds
        execution.executionOrder = TaskExecutionOptions.defaultApplicationOrder
        return ApplicationItem(
            id: UUID(),
            taskIdentifier: "",
            catalogID: nil,
            displayName: "",
            applicationPath: "/Applications/",
            bundleIdentifier: "",
            processName: "",
            icon: IconSource(kind: .applicationBundle, value: ""),
            detection: TaskCheck(method: .applicationPath, value: ""),
            installStrategy: strategy,
            isEnabled: true,
            execution: execution
        )
    }
}

/// A flat installer package stored in the project. The package file itself lives in Installers/.
struct InstallerReference: Codable, Equatable {
    /// Path relative to the project root, always Installers/<name>.pkg.
    var relativePath: String
    var originalFilename: String
    /// Lowercase hexadecimal SHA-256 of the package.
    var sha256: String
    var sizeBytes: Int64
    var importedAt: Date
}

/// A named group of applications, such as "Microsoft 365".
struct ApplicationGroup: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var symbolName: String
    /// When true, every application in the group is treated as required.
    var isRequired: Bool
    var displayBehavior: GroupDisplayBehavior
    var applications: [ApplicationItem]
}

/// A shell script copied into the project's Scripts folder. Importing copies and inspects the file;
/// the application never executes it.
struct ScriptItem: Codable, Equatable, Identifiable {
    var id: UUID
    var taskIdentifier: String
    var displayName: String
    /// Path relative to the project root, always inside Scripts/.
    var relativePath: String
    var originalFilename: String
    var sha256: String
    /// Interpreter from the shebang line, e.g. "/bin/bash".
    var interpreter: String
    /// Whether the source file had an executable bit when imported (schema 2).
    /// The package builder always sets 755 on packaged scripts regardless.
    var sourceWasExecutable: Bool
    /// When the file was imported or last replaced (schema 2).
    var importedAt: Date
    /// Exit codes that count as success. Usually [0].
    var successExitCodes: [Int]
    var execution: TaskExecutionOptions
}

/// A task that has no source item: Intune sync, wait conditions, validation steps.
struct EnrollmentTask: Codable, Equatable, Identifiable {
    var id: UUID
    var taskIdentifier: String
    var displayName: String
    var type: TaskType
    var icon: IconSource
    var detection: TaskCheck?
    var validation: TaskCheck?
    var execution: TaskExecutionOptions

    /// Hidden, required task that completes only after every other required task is acceptable.
    static func makeFinalValidation(taskIdentifier: String) -> EnrollmentTask {
        var execution = TaskExecutionOptions()
        execution.isRequired = true
        execution.isVisible = false
        execution.executionOrder = 900
        execution.timeoutSeconds = 300
        execution.messages = TaskMessages(
            waiting: "Waiting for required items",
            progress: "Checking device readiness…",
            success: "Device ready",
            warning: "Ready with warnings",
            failure: "Device not ready"
        )
        return EnrollmentTask(
            id: UUID(),
            taskIdentifier: taskIdentifier,
            displayName: "Final validation",
            type: .finalValidation,
            icon: IconSource(kind: .sfSymbol, value: "checkmark.shield"),
            detection: nil,
            validation: nil,
            execution: execution
        )
    }
}
