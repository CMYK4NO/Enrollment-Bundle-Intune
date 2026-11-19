import SwiftUI

struct WorkspaceFocusedValueKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

extension FocusedValues {
    var workspace: WorkspaceViewModel? {
        get { self[WorkspaceFocusedValueKey.self] }
        set { self[WorkspaceFocusedValueKey.self] = newValue }
    }

}

/// Menu bar commands. They act on the frontmost project window.
struct StudioCommands: Commands {
    @FocusedValue(\.workspace) private var workspace: WorkspaceViewModel?
    @FocusedValue(\.settingsContext) private var settingsContext: SettingsContext?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Settings live in the app menu (below About) and open in their own window. Save stores the app-wide defaults
        // and also writes them into the frontmost project.
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Settings…") {
                if let settingsContext {
                    SettingsWindowModel.shared.show(settingsContext)
                }
                openWindow(id: SettingsWindow.id)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Navigate") {
            ForEach(SidebarSection.allCases.filter { $0 != .settings }) { section in
                Button(section.title) {
                    workspace?.navigate(to: section)
                }
                .keyboardShortcut(section.shortcutKey, modifiers: .command)
                .disabled(workspace == nil)
            }
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Add Applications from Catalogue…") {
                workspace?.navigate(to: .applications)
                workspace?.request(.catalog)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(workspace == nil)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Duplicate as New Project…") {
                workspace?.request(.duplicateProject)
            }
            .disabled(workspace == nil)
            Button("Export Configuration…") {
                workspace?.request(.exportConfiguration)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(workspace == nil)
            Button("Import Configuration…") {
                workspace?.request(.importConfiguration)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(workspace == nil)
        }
    }
}
