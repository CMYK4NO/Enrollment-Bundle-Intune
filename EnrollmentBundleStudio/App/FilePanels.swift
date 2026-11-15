import AppKit
import UniformTypeIdentifiers

/// Open and save panels built on NSOpenPanel and NSSavePanel.
///
/// SwiftUI's fileImporter and fileExporter can silently fail to appear when a window contains more than
/// one of them, so the app uses AppKit panels directly. They attach as a sheet to the key window when there
/// is one. Panels only return URLs the user chose; nothing is read or written here.
@MainActor
enum FilePanels {
    static func openFiles(
        title: String,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = false
    ) async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        if !allowedContentTypes.isEmpty {
            panel.allowedContentTypes = allowedContentTypes
        }
        return await present(panel) == .OK ? panel.urls : []
    }

    static func openDirectory(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return await present(panel) == .OK ? panel.url : nil
    }

    /// The panel itself asks before replacing an existing item.
    static func saveLocation(title: String, defaultName: String, contentType: UTType) async -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return await present(panel) == .OK ? panel.url : nil
    }

    // MARK: Content types

    static var shellScriptTypes: [UTType] {
        var types: [UTType] = [.shellScript]
        for fileExtension in ["sh", "zsh"] {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    static var installerPackageTypes: [UTType] {
        var types: [UTType] = []
        if let archive = UTType("com.apple.installer-package-archive") {
            types.append(archive)
        }
        if let byExtension = UTType(filenameExtension: "pkg"), !types.contains(byExtension) {
            types.append(byExtension)
        }
        return types
    }

    /// A visible window that can host a sheet: the key window when it is a normal document window or
    /// one of our sheets, otherwise the main window. On macOS 26 the key window can briefly be a transient
    /// glass window (menus, popovers), which must never get a panel attached.
    private static var hostWindow: NSWindow? {
        func usable(_ window: NSWindow?) -> NSWindow? {
            guard let window, window.isVisible, window.canBecomeMain || window.isSheet else { return nil }
            return window
        }
        return usable(NSApp.keyWindow) ?? usable(NSApp.mainWindow)
    }

    private static func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = hostWindow, window.attachedSheet == nil {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            } else {
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }
        }
    }
}
