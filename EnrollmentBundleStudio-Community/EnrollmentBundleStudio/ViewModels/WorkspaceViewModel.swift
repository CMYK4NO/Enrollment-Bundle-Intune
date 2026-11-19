import SwiftUI

enum PreviewDeviceSource: String, CaseIterable, Identifiable {
    case sample
    case thisMac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sample: return "Sample values"
        case .thisMac: return "This Mac"
        }
    }
}

enum PreviewAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A parsed configuration waiting for the administrator's review.
struct PendingImport: Identifiable {
    let id = UUID()
    let fileName: String
    let result: ConfigurationImportResult
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// One-shot actions that a menu command or button asks a view to perform, such as opening a sheet.
enum WorkspaceRequest: Hashable {
    case catalog
    case exportConfiguration
    case importConfiguration
    case duplicateProject
}

/// Per-window UI state that is not part of the saved project.
///
/// Rules that keep SwiftUI's "Publishing changes from within view updates" warning away:
/// - Selection, presentation flags and filters live in the owning view as @State, not here.
/// - Menu commands call `request(_:)`. The target view handles it in `.task(id:)`, which runs after the
///   view update, and calls `consume(_:)` so each request is handled exactly once.
/// - Every published property below only publishes when its value actually changes, because SwiftUI
///   controls sometimes write an unchanged value back during an update.
@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published private var collapsedGroupStorage: Set<UUID> = []
    @Published private var previewScenarioStorage: PreviewScenario = .inProgress
    @Published private var previewDeviceSourceStorage: PreviewDeviceSource = .sample
    @Published private var previewAppearanceStorage: PreviewAppearance = .system
    @Published private var previewOverrideStorage: [String: TaskStatus] = [:]
    @Published private var alertStorage: AppAlert?
    @Published private var requestCounts: [WorkspaceRequest: Int] = [:]
    @Published private var navigationCount = 0
    /// Not published: read once by ContentView when it handles a navigation request.
    private var navigationTarget: SidebarSection = .overview
    private var handledNavigationCount = 0
    /// Not published: consuming a request must never trigger a view update by itself.
    private var handledCounts: [WorkspaceRequest: Int] = [:]

    var collapsedGroupIDs: Set<UUID> {
        get { collapsedGroupStorage }
        set { if newValue != collapsedGroupStorage { collapsedGroupStorage = newValue } }
    }

    /// Changing the scenario clears simulated per-item statuses.
    var previewScenario: PreviewScenario {
        get { previewScenarioStorage }
        set {
            guard newValue != previewScenarioStorage else { return }
            previewScenarioStorage = newValue
            previewStatusOverrides = [:]
        }
    }

    var previewDeviceSource: PreviewDeviceSource {
        get { previewDeviceSourceStorage }
        set { if newValue != previewDeviceSourceStorage { previewDeviceSourceStorage = newValue } }
    }

    var previewAppearance: PreviewAppearance {
        get { previewAppearanceStorage }
        set { if newValue != previewAppearanceStorage { previewAppearanceStorage = newValue } }
    }

    var previewStatusOverrides: [String: TaskStatus] {
        get { previewOverrideStorage }
        set { if newValue != previewOverrideStorage { previewOverrideStorage = newValue } }
    }

    var alert: AppAlert? {
        get { alertStorage }
        set { if newValue?.id != alertStorage?.id { alertStorage = newValue } }
    }

    // MARK: Requests

    func request(_ request: WorkspaceRequest) {
        requestCounts[request, default: 0] += 1
    }

    /// Use as the `id` of `.task(id:)` in the view that handles the request.
    func requestCount(_ request: WorkspaceRequest) -> Int {
        requestCounts[request] ?? 0
    }

    /// Returns true once for each request made, false when there is nothing new to handle.
    func consume(_ request: WorkspaceRequest) -> Bool {
        let requested = requestCounts[request] ?? 0
        guard requested > (handledCounts[request] ?? 0) else { return false }
        handledCounts[request] = requested
        return true
    }

    // MARK: Navigation

    /// Asks the window to show a section. Used by menu commands, which reach this object reliably
    /// through focusedSceneValue even while a menu is being tracked.
    func navigate(to section: SidebarSection) {
        navigationTarget = section
        navigationCount += 1
    }

    /// Use as the `id` of `.task(id:)` in ContentView.
    var navigationRequestID: Int { navigationCount }

    /// Returns the requested section once per request.
    func consumeNavigation() -> SidebarSection? {
        guard navigationCount > handledNavigationCount else { return nil }
        handledNavigationCount = navigationCount
        return navigationTarget
    }

    // MARK: Helpers

    func present(_ error: Error, title: String) {
        let message: String
        if let localized = error as? LocalizedError {
            message = [localized.errorDescription, localized.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: "\n\n")
        } else {
            message = error.localizedDescription
        }
        alert = AppAlert(title: title, message: message.isEmpty ? error.localizedDescription : message)
    }

    func toggleCollapsed(_ groupID: UUID) {
        if collapsedGroupIDs.contains(groupID) {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
    }

    /// Sets (or clears, when status is nil) a simulated status for the given task identifiers.
    func setPreviewStatus(_ status: TaskStatus?, for taskIdentifiers: [String]) {
        var overrides = previewStatusOverrides
        for identifier in taskIdentifiers {
            if let status {
                overrides[identifier] = status
            } else {
                overrides.removeValue(forKey: identifier)
            }
        }
        previewStatusOverrides = overrides
    }
}
