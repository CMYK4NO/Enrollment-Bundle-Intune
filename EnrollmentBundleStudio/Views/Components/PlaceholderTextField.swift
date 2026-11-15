import SwiftUI

/// Menu that inserts a placeholder token.
struct PlaceholderInsertMenu: View {
    let fieldTitle: String
    let onInsert: (String) -> Void

    var body: some View {
        Menu {
            ForEach(Placeholder.allCases) { placeholder in
                Button("\(placeholder.displayName)   \(placeholder.token)") {
                    onInsert(placeholder.token)
                }
            }
        } label: {
            Label("Insert Placeholder", systemImage: "curlybraces")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Insert a placeholder that is replaced on the device")
        .accessibilityLabel("Insert placeholder into \(fieldTitle)")
    }
}

/// Text field or editor with a placeholder menu and a warning for unrecognized tokens.
/// SwiftUI on macOS 13 does not expose the insertion point, so tokens are appended to the end.
struct PlaceholderTextField: View {
    let title: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                PlaceholderInsertMenu(fieldTitle: title) { token in
                    insert(token)
                }
            }
            if multiline {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 64, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .accessibilityLabel(title)
            } else {
                TextField(title, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title)
            }
            let unknown = PlaceholderResolver.unknownTokens(in: text)
            if !unknown.isEmpty {
                Label("Unrecognized placeholder: \(unknown.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func insert(_ token: String) {
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += token
        } else {
            text += " " + token
        }
    }
}
