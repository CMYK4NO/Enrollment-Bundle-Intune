import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Editor for the Dock that is set up on the Mac after a successful enrollment.
struct DockView: View {
    @Binding var document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel
    @State private var manualPath = ""
    @State private var manualLabel = ""
    @State private var selectedItemID: UUID?

    private var dock: Binding<DockConfiguration> {
        Binding(
            get: { document.project.dock ?? .standard },
            set: { document.project.dock = $0 }
        )
    }

    private var current: DockConfiguration { document.project.dock ?? .standard }

    private var applications: [ApplicationItem] {
        document.project.allApplications.filter { $0.isEnabled }
    }

    private var resolved: [ResolvedDockItem] { current.resolvedItems(in: document.project) }

    var body: some View {
        Form {
            Section("Dock") {
                Toggle("Customize the Dock after enrollment", isOn: dock.isEnabled.deferringWrites())
                Toggle("Remove default items", isOn: dock.removeDefaultItems.deferringWrites())
                    .disabled(!current.isEnabled)
                Text(current.removeDefaultItems
                     ? "The Dock shows only the apps below. Folders such as Downloads and the Trash are not touched."
                     : "The apps below are added to the Dock the user already has. Apps that are already in it are not added twice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The Dock is set up once, on the Mac, after the enrollment finishes successfully or with warnings. A Dock the user changes afterwards is not replaced on later runs; changing anything on this page applies the new Dock once. Apps that are not installed at that time are skipped. Nothing runs while you edit or preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                dockStrip
            }

            Section("Add apps") {
                HStack {
                    Menu("Project apps") {
                        if applications.isEmpty {
                            Text("No applications in the project")
                        } else {
                            Button("Add all (\(applications.count))") {
                                dock.wrappedValue.addProjectApplications(applications)
                            }
                            Divider()
                            ForEach(applications) { application in
                                Button(application.displayName) {
                                    dock.wrappedValue.addProjectApplication(application)
                                }
                                .disabled(current.containsProjectApplication(application.taskIdentifier))
                            }
                        }
                    }
                    .fixedSize()
                    Menu("macOS apps") {
                        ForEach(DockSystemApplications.entries) { entry in
                            Button(entry.label) {
                                dock.wrappedValue.addApplication(label: entry.label, path: entry.path, source: .system)
                            }
                            .disabled(current.containsPath(entry.path))
                        }
                    }
                    .fixedSize()
                    Spacer()
                }
                HStack {
                    TextField("Application path", text: $manualPath, prompt: Text(verbatim: "/Applications/Example.app"))
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") { Task { await chooseApplication() } }
                }
                TextField("Name in the Dock (optional)", text: $manualLabel)
                HStack {
                    Spacer()
                    Button("Add") { addManual() }
                        .disabled(!DockConfiguration.isValidApplicationPath(manualPath))
                }
                if !manualPath.isEmpty && !DockConfiguration.isValidApplicationPath(manualPath) {
                    FieldIssueLabel(message: "Enter the full path of an application, for example /Applications/Example.app.", severity: .error)
                }
                Text("Choosing an app only reads its name and location. The path is the one on the managed Macs, so an app that is not on this Mac can be typed in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apps in the Dock (\(current.items.count))") {
                if current.items.isEmpty {
                    Text("No apps yet. Add apps above.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selectedItemID) {
                        ForEach(current.items) { item in
                            itemRow(item)
                                .tag(item.id)
                        }
                        .onMove { source, destination in
                            dock.wrappedValue.items.moveElements(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .frame(height: min(max(CGFloat(current.items.count) * 44 + 8, 90), 360))
                    Text("Drag to reorder. The first app is the leftmost (or topmost) in the Dock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Picker("Position", selection: dock.position.deferringWrites()) {
                    ForEach(DockPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                Stepper(value: dock.tileSize.deferringWrites(), in: DockConfiguration.tileSizeRange, step: 2) {
                    LabeledContent("Icon size", value: "\(current.tileSize) pt")
                }
                Toggle("Hide and show the Dock automatically", isOn: dock.autoHide.deferringWrites())
            }
            .disabled(!current.isEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Dock")
    }

    // MARK: Preview strip

    private var dockStrip: some View {
        let items = current.items
        return ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if items.isEmpty {
                    Text("The Dock will be empty of apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    VStack(spacing: 2) {
                        iconView(for: item, size: 40)
                        Text(displayName(of: item))
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: 56)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .opacity(current.isEnabled ? 1 : 0.5)
        .accessibilityLabel("Dock preview")
    }

    // MARK: Rows

    @ViewBuilder
    private func itemRow(_ item: DockItem) -> some View {
        let linked = linkedApplication(of: item)
        let path = effectivePath(of: item)
        HStack(spacing: 10) {
            iconView(for: item, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(of: item))
                Text(path.isEmpty ? "No path" : path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.applicationTaskIdentifier != nil && linked == nil {
                Label("App removed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !DockConfiguration.isValidApplicationPath(path) {
                Label("Invalid path", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                remove(item)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove from the Dock")
            .accessibilityLabel("Remove \(displayName(of: item)) from the Dock")
        }
        .contextMenu {
            Button("Move Up") { move(item, by: -1) }
                .disabled(current.items.first?.id == item.id)
            Button("Move Down") { move(item, by: 1) }
                .disabled(current.items.last?.id == item.id)
            Divider()
            Button("Remove", role: .destructive) { remove(item) }
        }
    }

    private func linkedApplication(of item: DockItem) -> ApplicationItem? {
        guard let identifier = item.applicationTaskIdentifier else { return nil }
        return document.project.allApplications.first { $0.taskIdentifier == identifier }
    }

    private func effectivePath(of item: DockItem) -> String {
        (linkedApplication(of: item)?.applicationPath ?? item.path).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayName(of item: DockItem) -> String {
        let name = (linkedApplication(of: item)?.displayName ?? item.label).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return ((effectivePath(of: item) as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    @ViewBuilder
    private func iconView(for item: DockItem, size: CGFloat) -> some View {
        if let application = linkedApplication(of: item) {
            IconSourceImage(icon: application.icon, applicationPath: application.applicationPath, assets: document.assets, size: size)
        } else {
            IconSourceImage(icon: IconSource(kind: .applicationBundle, value: ""), applicationPath: effectivePath(of: item), assets: [:], size: size)
        }
    }

    // MARK: Actions

    private func remove(_ item: DockItem) {
        dock.wrappedValue.items.removeAll { $0.id == item.id }
    }

    private func move(_ item: DockItem, by offset: Int) {
        var items = dock.wrappedValue.items
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + offset
        guard target >= 0, target < items.count else { return }
        items.swapAt(index, target)
        dock.wrappedValue.items = items
    }

    private func addManual() {
        let label = manualLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if dock.wrappedValue.addApplication(label: label, path: manualPath, source: .manual) {
            manualPath = ""
            manualLabel = ""
        } else {
            workspace.alert = AppAlert(title: "Not added", message: "That application is already in the Dock list, or its path is not valid.")
        }
    }

    private func chooseApplication() async {
        let urls = await FilePanels.openFiles(title: "Choose an application", allowedContentTypes: [.applicationBundle])
        guard let url = urls.first else { return }
        manualPath = url.path
        if manualLabel.isEmpty {
            manualLabel = url.deletingPathExtension().lastPathComponent
        }
    }
}
