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

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(SidebarSection.allCases) { section in
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
