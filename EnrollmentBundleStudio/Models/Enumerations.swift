import Foundation

/// How the enrollment bundle obtains an application. Intune is the primary deployment system,
/// so waiting for Intune is the default; the two "run" strategies are advanced options.
enum ApplicationInstallStrategy: String, Codable, CaseIterable, Identifiable {
    case bundledInstaller
    case customScript
    case waitForIntune
    case detectionOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waitForIntune: return "Wait for Intune"
        case .bundledInstaller: return "Run bundled installer"
        case .customScript: return "Run custom script"
        case .detectionOnly: return "Detection only"
        }
    }

    var explanation: String {
        switch self {
        case .waitForIntune:
            return "Intune deploys the app. The enrollment bundle waits until the app is detected, then marks it complete."
        case .bundledInstaller:
            return "The enrollment bundle runs an installer package included in the bundle. Default for new apps; attach an installer package to each one."
        case .customScript:
            return "Advanced. An imported script installs or configures the item. Scripts run as root unless set to user context."
        case .detectionOnly:
            return "Checks once whether the app is present and reports the result. Does not wait and never installs anything."
        }
    }
}

/// Project-wide default for running imported scripts.
enum ScriptExecutionStrategy: String, Codable, CaseIterable, Identifiable {
    case sequential
    case parallelGroups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: return "Sequential"
        case .parallelGroups: return "Parallel groups"
        }
    }

    var explanation: String {
        switch self {
        case .sequential:
            return "Scripts run one at a time in execution order. Simplest to troubleshoot."
        case .parallelGroups:
            return "Scripts that share a parallel group name run together; groups still run in order. Dependencies are always honoured."
        }
    }
}

/// Account a task runs as on the device. User context requires a logged-in console user.
enum ExecutionContext: String, Codable, CaseIterable, Identifiable {
    case root
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .root: return "Root (device)"
        case .user: return "Console user"
        }
    }
}

/// How a task decides that its item is present or valid.
enum ValidationMethod: String, Codable, CaseIterable, Identifiable {
    case applicationPath
    case bundleIdentifier
    case packageReceipt
    case processRunning
    case customCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationPath: return "App exists at path"
        case .bundleIdentifier: return "Bundle identifier matches"
        case .packageReceipt: return "Installer receipt exists"
        case .processRunning: return "Process is running"
        case .customCommand: return "Custom command"
        }
    }

    var explanation: String {
        switch self {
        case .applicationPath:
            return "Complete when the application bundle exists at the expected path."
        case .bundleIdentifier:
            return "Complete when the bundle at the expected path reports the expected bundle identifier. Guards against a stale or wrong app."
        case .packageReceipt:
            return "Complete when pkgutil reports the installer receipt entered below."
        case .processRunning:
            return "Complete when a process with the configured process name is running."
        case .customCommand:
            return "Complete when the command entered below exits with status 0. The command runs as root on the device."
        }
    }

    /// Whether the method needs the free-text `TaskCheck.value`.
    var requiresValue: Bool {
        switch self {
        case .packageReceipt, .customCommand: return true
        case .applicationPath, .bundleIdentifier, .processRunning: return false
        }
    }

    var valuePrompt: String {
        switch self {
        case .packageReceipt: return "com.vendor.pkg.identifier"
        case .customCommand: return "/usr/bin/test -d \"/Applications/Example.app\""
        case .applicationPath, .bundleIdentifier, .processRunning: return ""
        }
    }
}

/// How an application group appears in the enrollment dialog.
enum GroupDisplayBehavior: String, Codable, CaseIterable, Identifiable {
    case individualItems
    case singleSummaryItem
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individualItems: return "Show each app"
        case .singleSummaryItem: return "Show one summary row"
        case .hidden: return "Hidden (background)"
        }
    }
}

/// Kinds of enrollment work. Application and script tasks are derived from their source items;
/// the remaining types are stored as system tasks.
enum TaskType: String, Codable, CaseIterable, Identifiable {
    case applicationDetection
    case packageInstallation
    case shellScript
    case intuneSync
    case waitCondition
    case configurationValidation
    case finalValidation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationDetection: return "Application detection"
        case .packageInstallation: return "Package installation"
        case .shellScript: return "Shell script"
        case .intuneSync: return "Intune synchronization"
        case .waitCondition: return "Wait condition"
        case .configurationValidation: return "Configuration validation"
        case .finalValidation: return "Final validation"
        }
    }
}
