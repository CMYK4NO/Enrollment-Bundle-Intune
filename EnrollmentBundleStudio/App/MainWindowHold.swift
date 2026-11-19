import AppKit

/// Keeps the document windows invisible and inert from launch until the splash has finished.
///
/// Windows are caught on their first update, before they are drawn. A held window that becomes key hands the
/// keyboard back to the window in front (the splash), so nothing can be typed into the window behind it.
/// A launch Open panel is cancelled; the app opens a new project after the splash instead.
@MainActor
final class MainWindowHold: NSObject {
    private let held = NSHashTable<NSWindow>.weakObjects()
    private let front: () -> NSWindow?

    init(front: @escaping () -> NSWindow?) {
        self.front = front
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowUpdated(_:)), name: NSWindow.didUpdateNotification, object: nil)
        center.addObserver(self, selector: #selector(windowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        NSApp.windows.forEach(holdIfNeeded)
    }

    @objc private func windowUpdated(_ notification: Notification) {
        if let window = notification.object as? NSWindow { holdIfNeeded(window) }
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, held.contains(window) else { return }
        front()?.makeKey()
    }

    private func holdIfNeeded(_ window: NSWindow) {
        if let panel = window as? NSOpenPanel {
            panel.cancel(nil)
            return
        }
        guard window.canBecomeMain, !(window is NSPanel), !(window is SplashWindow),
              !held.contains(window) else { return }
        held.add(window)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    /// Reveals the held windows and stops watching for new ones.
    func release() {
        NotificationCenter.default.removeObserver(self)
        let windows = held.allObjects
        held.removeAllObjects()
        for window in windows {
            window.alphaValue = 1
            window.ignoresMouseEvents = false
        }
        windows.first { $0.isVisible && !$0.isMiniaturized }?.makeKeyAndOrderFront(nil)
    }
}
