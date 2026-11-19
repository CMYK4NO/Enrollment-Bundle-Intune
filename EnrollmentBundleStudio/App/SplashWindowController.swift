import AppKit
import SwiftUI

/// Shows a short splash screen at launch.
///
/// The splash is a separate borderless window. It shows an image only: no network access, no file access.
/// If the image is missing, nothing is shown and the app carries on.
@MainActor
final class SplashWindowController {
    static let size = NSSize(width: 800, height: 450)
    static let displayDuration: TimeInterval = 2.5
    static let fadeDuration: TimeInterval = 0.35
    static let imageName = "SplashImage"

    /// Called when the splash is gone.
    var onFinished: (() -> Void)?

    private(set) var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    /// The splash frame, centred in the usable area of a screen (without the menu bar and the Dock).
    static func frame(centeredIn visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: (visibleFrame.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// Returns false when there is no image, in which case no splash is shown.
    @discardableResult
    func show() -> Bool {
        guard window == nil else { return true }
        guard NSImage(named: Self.imageName) != nil else { return false }

        let hosting = NSHostingView(rootView: SplashView())
        hosting.frame = NSRect(origin: .zero, size: Self.size)

        let splash = SplashWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        splash.contentView = hosting
        splash.isOpaque = false
        splash.backgroundColor = .clear
        splash.hasShadow = true
        splash.level = .floating
        splash.isReleasedWhenClosed = false
        splash.isMovableByWindowBackground = false
        splash.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        splash.setAccessibilityLabel("\(AppInfo.displayName) splash screen")
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            splash.setFrame(Self.frame(centeredIn: screen.visibleFrame), display: false)
        } else {
            splash.center()
        }
        window = splash
        splash.makeKeyAndOrderFront(nil)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.displayDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
        return true
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let splash = window else { return }
        window = nil

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            splash.orderOut(nil)
            onFinished?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            splash.animator().alphaValue = 0
        }, completionHandler: {
            splash.orderOut(nil)
            Task { @MainActor [weak self] in self?.onFinished?() }
        })
    }
}

/// Borderless windows cannot become key by default. The splash takes the keyboard and swallows key presses.
final class SplashWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {}
}

private struct SplashView: View {
    var body: some View {
        Image(SplashWindowController.imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: SplashWindowController.size.width, height: SplashWindowController.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("macOS Enrollment Bundle Studio")
    }
}
