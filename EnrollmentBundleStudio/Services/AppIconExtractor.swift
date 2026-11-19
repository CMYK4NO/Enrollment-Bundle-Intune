import AppKit
import Foundation

/// Reads the icon of an application installed on this Mac and renders it as a PNG, so the icon can travel inside
/// the project. Only the icons of apps the administrator already has are used; nothing is downloaded.
enum AppIconExtractor {
    static let pixelSize = 256

    /// The icon of the app bundle at `path` as PNG data, or nil when no app bundle exists there.
    /// The folder is checked first because NSWorkspace returns a generic icon for a path that does not exist.
    static func applicationIconPNG(atPath path: String) -> Data? {
        guard path.hasPrefix("/"), path.hasSuffix(".app") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return renderPNG(NSWorkspace.shared.icon(forFile: path), pixelSize: pixelSize)
    }

    /// Draws `image` into a square RGBA bitmap and encodes it as PNG.
    static func renderPNG(_ image: NSImage, pixelSize: Int) -> Data? {
        guard pixelSize > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }
        bitmap.size = NSSize(width: pixelSize, height: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill(using: .copy)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
