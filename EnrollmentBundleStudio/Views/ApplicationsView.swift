import SwiftUI

struct ApplicationEditContext: Identifiable {
    let id = UUID()
    /// Current group, or nil when the new-group option is preselected.
    let groupID: UUID?
    let groups: [GroupChoice]
    let draft: ApplicationItem
    let isNew: Bool
    /// Imported scripts the "Run custom script" strategy can link to.
    var scripts: [ScriptChoice] = []
}

struct ScriptChoice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct GroupRenameContext: Identifiable {
    let id = UUID()
    let groupID: UUID
    let currentName: String
}

/// A file or project data copied into the project when the editor is saved.
struct PendingAsset: Equatable {
    let path: String
    let data: Data
}

/// Application groups and applications, with reordering, moving and catalogue import.
struct ApplicationsView: View {
    @Binding var document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel
    @State private var editContext: ApplicationEditContext?
    @State private var renameContext: GroupRenameContext?
    @State private var pendingRemoval: PendingRemoval?
    @State private var isCatalogPresented = false

    private enum PendingRemoval {
        case group(id: UUID, name: String, applicationCount: Int)
        case application(id: UUID, name: String)

        var title: String {
            switch self {
            case .group(_, let name, _): return "Remove the group \"\(name)\"?"
            case .application(_, let name): return "Remove \"\(name)\"?"
            }
        }

        var message: String {
            switch self {
            case .group(_, _, let count):
                return count == 0
                    ? "The empty group is removed. You can undo this with Edit > Undo."
                    : "The group and its \(count) application(s) are removed from the project. You can undo this with Edit > Undo."
            case .application:
                return "The application is removed from the project. You can undo this with Edit > Undo."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            if document.project.applicationGroups.isEmpty {
                emptyState
            } else {
                groupList
            }
        }
        .task(id: workspace.requestCount(.catalog)) {
            if workspace.consume(.catalog) && !document.isReadOnly {
                isCatalogPresented = true
            }
        }
        .sheet(isPresented: $isCatalogPresented) {
            CatalogPickerSheet(project: document.project) { entries, target in
                document.addCatalogEntries(entries, target: target)
            }
        }
        .sheet(item: $editContext) { context in
            ApplicationEditorSheet(context: context, assets: document.assets) { result in
                save(result, context: context)
            }
        }
        .sheet(item: $renameContext) { context in
            GroupRenameSheet(context: context) { newName in
                document.project.renameGroup(id: context.groupID, to: newName)
            }
        }
        .confirmationDialog(
            pendingRemoval?.title ?? "",
            isPresented: removalPresented,
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("Remove", role: .destructive) {
                performRemoval(removal)
            }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(removal.message)
        }
    }

