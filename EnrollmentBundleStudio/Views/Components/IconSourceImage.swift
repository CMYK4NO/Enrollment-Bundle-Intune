import AppKit
import SwiftUI

/// Draws an IconSource using only local data: a project image, the icon of an app already installed
/// on this Mac, or an SF Symbol. Falls back to a generic symbol.
struct IconSourceImage: View {
    let icon: IconSource
    let applicationPath: String
    let assets: [String: Data]
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var resolvedImage: NSImage? {
        switch icon.kind {
        case .projectAsset:
            guard let data = assets[icon.value] else { return nil }
            return NSImage(data: data)
        case .applicationBundle:
            guard !applicationPath.isEmpty, FileManager.default.fileExists(atPath: applicationPath) else { return nil }
            return NSWorkspace.shared.icon(forFile: applicationPath)
        case .sfSymbol:
            return NSImage(systemSymbolName: icon.value, accessibilityDescription: nil)
        }
    }

    private var fallbackSymbol: String {
        switch icon.kind {
        case .projectAsset: return "photo"
        case .applicationBundle: return "app.dashed"
        case .sfSymbol: return "questionmark.square.dashed"
        }
    }
}
