import SwiftUI

/// Lets the administrator pick catalogue entries. Entries only describe detection and display;
/// nothing is downloaded.
struct CatalogPickerSheet: View {
    let project: EnrollmentProject
    let onAdd: ([CatalogEntry], CatalogTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var searchText = ""
    @State private var target: CatalogTarget = .categoryGroups

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Application Catalogue")
                    .font(.title2.bold())
                Text("Each entry describes how to detect and display an app. Nothing is downloaded or redistributed; Intune still delivers the software.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Filter", text: $searchText, prompt: Text("Search by name or category"))
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
            }
            .padding(16)

            List {
                ForEach(visibleCategories, id: \.self) { category in
                    Section(category) {
                        ForEach(filteredEntries(in: category)) { entry in
                            CatalogEntryRow(
                                entry: entry,
                                isAdded: project.containsCatalogEntry(entry.id),
                                isSelected: selectionBinding(for: entry.id)
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Picker("Add to", selection: $target) {
                    Text("Groups named by category").tag(CatalogTarget.categoryGroups)
                    ForEach(project.applicationGroups) { group in
                        Text(group.name).tag(CatalogTarget.group(group.id))
                    }
                }
                .frame(maxWidth: 320)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add \(selectedIDs.count) Selected") {
                    let entries = ApplicationCatalog.entries.filter { selectedIDs.contains($0.id) }
                    onAdd(entries, target)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(14)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 640)
    }

    private var visibleCategories: [String] {
        ApplicationCatalog.categories.filter { !filteredEntries(in: $0).isEmpty }
    }

    private func filteredEntries(in category: String) -> [CatalogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ApplicationCatalog.entries(inCategory: category).filter { entry in
            query.isEmpty
                || entry.displayName.localizedCaseInsensitiveContains(query)
                || entry.category.localizedCaseInsensitiveContains(query)
        }
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }
}

private struct CatalogEntryRow: View {
    let entry: CatalogEntry
    let isAdded: Bool
    @Binding var isSelected: Bool
    /// The icon shipped with the app for this entry, if any. Takes the place of the installed app's icon.
    @State private var bundledIcon: Data?

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 10) {
                IconSourceImage(
                    icon: bundledIcon == nil
                        ? IconSource(kind: .applicationBundle, value: "")
                        : IconSource(kind: .projectAsset, value: "bundled"),
                    applicationPath: entry.applicationPath,
                    assets: bundledIcon.map { ["bundled": $0] } ?? [:],
                    size: 28
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.body.weight(.medium))
                        if entry.defaultRequired {
                            Text("Required by default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if isAdded {
                            Text("Already added")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    Text("\(entry.bundleIdentifier)  \(entry.applicationPath)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isAdded)
        .task {
            bundledIcon = CatalogIconLoader.data(for: entry)
        }
        .accessibilityLabel("\(entry.displayName)\(isAdded ? ", already added" : "")")
    }
}
