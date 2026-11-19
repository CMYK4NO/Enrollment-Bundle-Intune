import CryptoKit
import Foundation

/// Where the Dock sits on the screen.
enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// One application in the Dock.
struct DockItem: Codable, Equatable, Identifiable {
    enum Source: String, Codable {
        /// An application from the project's Applications page.
        case project
        /// A built-in macOS application.
        case system
        /// Any other application, entered by hand.
        case manual
    }

    var id: UUID
    var source: Source
    /// Name shown under the icon on hover. Empty means "use the application's file name".
    var label: String
    /// Absolute path of the .app bundle on the device.
    var path: String
    /// For a project application: its task identifier, so the name and path follow later edits of that application.
    var applicationTaskIdentifier: String?
}

/// A Dock item after project links have been applied: exactly what the device receives.
struct ResolvedDockItem: Equatable {
    let label: String
    let path: String
}

/// The Dock the enrollment sets up once after it succeeds. Stored in project.json as the optional `dock`
/// object, so projects saved before this existed open unchanged.
struct DockConfiguration: Codable, Equatable {
    static let tileSizeRange = 16...128
    static let defaultTileSize = 54

    /// Off leaves the Dock alone, whatever else is set below.
    var isEnabled: Bool
    /// On: the Dock shows only the selected apps. Off: the selected apps are added to the Dock already there.
    var removeDefaultItems: Bool
    var items: [DockItem]
    var autoHide: Bool
    var position: DockPosition
    var tileSize: Int

    static let standard = DockConfiguration(
        isEnabled: false,
        removeDefaultItems: true,
        items: [],
        autoHide: false,
        position: .bottom,
        tileSize: defaultTileSize
    )

    /// True for an absolute path to an application bundle, without control characters or ".." components.
    static func isValidApplicationPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.lowercased().hasSuffix(".app"), trimmed.utf8.count <= 1024 else { return false }
        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return false }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        return !components.contains("..") && components.count >= 2
    }

    /// The items as the device receives them: project links applied, labels filled in, invalid paths and
    /// repeated paths dropped (the first occurrence wins).
    func resolvedItems(in project: EnrollmentProject) -> [ResolvedDockItem] {
        var result: [ResolvedDockItem] = []
        var seen = Set<String>()
        for item in items {
            var label = item.label
            var path = item.path
            if let identifier = item.applicationTaskIdentifier,
               let application = project.allApplications.first(where: { $0.taskIdentifier == identifier }) {
                label = application.displayName
                path = application.applicationPath
            }
            path = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isValidApplicationPath(path), seen.insert(path).inserted else { continue }
            label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty {
                label = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            }
            result.append(ResolvedDockItem(label: label, path: path))
        }
        return result
    }

    /// Identifies this configuration. The device remembers it after applying the Dock, so the Dock is set up
    /// once and a Dock the user rearranges later is not replaced, until a different configuration is shipped.
    func fingerprint(in project: EnrollmentProject) -> String {
        var text = "remove=\(removeDefaultItems ? 1 : 0)\nposition=\(position.rawValue)\nsize=\(tileSize)\nautohide=\(autoHide ? 1 : 0)\n"
        for item in resolvedItems(in: project) {
            text += "item=\(item.label)\t\(item.path)\n"
        }
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Built-in macOS applications offered on the Dock page. Paths are the standard locations; an app that is
/// missing on a Mac (older or newer macOS) is skipped there, never treated as an error.
enum DockSystemApplications {
    struct Entry: Identifiable, Equatable {
        let label: String
        let path: String
        var id: String { path }
    }

    static let entries: [Entry] = [
        Entry(label: "Safari", path: "/Applications/Safari.app"),
        Entry(label: "Mail", path: "/System/Applications/Mail.app"),
        Entry(label: "Calendar", path: "/System/Applications/Calendar.app"),
        Entry(label: "Contacts", path: "/System/Applications/Contacts.app"),
        Entry(label: "Messages", path: "/System/Applications/Messages.app"),
        Entry(label: "FaceTime", path: "/System/Applications/FaceTime.app"),
        Entry(label: "Maps", path: "/System/Applications/Maps.app"),
        Entry(label: "Photos", path: "/System/Applications/Photos.app"),
        Entry(label: "Notes", path: "/System/Applications/Notes.app"),
        Entry(label: "Reminders", path: "/System/Applications/Reminders.app"),
        Entry(label: "Music", path: "/System/Applications/Music.app"),
        Entry(label: "Podcasts", path: "/System/Applications/Podcasts.app"),
        Entry(label: "TV", path: "/System/Applications/TV.app"),
        Entry(label: "Freeform", path: "/System/Applications/Freeform.app"),
        Entry(label: "Calculator", path: "/System/Applications/Calculator.app"),
        Entry(label: "Preview", path: "/System/Applications/Preview.app"),
        Entry(label: "TextEdit", path: "/System/Applications/TextEdit.app"),
        Entry(label: "Terminal", path: "/System/Applications/Utilities/Terminal.app"),
        Entry(label: "Activity Monitor", path: "/System/Applications/Utilities/Activity Monitor.app"),
        Entry(label: "App Store", path: "/System/Applications/App Store.app"),
        Entry(label: "System Settings", path: "/System/Applications/System Settings.app")
    ]
}

// MARK: - Editing

extension DockConfiguration {
    /// True when the Dock already lists this project application.
    func containsProjectApplication(_ taskIdentifier: String) -> Bool {
        items.contains { $0.applicationTaskIdentifier == taskIdentifier }
    }

    /// True when the Dock already lists an item with this path (project links are not followed here).
    func containsPath(_ path: String) -> Bool {
        let wanted = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.contains { $0.applicationTaskIdentifier == nil && $0.path == wanted }
    }

    /// Adds an application from the Applications page. The Dock follows later edits of its name and path.
    /// Returns false when it is already listed.
    @discardableResult
    mutating func addProjectApplication(_ application: ApplicationItem) -> Bool {
        guard !containsProjectApplication(application.taskIdentifier) else { return false }
        items.append(DockItem(
            id: UUID(),
            source: .project,
            label: application.displayName,
            path: application.applicationPath,
            applicationTaskIdentifier: application.taskIdentifier
        ))
        return true
    }

    /// Adds every enabled project application that is not listed yet and returns how many were added.
    @discardableResult
    mutating func addProjectApplications(_ applications: [ApplicationItem]) -> Int {
        var added = 0
        for application in applications where application.isEnabled {
            if addProjectApplication(application) { added += 1 }
        }
        return added
    }

    /// Adds a macOS application or an application chosen by hand. Returns false for an invalid or repeated path.
    @discardableResult
    mutating func addApplication(label: String, path: String, source: DockItem.Source) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidApplicationPath(trimmed), !containsPath(trimmed) else { return false }
        items.append(DockItem(id: UUID(), source: source, label: label, path: trimmed, applicationTaskIdentifier: nil))
        return true
    }
}
