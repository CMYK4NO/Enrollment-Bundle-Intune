import AppKit
import SwiftUI

/// Thumbnail with Choose and Remove buttons for a branding image.
struct ImageAssetRow: View {
    let title: String
    let path: String?
    let data: Data?
    let recommendation: String
    let onChoose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(path ?? "Not set")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if path != nil && data == nil {
                    FieldIssueLabel(message: "File is missing from the project.", severity: .error)
                } else {
                    Text(recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Choose…", action: onChoose)
                .accessibilityLabel("Choose \(title)")
            Button("Remove", action: onRemove)
                .disabled(path == nil)
                .accessibilityLabel("Remove \(title)")
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityLabel("\(title) thumbnail")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                .accessibilityHidden(true)
        }
    }
}
