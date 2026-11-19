import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case branding
    case scripts
    case applications
    case execution
    case dock
    case preview
    case validation
    case packageBuilder
    case buildHistory
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .branding: return "Branding"
        case .applications: return "Applications"
        case .scripts: return "Scripts"
        case .execution: return "Execution"
        case .dock: return "Dock"
        case .preview: return "Preview"
        case .validation: return "Validation"
        case .packageBuilder: return "Package Builder"
        case .buildHistory: return "Build History"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .branding: return "paintpalette"
        case .applications: return "app.badge"
        case .scripts: return "terminal"
        case .execution: return "arrow.triangle.branch"
        case .dock: return "dock.rectangle"
        case .preview: return "eye"
        case .validation: return "checkmark.shield"
        case .packageBuilder: return "shippingbox"
        case .buildHistory: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// Implementation phase that delivers the section's editor.
    var availablePhase: Int {
        switch self {
        case .overview, .branding, .applications, .dock, .preview, .settings: return 1
        case .scripts, .execution, .validation: return 2
        case .packageBuilder: return 3
        case .buildHistory: return 4
        }
    }

    var isAvailable: Bool { availablePhase <= AppInfo.implementedPhase }

    var pendingDescription: String {
        switch self {
        case .scripts:
            return "Import .sh and .zsh scripts into the project with SHA-256 hashes, shebang and Bash 3.2 checks. Imported scripts are never executed while editing."
        case .execution:
            return "Arrange task order, parallel groups and dependencies, with detection of circular, missing and disabled dependencies."
        case .validation:
            return "Project-wide checks grouped as errors, warnings and information, with remediation guidance. Errors block building."
        case .packageBuilder:
            return "Build unsigned or signed installer packages with Apple's pkgbuild and productbuild, then verify them."
        case .buildHistory:
            return "Browse previous builds and their reports, including package hashes and signature status."
        case .overview, .branding, .applications, .dock, .preview, .settings:
            return ""
        }
    }

    var shortcutKey: KeyEquivalent {
        let keys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return KeyEquivalent(keys[min(index, keys.count - 1)])
    }
}
