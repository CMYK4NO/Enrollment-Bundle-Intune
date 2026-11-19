import SwiftUI

struct GroupRenameSheet: View {
    let context: GroupRenameContext
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(context: GroupRenameContext, onRename: @escaping (String) -> Void) {
        self.context = context
        self.onRename = onRename
        _name = State(initialValue: context.currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Group")
                .font(.headline)
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    onRename(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
