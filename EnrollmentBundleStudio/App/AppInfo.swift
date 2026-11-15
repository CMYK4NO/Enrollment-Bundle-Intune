import Foundation

/// Static facts about the running application and the project schema it understands.
enum AppInfo {
    static let displayName = "Enrollment Bundle Studio"

    /// Schema version written by this build of the application.
    static let currentSchemaVersion = 4

    /// Oldest schema version this build can open. Versions between this and the current one are migrated.
    static let minimumSupportedSchemaVersion = 1

    /// Highest implementation phase shipped in this build. Sidebar sections from later phases
    /// show an explanatory page instead of an editor.
    static let implementedPhase = 4

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}
