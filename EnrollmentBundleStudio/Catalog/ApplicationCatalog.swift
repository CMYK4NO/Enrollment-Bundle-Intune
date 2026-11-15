import Foundation

/// Describes how to detect and display a well-known application.
/// The catalogue never downloads or redistributes software; Intune remains the delivery system.
struct CatalogEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    let category: String
    let applicationPath: String
    let bundleIdentifier: String
    let processName: String
    let defaultTimeoutSeconds: Int
    let suggestedValidation: ValidationMethod
    let defaultRequired: Bool
    let symbolName: String
    let notes: String
    /// Name (without extension) of an .icns file shipped in the app bundle. When set, adding the entry copies it
    /// into the project's Icons folder and uses it as the application icon.
    var bundledIconResource: String? = nil

    func makeApplicationItem(taskIdentifier: String, strategy: ApplicationInstallStrategy) -> ApplicationItem {
        var execution = TaskExecutionOptions()
        execution.isRequired = defaultRequired
        execution.timeoutSeconds = defaultTimeoutSeconds
        execution.messages = .standard
        return ApplicationItem(
            id: UUID(),
            taskIdentifier: taskIdentifier,
            catalogID: id,
            displayName: displayName,
            applicationPath: applicationPath,
            bundleIdentifier: bundleIdentifier,
            processName: processName,
            icon: IconSource(kind: .applicationBundle, value: ""),
            detection: TaskCheck(method: suggestedValidation, value: ""),
            installStrategy: strategy,
            isEnabled: true,
            execution: execution
        )
    }
}

/// Built-in catalogue. Verify paths and bundle identifiers against your own fleet before relying on them;
/// vendors occasionally rename apps or change identifiers.
enum ApplicationCatalog {
    static let entries: [CatalogEntry] = [
        CatalogEntry(
            id: "company-portal", displayName: "Microsoft Company Portal", category: "Device Management",
            applicationPath: "/Applications/Company Portal.app", bundleIdentifier: "com.microsoft.CompanyPortalMac",
            processName: "Company Portal", defaultTimeoutSeconds: 900, suggestedValidation: .bundleIdentifier,
            defaultRequired: true, symbolName: "building.columns",
            notes: "Required for Intune user enrollment and Platform SSO registration."
        ),
        CatalogEntry(
            id: "microsoft-defender", displayName: "Microsoft Defender", category: "Security Tools",
            applicationPath: "/Applications/Microsoft Defender.app", bundleIdentifier: "com.microsoft.wdav",
            processName: "wdavdaemon", defaultTimeoutSeconds: 1800, suggestedValidation: .bundleIdentifier,
            defaultRequired: true, symbolName: "shield.lefthalf.filled",
            notes: "Deploy the system extension, network filter and full disk access profiles before the app."
        ),
        CatalogEntry(
            id: "microsoft-edge", displayName: "Microsoft Edge", category: "Browsers",
            applicationPath: "/Applications/Microsoft Edge.app", bundleIdentifier: "com.microsoft.edgemac",
            processName: "Microsoft Edge", defaultTimeoutSeconds: 1200, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "globe",
            notes: "Can be deployed with the Intune built-in Microsoft Edge app type."
        ),
        CatalogEntry(
            id: "microsoft-365", displayName: "Microsoft 365 and Office", category: "Microsoft 365",
            applicationPath: "/Applications/Microsoft Word.app", bundleIdentifier: "com.microsoft.Word",
            processName: "Microsoft Word", defaultTimeoutSeconds: 3600, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "square.grid.2x2",
            notes: "One row for the whole suite, detected through Microsoft Word. Large download; allow a generous timeout.",
            bundledIconResource: "Microsoft365"
        ),
        CatalogEntry(
            id: "visual-studio-code", displayName: "Visual Studio Code", category: "Developer Tools",
            applicationPath: "/Applications/Visual Studio Code.app", bundleIdentifier: "com.microsoft.VSCode",
            processName: "", defaultTimeoutSeconds: 1200, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "chevron.left.forwardslash.chevron.right",
            notes: "Usually optional and limited to developer groups."
        ),
        CatalogEntry(
            id: "google-chrome", displayName: "Google Chrome", category: "Browsers",
            applicationPath: "/Applications/Google Chrome.app", bundleIdentifier: "com.google.Chrome",
            processName: "Google Chrome", defaultTimeoutSeconds: 1200, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "globe",
            notes: "Use the enterprise installer package when deploying through Intune."
        ),
        CatalogEntry(
            id: "mozilla-firefox", displayName: "Firefox", category: "Browsers",
            applicationPath: "/Applications/Firefox.app", bundleIdentifier: "org.mozilla.firefox",
            processName: "firefox", defaultTimeoutSeconds: 1200, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "flame",
            notes: "Use the vendor's installer package when deploying through Intune."
        ),
        CatalogEntry(
            id: "slack", displayName: "Slack", category: "Collaboration",
            applicationPath: "/Applications/Slack.app", bundleIdentifier: "com.tinyspeck.slackmacgap",
            processName: "Slack", defaultTimeoutSeconds: 1200, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "bubble.left.and.bubble.right",
            notes: "Use the vendor's installer package, or the Mac App Store build (different bundle identifier), when deploying through Intune."
        ),
        CatalogEntry(
            id: "zoom", displayName: "Zoom.us", category: "Collaboration",
            applicationPath: "/Applications/zoom.us.app", bundleIdentifier: "us.zoom.xos",
            processName: "zoom.us", defaultTimeoutSeconds: 1200, suggestedValidation: .bundleIdentifier,
            defaultRequired: false, symbolName: "video",
            notes: "Use the Zoom Workplace installer package from the Zoom download center."
        )
    ]

    /// Categories in catalogue order.
    static var categories: [String] {
        var ordered: [String] = []
        for entry in entries where !ordered.contains(entry.category) {
            ordered.append(entry.category)
        }
        return ordered
    }

    static func entry(id: String) -> CatalogEntry? {
        entries.first { $0.id == id }
    }

    static func entries(inCategory category: String) -> [CatalogEntry] {
        entries.filter { $0.category == category }
    }

    static func symbol(forCategory category: String) -> String {
        switch category {
        case "Device Management": return "gearshape.2"
        case "Security Tools": return "lock.shield"
        case "Microsoft 365": return "square.grid.2x2"
        case "Browsers": return "globe"
        case "Collaboration": return "person.2"
        case "Developer Tools": return "hammer"
        default: return "folder"
        }
    }
}