    // MARK: Subviews

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                isCatalogPresented = true
            } label: {
                Label("Add from Catalogue…", systemImage: "books.vertical")
            }
            Button {
                addCustomApplication(toGroup: nil)
            } label: {
                Label("Add Custom App…", systemImage: "plus")
            }
            Button {
                addGroup()
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
            }
            Spacer()
            Text(summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No application groups")
                .font(.title3.bold())
            Text("Add applications from the catalogue, or create a group for custom applications.")
                .foregroundStyle(.secondary)
            Button("Add from Catalogue…") {
                isCatalogPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var groupList: some View {
        List {
            ForEach(document.project.applicationGroups) { group in
                Section {
                    if !workspace.collapsedGroupIDs.contains(group.id) {
                        if group.applications.isEmpty {
                            Text("No applications in this group.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(group.applications) { application in
                                ApplicationRow(
                                    application: application,
                                    isRequired: group.isRequired || application.execution.isRequired,
                                    requiredByGroup: group.isRequired,
                                    assets: document.assets,
                                    isEnabled: applicationBinding(application, \.isEnabled),
                                    onEdit: { edit(application, in: group) }
                                )
                                .contextMenu {
                                    applicationMenu(application, in: group)
                                }
                            }
                            .onMove { source, destination in
                                document.project.moveApplications(inGroup: group.id, fromOffsets: source, toOffset: destination)
                            }
                        }
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.inset)
    }

    private func groupHeader(_ group: ApplicationGroup) -> some View {
        let isCollapsed = workspace.collapsedGroupIDs.contains(group.id)
        return HStack(spacing: 8) {
            Button {
                workspace.toggleCollapsed(group.id)
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isCollapsed ? "Expand \(group.name)" : "Collapse \(group.name)")

            Image(systemName: group.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(group.name)
                .font(.headline)
            if group.isRequired {
                Text("Required group")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            }
            Text(group.displayBehavior.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(group.applications.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(group.applications.count) applications")
            Menu {
                groupMenu(group)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(group.name)")
        }
        .contextMenu {
            groupMenu(group)
        }
    }

    @ViewBuilder
    private func groupMenu(_ group: ApplicationGroup) -> some View {
        Button("Rename…") {
            renameContext = GroupRenameContext(groupID: group.id, currentName: group.name)
        }
        Button("Add Custom App to Group…") {
            addCustomApplication(toGroup: group.id)
        }
        Divider()
        Toggle("Required Group", isOn: groupBinding(group, \.isRequired).deferringWrites())
        Picker("Display", selection: groupBinding(group, \.displayBehavior).deferringWrites()) {
            ForEach(GroupDisplayBehavior.allCases) { behavior in
                Text(behavior.title).tag(behavior)
            }
        }
        Divider()
        Button("Move Group Up") {
            document.project.moveGroup(id: group.id, by: -1)
        }
        .disabled(document.project.groupIndex(id: group.id) == 0)
        Button("Move Group Down") {
            document.project.moveGroup(id: group.id, by: 1)
        }
        .disabled(document.project.groupIndex(id: group.id) == document.project.applicationGroups.count - 1)
        Divider()
        Button("Remove Group…", role: .destructive) {
            pendingRemoval = .group(id: group.id, name: group.name, applicationCount: group.applications.count)
        }
    }

    @ViewBuilder
    private func applicationMenu(_ application: ApplicationItem, in group: ApplicationGroup) -> some View {
        Button("Edit…") {
            edit(application, in: group)
        }
        Toggle("Required", isOn: applicationBinding(application, \.execution.isRequired).deferringWrites())
            .disabled(group.isRequired)
        Toggle("Enabled", isOn: applicationBinding(application, \.isEnabled).deferringWrites())
        Toggle("Visible in Dialog", isOn: applicationBinding(application, \.execution.isVisible).deferringWrites())
        Menu("Move to Group") {
            ForEach(document.project.applicationGroups.filter { $0.id != group.id }) { target in
                Button(target.name) {
                    document.project.moveApplication(id: application.id, toGroup: target.id)
                }
            }
        }
        .disabled(document.project.applicationGroups.count < 2)
        Divider()
        Button("Remove…", role: .destructive) {
            pendingRemoval = .application(id: application.id, name: application.displayName)
        }
    }

    // MARK: Bindings

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { isPresented in
                if !isPresented { pendingRemoval = nil }
            }
        )
    }

    private func applicationBinding<Value>(_ application: ApplicationItem, _ keyPath: WritableKeyPath<ApplicationItem, Value>) -> Binding<Value> {
        Binding(
            get: { document.project.application(id: application.id)?[keyPath: keyPath] ?? application[keyPath: keyPath] },
            set: { newValue in
                guard var current = document.project.application(id: application.id) else { return }
                current[keyPath: keyPath] = newValue
                document.project.updateApplication(current)
            }
        )
    }

    private func groupBinding<Value>(_ group: ApplicationGroup, _ keyPath: WritableKeyPath<ApplicationGroup, Value>) -> Binding<Value> {
        Binding(
            get: { document.project.group(id: group.id)?[keyPath: keyPath] ?? group[keyPath: keyPath] },
            set: { newValue in
                guard var current = document.project.group(id: group.id) else { return }
                current[keyPath: keyPath] = newValue
                document.project.updateGroup(current)
            }
        )
    }

    // MARK: Actions

    private var summaryText: String {
        let applications = document.project.allApplications
        let enabled = applications.filter { $0.isEnabled }.count
        return "\(document.project.applicationGroups.count) groups, \(enabled) of \(applications.count) apps enabled"
    }

    private var groupChoices: [GroupChoice] {
        document.project.applicationGroups.map { GroupChoice(id: $0.id, name: $0.name, isRequired: $0.isRequired) }
    }

    private var scriptChoices: [ScriptChoice] {
        document.project.scripts.map { ScriptChoice(id: $0.taskIdentifier, name: $0.displayName) }
    }

    private func edit(_ application: ApplicationItem, in group: ApplicationGroup) {
        editContext = ApplicationEditContext(groupID: group.id, groups: groupChoices, draft: application, isNew: false, scripts: scriptChoices)
    }

    /// Custom apps default to an existing "Custom Applications" group, then to the first group that is
    /// not required, and otherwise to a new optional group created only when the editor is saved.
    private func preferredCustomGroupID() -> UUID? {
        let groups = document.project.applicationGroups
        if let custom = groups.first(where: { $0.name == ApplicationEditorSheet.newGroupName }) {
            return custom.id
        }
        return groups.first(where: { !$0.isRequired })?.id
    }

    private func addGroup() {
        let id = document.project.addGroup(named: "New Group")
        if let group = document.project.group(id: id) {
            renameContext = GroupRenameContext(groupID: id, currentName: group.name)
        }
    }

    private func addCustomApplication(toGroup groupID: UUID?) {
        let draft = ApplicationItem.makeCustom(
            strategy: document.project.settings.applicationInstallStrategy,
            timeoutSeconds: document.project.settings.defaultTaskTimeoutSeconds
        )
        editContext = ApplicationEditContext(
            groupID: groupID ?? preferredCustomGroupID(),
            groups: groupChoices,
            draft: draft,
            isNew: true,
            scripts: scriptChoices
        )
    }

    /// Applies an editor result as one change, so it is a single undo step.
    private func save(_ result: ApplicationEditResult, context: ApplicationEditContext) {
        var updated = document
        do {
            if let pendingIcon = result.pendingIcon {
                try updated.setAsset(pendingIcon.data, at: pendingIcon.path)
            }
            let targetGroupID = result.groupID ?? updated.project.addGroup(named: result.newGroupName, symbolName: "shippingbox")
            var item = result.item
            var previous: ApplicationItem?
            if context.isNew {
                item.taskIdentifier = updated.project.uniqueTaskIdentifier(for: item.displayName, prefix: "app")
                updated.project.addApplication(item, toGroup: targetGroupID)
            } else {
                previous = updated.project.updateApplication(item)
                if targetGroupID != context.groupID {
                    updated.project.moveApplication(id: item.id, toGroup: targetGroupID)
                }
            }
            if let pendingInstaller = result.pendingInstaller {
                updated.attachInstaller(pendingInstaller, toApplication: item.id)
            } else if item.installer == nil {
                updated.removeInstallerIfUnreferenced(previous?.installer?.relativePath)
            }
            if let oldIcon = previous?.icon, oldIcon.kind == .projectAsset {
                updated.removeAssetIfUnreferenced(oldIcon.value)
            }
            updated.removeAssetIfUnreferenced(result.pendingIcon?.path)
            document = updated
        } catch {
            workspace.present(error, title: "Could Not Save Application")
        }
    }

    private func performRemoval(_ removal: PendingRemoval) {
        var updated = document
        switch removal {
        case .group(let id, _, _):
            if let removed = updated.project.removeGroup(id: id) {
                for application in removed.applications {
                    if application.icon.kind == .projectAsset {
                        updated.removeAssetIfUnreferenced(application.icon.value)
                    }
                    updated.removeInstallerIfUnreferenced(application.installer?.relativePath)
                }
            }
            workspace.collapsedGroupIDs.remove(id)
        case .application(let id, _):
            if let removed = updated.project.removeApplication(id: id) {
                if removed.icon.kind == .projectAsset {
                    updated.removeAssetIfUnreferenced(removed.icon.value)
                }
                updated.removeInstallerIfUnreferenced(removed.installer?.relativePath)
            }
        }
        document = updated
        pendingRemoval = nil
    }
}
