import Foundation

/// Destination for applications added from the catalogue.
enum CatalogTarget: Hashable {
    /// Put each entry into a group named after its catalogue category, creating groups as needed.
    case categoryGroups
    case group(UUID)
}

extension EnrollmentProject {
    // MARK: Queries

    var allApplications: [ApplicationItem] {
        applicationGroups.flatMap { $0.applications }
    }

    var allTaskIdentifiers: Set<String> {
        var identifiers = Set<String>()
        for group in applicationGroups {
            for application in group.applications {
                identifiers.insert(application.taskIdentifier)
            }
        }
        for script in scripts {
            identifiers.insert(script.taskIdentifier)
        }
        for task in systemTasks {
            identifiers.insert(task.taskIdentifier)
        }
        return identifiers
    }

    /// Every asset path the project currently references.
    var referencedAssetPaths: Set<String> {
        var paths = Set<String>()
        if let logo = branding.logoPath { paths.insert(logo) }
        if let banner = branding.bannerPath { paths.insert(banner) }
        if let overlay = branding.overlayIconPath { paths.insert(overlay) }
        for application in allApplications where application.icon.kind == .projectAsset {
            paths.insert(application.icon.value)
        }
        for task in systemTasks where task.icon.kind == .projectAsset {
            paths.insert(task.icon.value)
        }
        for script in scripts where !script.relativePath.isEmpty {
            paths.insert(script.relativePath)
        }
        return paths
    }

    /// Installer packages referenced by applications. Kept apart from `referencedAssetPaths`
    /// because packages are large and are not part of configuration exports.
    var referencedInstallerPaths: Set<String> {
        Set(allApplications.compactMap { $0.installer?.relativePath })
    }

    func uniqueTaskIdentifier(for displayName: String, prefix: String) -> String {
        let slug = FilenameSanitizer.slug(displayName)
        let base = "\(prefix).\(slug.isEmpty ? "item" : slug)"
        let existing = allTaskIdentifiers
        guard existing.contains(base) else { return base }
        var counter = 2
        while existing.contains("\(base)-\(counter)") {
            counter += 1
        }
        return "\(base)-\(counter)"
    }

    func uniqueGroupName(_ base: String) -> String {
        let names = Set(applicationGroups.map { $0.name })
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    func groupIndex(id: UUID) -> Int? {
        applicationGroups.firstIndex { $0.id == id }
    }

    func group(id: UUID) -> ApplicationGroup? {
        applicationGroups.first { $0.id == id }
    }

    func location(ofApplication id: UUID) -> (group: Int, item: Int)? {
        for (groupIndex, group) in applicationGroups.enumerated() {
            if let itemIndex = group.applications.firstIndex(where: { $0.id == id }) {
                return (groupIndex, itemIndex)
            }
        }
        return nil
    }

    func application(id: UUID) -> ApplicationItem? {
        guard let found = location(ofApplication: id) else { return nil }
        return applicationGroups[found.group].applications[found.item]
    }

    func containsCatalogEntry(_ catalogID: String) -> Bool {
        allApplications.contains { $0.catalogID == catalogID }
    }

    // MARK: Groups

    @discardableResult
    mutating func addGroup(named name: String, symbolName: String = "folder") -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = ApplicationGroup(
            id: UUID(),
            name: uniqueGroupName(trimmed.isEmpty ? "New Group" : trimmed),
            symbolName: symbolName,
            isRequired: false,
            displayBehavior: .individualItems,
            applications: []
        )
        applicationGroups.append(group)
        return group.id
    }

    mutating func renameGroup(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groupIndex(id: id) else { return }
        applicationGroups[index].name = trimmed
    }

    mutating func updateGroup(_ group: ApplicationGroup) {
        guard let index = groupIndex(id: group.id) else { return }
        applicationGroups[index] = group
    }

    /// Moves a group up (negative offset) or down (positive offset).
    mutating func moveGroup(id: UUID, by offset: Int) {
        guard let index = groupIndex(id: id) else { return }
        let target = index + offset
        guard target >= 0, target < applicationGroups.count, target != index else { return }
        let group = applicationGroups.remove(at: index)
        applicationGroups.insert(group, at: target)
    }

    /// Removes a group and drops dependency references to its applications.
    @discardableResult
    mutating func removeGroup(id: UUID) -> ApplicationGroup? {
        guard let index = groupIndex(id: id) else { return nil }
        let removed = applicationGroups.remove(at: index)
        removeDependencyReferences(to: Set(removed.applications.map { $0.taskIdentifier }))
        return removed
    }

    // MARK: Applications

    mutating func addApplication(_ application: ApplicationItem, toGroup groupID: UUID) {
        guard let index = groupIndex(id: groupID) else { return }
        applicationGroups[index].applications.append(application)
    }

    /// Replaces the application with the same id and returns the previous value.
    @discardableResult
    mutating func updateApplication(_ application: ApplicationItem) -> ApplicationItem? {
        guard let found = location(ofApplication: application.id) else { return nil }
        let previous = applicationGroups[found.group].applications[found.item]
        applicationGroups[found.group].applications[found.item] = application
        return previous
    }

    /// Removes an application and drops dependency references to it.
    @discardableResult
    mutating func removeApplication(id: UUID) -> ApplicationItem? {
        guard let found = location(ofApplication: id) else { return nil }
        let removed = applicationGroups[found.group].applications.remove(at: found.item)
        removeDependencyReferences(to: [removed.taskIdentifier])
        return removed
    }

    /// Moves an application to the end of another group.
    mutating func moveApplication(id: UUID, toGroup groupID: UUID) {
        guard let destination = groupIndex(id: groupID),
              let found = location(ofApplication: id),
              found.group != destination else {
            return
        }
        let application = applicationGroups[found.group].applications.remove(at: found.item)
        applicationGroups[destination].applications.append(application)
    }

    mutating func moveApplications(inGroup groupID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let index = groupIndex(id: groupID) else { return }
        applicationGroups[index].applications.moveElements(fromOffsets: source, toOffset: destination)
    }

    /// Adds catalogue entries, skipping entries already present. Returns the number added.
    @discardableResult
    mutating func addCatalogEntries(_ entries: [CatalogEntry], target: CatalogTarget) -> Int {
        var added = 0
        for entry in entries where !containsCatalogEntry(entry.id) {
            let groupID: UUID
            switch target {
            case .group(let id):
                guard groupIndex(id: id) != nil else { continue }
                groupID = id
            case .categoryGroups:
                if let existing = applicationGroups.first(where: { $0.name == entry.category }) {
                    groupID = existing.id
                } else {
                    groupID = addGroup(named: entry.category, symbolName: ApplicationCatalog.symbol(forCategory: entry.category))
                }
            }
            let item = entry.makeApplicationItem(
                taskIdentifier: uniqueTaskIdentifier(for: entry.displayName, prefix: "app"),
                strategy: settings.applicationInstallStrategy
            )
            addApplication(item, toGroup: groupID)
            added += 1
        }
        return added
    }
}
