import AppKit
import SwiftUI

/// Launch sequence: splash, then a new project. No project window is visible or usable while the splash is up.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var splash: SplashWindowController?
    private var hold: MainWindowHold?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The unit-test host must not pop up a window.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // Started before the document windows are created, so they can be held back.
        hold = MainWindowHold(front: { [weak self] in self?.splash?.window })
        let controller = SplashWindowController()
        controller.onFinished = { [weak self] in self?.startWorking() }
        splash = controller
        // Without a splash image, start once launch has finished instead of inside it.
        if !controller.show() { Task { @MainActor [weak self] in self?.startWorking() } }
    }

    private func startWorking() {
        hold?.release()
        hold = nil
        openNewDocumentIfNoneOpen()
        startReopeningNewProject()
    }

    /// After a project window closes and no project is left open, starts a new project so the app is never
    /// left without one.
    private func startReopeningNewProject() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // Read now: the window is still attached to its document while it is closing.
        guard let window = notification.object as? NSWindow,
              NSDocumentController.shared.document(for: window) != nil else { return }
        Task { @MainActor [weak self] in
            // Let the close finish first. Opening a saved project replaces an empty one, so look again afterwards.
            // When the app is quitting the process ends before this runs.
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.openNewDocumentIfNoneOpen()
        }
    }

    /// Safety net for the launch behaviour: when no project is open, start a new one.
    private func openNewDocumentIfNoneOpen() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        NSDocumentController.shared.newDocument(nil)
    }
}

@main
struct EnrollmentBundleStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Open a new untitled project at launch instead of the Open panel with its "New Document" button.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    var body: some Scene {
        DocumentGroup(newDocument: EnrollmentProjectDocument(settingsDefaults: AppSettingsStore.shared.load())) { file in
            ContentView(document: file.$document.skippingEqualWrites(), fileURL: file.fileURL)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            StudioCommands()
        }

        Window("Settings", id: SettingsWindow.id) {
            ProjectSettingsWindowView()
        }
        .defaultSize(width: 560, height: 560)
    }
}
