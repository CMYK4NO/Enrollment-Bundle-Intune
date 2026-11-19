import SwiftUI
import UniformTypeIdentifiers

/// A .enrollmentproject directory package.
///
/// `project` mirrors project.json. `assets` holds the files of the managed folders (Branding, Icons,
/// Scripts) keyed by relative path, so imported files live inside the project instead of being fragile
/// references to their original location. Folders the document does not manage (Templates, Generated,
/// Builds) are preserved untouched on save because writing starts from the existing file wrapper.
/// Where an installer package's bytes come from. Packages can be hundreds of megabytes, so they are
/// never held as Data: either a lazily read file wrapper from the opened project, or the URL the
/// administrator chose, copied into the project on the next save.
struct InstallerSource: Equatable, @unchecked Sendable {
    let wrapper: FileWrapper?
    let sourceURL: URL?

    static func == (lhs: InstallerSource, rhs: InstallerSource) -> Bool {
        lhs.wrapper === rhs.wrapper && lhs.sourceURL == rhs.sourceURL
    }
}

struct EnrollmentProjectDocument: FileDocument, Equatable {
    static var readableContentTypes: [UTType] { [.enrollmentProject] }
    static var writableContentTypes: [UTType] { [.enrollmentProject] }

    var project: EnrollmentProject
    private(set) var assets: [String: Data]
    /// True when the project uses a newer schema; saving is refused so the original is never overwritten.
    private(set) var isReadOnly: Bool
    /// Problems found while opening, shown on the Overview page.
    private(set) var loadNotes: [String]
    /// Set when the project was upgraded from an older schema while opening.
    private(set) var migratedFromVersion: Int?
    private(set) var migrationSummary: [String]
    /// Files written to the package root on the next save if they do not exist yet (migration backups).
    private(set) var pendingRootFiles: [String: Data]
    /// Installer packages keyed by relative path (Installers/<name>.pkg).
    private(set) var installerSources: [String: InstallerSource]

    init(project: EnrollmentProject = .makeDefault(), assets: [String: Data] = [:]) {
        self.project = project
        self.assets = assets
        self.isReadOnly = false
        self.loadNotes = []
        self.migratedFromVersion = nil
        self.migrationSummary = []
        self.pendingRootFiles = [:]
        self.installerSources = [:]
    }

    /// A new project that starts from the saved app-wide runtime settings.
    init(settingsDefaults: RuntimeSettingsDefaults) {
        var project = EnrollmentProject.makeDefault()
        settingsDefaults.apply(to: &project.settings)
        self.init(project: project)
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try makeFileWrapper(existing: configuration.existingFile)
    }

    // MARK: Reading

    init(fileWrapper root: FileWrapper) throws {
        guard root.isDirectory, let children = root.fileWrappers else {
            throw ProjectFileError.notAProjectPackage
        }
        guard let projectFile = children[ProjectLayout.projectFileName],
              projectFile.isRegularFile,
              let projectData = projectFile.regularFileContents else {
            throw ProjectFileError.missingProjectFile
        }

        let loaded = try ProjectCoding.load(projectData)
        var notes = loaded.notes
        var loadedAssets: [String: Data] = [:]

        for directoryName in ProjectLayout.managedAssetDirectories {
            guard let directory = children[directoryName] else { continue }
            guard directory.isDirectory, let files = directory.fileWrappers else {
                notes.append("\"\(directoryName)\" is not a folder and was ignored.")
                continue
            }
            for (name, file) in files where file.isRegularFile && !name.hasPrefix(".") {
                let path = "\(directoryName)/\(name)"
                guard RelativePathValidator.isSafe(path, allowedRoots: ProjectLayout.managedAssetDirectories) else {
                    notes.append("Ignored a file with an unsafe name in \(directoryName).")
                    continue
                }
                guard let contents = file.regularFileContents else {
                    notes.append("Could not read \(path).")
                    continue
                }
                loadedAssets[path] = contents
            }
        }

        var installers: [String: InstallerSource] = [:]
        if let directory = children[ProjectLayout.installersDirectory], directory.isDirectory {
            for (name, file) in directory.fileWrappers ?? [:] where file.isRegularFile && !name.hasPrefix(".") {
                let path = "\(ProjectLayout.installersDirectory)/\(name)"
                if InstallerImporter.isSafeInstallerPath(path) {
                    installers[path] = InstallerSource(wrapper: file, sourceURL: nil)
                }
            }
        }

        var project = loaded.project
        notes.append(contentsOf: Self.sanitizeReferences(in: &project, assets: loadedAssets, installers: installers))

        var rootFiles: [String: Data] = [:]
        var summary = loaded.migrationSummary
        if let fromVersion = loaded.migratedFromVersion {
            let backupName = ProjectMigrator.backupFileName(forSchema: fromVersion)
            if children[backupName] == nil {
                rootFiles[backupName] = projectData
                summary.append("The original project.json will be kept as \(backupName) inside the project the next time you save.")
            } else {
                summary.append("A backup named \(backupName) already exists and is kept unchanged.")
            }
        }

        self.project = project
        self.assets = loadedAssets
        self.isReadOnly = loaded.isReadOnly
        self.loadNotes = notes
        self.migratedFromVersion = loaded.migratedFromVersion
        self.migrationSummary = summary
        self.pendingRootFiles = rootFiles
        self.installerSources = installers
        if !loaded.isReadOnly {
            applyLoadNormalizations()
        }
    }

    /// Brings an opened project in line with current rules. Nothing is written until the project is saved.
    private mutating func applyLoadNormalizations() {
        // One version for the package and the enrollment bundle.
        project.projectVersion = project.settings.packageVersion
        // Only macOS 26 and 27 are offered as a minimum.
        let supported = ProjectSettings.supportedMinimumMacOSVersions.map { $0.version }
        if !supported.contains(project.settings.minimumMacOSVersion) {
            loadNotes.append("The minimum macOS version was \(project.settings.minimumMacOSVersion). Only macOS 26 and 27 are offered, so it is now \(ProjectSettings.defaultMinimumMacOSVersion).")
            project.settings.minimumMacOSVersion = ProjectSettings.defaultMinimumMacOSVersion
        }
        // The earlier default flag location moved into the onBoarding log folder.
        if project.settings.onboardingFlagPath == "/Library/Logs/Microsoft/IntuneScripts/onboarding.flag" {
            project.settings.onboardingFlagPath = ProjectSettings.defaultOnboardingFlagPath
        }
        // Catalogue items that ship their own icon (Microsoft 365 and Office) use it instead of the installed app's icon.
        applyBundledCatalogIcons()
    }

    /// Clears references that escape the asset folders and reports references to missing files.
    private static func sanitizeReferences(in project: inout EnrollmentProject, assets: [String: Data],
                                           installers: [String: InstallerSource]) -> [String] {
        var notes: [String] = []
        let roots = ProjectLayout.managedAssetDirectories

        func isUsable(_ path: String, label: String) -> Bool {
            guard RelativePathValidator.isSafe(path, allowedRoots: roots) else {
                notes.append("Removed an unsafe file reference for \(label): \(path)")
                return false
            }
            if assets[path] == nil {
                notes.append("\(label) refers to a missing file: \(path)")
            }
            return true
        }

        if let logo = project.branding.logoPath, !isUsable(logo, label: "Company logo") {
            project.branding.logoPath = nil
        }
        if let banner = project.branding.bannerPath, !isUsable(banner, label: "Banner") {
            project.branding.bannerPath = nil
        }
        if let overlay = project.branding.overlayIconPath, !isUsable(overlay, label: "Overlay icon") {
            project.branding.overlayIconPath = nil
        }
        if let wallpaper = project.branding.wallpaperPath, !isUsable(wallpaper, label: "Desktop wallpaper") {
            project.branding.wallpaperPath = nil
        }
        for groupIndex in project.applicationGroups.indices {
            for itemIndex in project.applicationGroups[groupIndex].applications.indices {
                let application = project.applicationGroups[groupIndex].applications[itemIndex]
                if application.icon.kind == .projectAsset,
                   !isUsable(application.icon.value, label: "Icon for \(application.displayName)") {
                    project.applicationGroups[groupIndex].applications[itemIndex].icon = IconSource(kind: .applicationBundle, value: "")
                }
                if let installer = application.installer {
                    if !InstallerImporter.isSafeInstallerPath(installer.relativePath) {
                        notes.append("Removed an unsafe installer reference for \(application.displayName): \(installer.relativePath)")
                        project.applicationGroups[groupIndex].applications[itemIndex].installer = nil
                    } else if installers[installer.relativePath] == nil {
                        notes.append("Installer for \(application.displayName) refers to a missing file: \(installer.relativePath)")
                    }
                }
            }
        }
        for taskIndex in project.systemTasks.indices {
            let task = project.systemTasks[taskIndex]
            if task.icon.kind == .projectAsset, !isUsable(task.icon.value, label: "Icon for \(task.displayName)") {
                project.systemTasks[taskIndex].icon = IconSource(kind: .sfSymbol, value: "gearshape")
            }
        }
        for scriptIndex in project.scripts.indices {
            let script = project.scripts[scriptIndex]
            if !isUsable(script.relativePath, label: "Script \(script.displayName)") {
                project.scripts[scriptIndex].relativePath = ""
            }
        }
        return notes
    }

    // MARK: Writing

    func makeFileWrapper(existing: FileWrapper?) throws -> FileWrapper {
        if isReadOnly {
            throw ProjectFileError.readOnlyProject(project.schemaVersion)
        }

        var output = project
        output.schemaVersion = AppInfo.currentSchemaVersion
        output.applicationVersion = AppInfo.version
        output.projectVersion = output.settings.packageVersion
        output.modifiedAt = ProjectCoding.wholeSeconds(Date())
        let projectData = try ProjectCoding.encode(output)

        let root: FileWrapper
        if let existing, existing.isDirectory {
            root = existing
        } else {
            root = FileWrapper(directoryWithFileWrappers: [:])
        }

        try Self.setRegularFile(named: ProjectLayout.projectFileName, contents: projectData, in: root)
        for (name, data) in pendingRootFiles where root.fileWrappers?[name] == nil {
            try Self.setRegularFile(named: name, contents: data, in: root)
        }

        for directoryName in ProjectLayout.managedAssetDirectories {
            let directory = try Self.childDirectory(named: directoryName, in: root)
            let prefix = directoryName + "/"
            var desired: [String: Data] = [:]
            for (path, data) in assets where path.hasPrefix(prefix) {
                let name = String(path.dropFirst(prefix.count))
                if !name.isEmpty && !name.contains("/") {
                    desired[name] = data
                }
            }
            for (name, child) in directory.fileWrappers ?? [:] where child.isRegularFile && !name.hasPrefix(".") && desired[name] == nil {
                directory.removeFileWrapper(child)
            }
            for (name, data) in desired {
                try Self.setRegularFile(named: name, contents: data, in: directory)
            }
        }

        try writeInstallers(into: root)

        for directoryName in ProjectLayout.preservedDirectories {
            _ = try Self.childDirectory(named: directoryName, in: root)
        }
        return root
    }

    /// Keeps Installers/ in step with the packages the project references. Unchanged packages stay as
    /// they are; newly chosen packages are read from their original location at save time.
    private func writeInstallers(into root: FileWrapper) throws {
        let referenced = project.referencedInstallerPaths
        if referenced.isEmpty && root.fileWrappers?[ProjectLayout.installersDirectory] == nil {
            return
        }
        let directory = try Self.childDirectory(named: ProjectLayout.installersDirectory, in: root)
        let prefix = ProjectLayout.installersDirectory + "/"
        for (name, child) in directory.fileWrappers ?? [:]
        where child.isRegularFile && !name.hasPrefix(".") && !referenced.contains(prefix + name) {
            directory.removeFileWrapper(child)
        }
        for path in referenced.sorted() {
            guard let source = installerSources[path] else { continue }
            let name = String(path.dropFirst(prefix.count))
            let existing = directory.fileWrappers?[name]
            if let wrapper = source.wrapper {
                if existing === wrapper { continue }
                if let existing { directory.removeFileWrapper(existing) }
                wrapper.preferredFilename = name
                _ = directory.addFileWrapper(wrapper)
            } else if let url = source.sourceURL {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                // An earlier save already copied the package into the project. If the original has since been moved
                // or deleted, keep that copy instead of failing every later save. Builds still verify its SHA-256.
                if let existing, existing.isRegularFile, !FileManager.default.isReadableFile(atPath: url.path) {
                    continue
                }
                if let existing { directory.removeFileWrapper(existing) }
                let file = try FileWrapper(url: url, options: [])
                file.preferredFilename = name
                _ = directory.addFileWrapper(file)
            }
        }
    }

    private static func childDirectory(named name: String, in root: FileWrapper) throws -> FileWrapper {
        if let existing = root.fileWrappers?[name] {
            guard existing.isDirectory else {
                throw ProjectFileError.unexpectedItem(name)
            }
            return existing
        }
        let directory = FileWrapper(directoryWithFileWrappers: [:])
        directory.preferredFilename = name
        _ = root.addFileWrapper(directory)
        return directory
    }

    private static func setRegularFile(named name: String, contents: Data, in directory: FileWrapper) throws {
        if let existing = directory.fileWrappers?[name] {
            guard existing.isRegularFile else {
                throw ProjectFileError.unexpectedItem(name)
            }
            if existing.regularFileContents == contents {
                return
            }
            directory.removeFileWrapper(existing)
        }
        let file = FileWrapper(regularFileWithContents: contents)
        file.preferredFilename = name
        _ = directory.addFileWrapper(file)
    }

    // MARK: Asset editing

    func assetData(at path: String?) -> Data? {
        guard let path else { return nil }
        return assets[path]
    }

    /// Stores a file directly inside one of the managed folders.
    mutating func setAsset(_ data: Data, at path: String) throws {
        guard RelativePathValidator.isSafe(path, allowedRoots: ProjectLayout.managedAssetDirectories),
              path.split(separator: "/").count == 2 else {
            throw ProjectFileError.unsafeAssetPath(path)
        }
        assets[path] = data
    }

    /// Deletes an asset once nothing in the project points at it any more.
    mutating func removeAssetIfUnreferenced(_ path: String?) {
        guard let path, !project.referencedAssetPaths.contains(path) else { return }
        assets.removeValue(forKey: path)
    }

    mutating func replaceBrandingImage(_ role: BrandingImageRole, data: Data, path: String) throws {
        try setAsset(data, at: path)
        let previous: String?
        switch role {
        case .logo:
            previous = project.branding.logoPath
            project.branding.logoPath = path
        case .banner:
            previous = project.branding.bannerPath
            project.branding.bannerPath = path
        case .overlay:
            previous = project.branding.overlayIconPath
            project.branding.overlayIconPath = path
        case .wallpaper:
            previous = project.branding.wallpaperPath
            project.branding.wallpaperPath = path
        }
        if previous != path {
            removeAssetIfUnreferenced(previous)
        }
    }

    // MARK: Scripts

    /// Adds an imported script and its file as one change.
    mutating func addImportedScript(_ item: ScriptItem, data: Data) throws {
        try setAsset(data, at: item.relativePath)
        project.addScript(item)
    }

    /// Replaces a script's file, keeping its settings. The new file is hashed and inspected again.
    mutating func replaceScriptFile(id: UUID, data: Data, originalFilename: String, wasExecutable: Bool, now: Date = Date()) throws {
        guard var script = project.script(id: id) else { return }
        try ScriptImporter.validate(data: data, filename: originalFilename)
        let oldPath = script.relativePath
        let newExtension = (originalFilename as NSString).pathExtension.lowercased()
        if (oldPath as NSString).pathExtension.lowercased() != newExtension || oldPath.isEmpty {
            var existing = Set(assets.keys)
            existing.remove(oldPath)
            script.relativePath = ScriptImporter.scriptPath(for: originalFilename, existingPaths: existing)
        }
        try setAsset(data, at: script.relativePath)
        script.originalFilename = originalFilename
        script.sha256 = Hashing.sha256Hex(data)
        script.interpreter = ScriptInspector.inspect(data).interpreter ?? ""
        script.sourceWasExecutable = wasExecutable
        script.importedAt = ProjectCoding.wholeSeconds(now)
        project.updateScript(script)
        if oldPath != script.relativePath {
            removeAssetIfUnreferenced(oldPath)
        }
    }

    /// Records the current file contents as reviewed after the file changed outside the app.
    mutating func acceptCurrentScriptFile(id: UUID) {
        guard var script = project.script(id: id), let data = assets[script.relativePath] else { return }
        script.sha256 = Hashing.sha256Hex(data)
        script.interpreter = ScriptInspector.inspect(data).interpreter ?? ""
        project.updateScript(script)
    }

    @discardableResult
    mutating func removeScript(id: UUID) -> ScriptItem? {
        guard let removed = project.removeScript(id: id) else { return nil }
        removeAssetIfUnreferenced(removed.relativePath)
        return removed
    }

    // MARK: Installers

    /// Attaches a package to an application, replacing any previous one. The file is copied on the next save.
    mutating func attachInstaller(_ pending: PendingInstaller, toApplication id: UUID, now: Date = Date()) {
        guard var application = project.application(id: id) else { return }
        let previous = application.installer?.relativePath
        var existing = Set(installerSources.keys).union(project.referencedInstallerPaths)
        if let previous { existing.remove(previous) }
        let path = InstallerImporter.installerPath(for: pending.inspection.originalFilename, existingPaths: existing)
        installerSources[path] = InstallerSource(wrapper: nil, sourceURL: pending.sourceURL)
        application.installer = InstallerReference(
            relativePath: path,
            originalFilename: pending.inspection.originalFilename,
            sha256: pending.inspection.sha256,
            sizeBytes: pending.inspection.sizeBytes,
            importedAt: ProjectCoding.wholeSeconds(now)
        )
        project.updateApplication(application)
        if let previous, previous != path {
            removeInstallerIfUnreferenced(previous)
        }
    }

    mutating func removeInstallerIfUnreferenced(_ path: String?) {
        guard let path, !project.referencedInstallerPaths.contains(path) else { return }
        installerSources.removeValue(forKey: path)
    }

    // MARK: Copies

    /// A copy for "Duplicate as New Project" or import: new project ID, so device state never collides.
    func asNewProject(name: String? = nil, keepProjectID: Bool = false, now: Date = Date()) -> EnrollmentProjectDocument {
        var copy = project
        if !keepProjectID {
            copy.id = UUID()
        }
        if let name {
            copy.settings.projectName = name
        }
        let timestamp = ProjectCoding.wholeSeconds(now)
        copy.createdAt = timestamp
        copy.modifiedAt = timestamp
        copy.schemaVersion = AppInfo.currentSchemaVersion
        let referenced = copy.referencedAssetPaths
        var result = EnrollmentProjectDocument(project: copy, assets: assets.filter { referenced.contains($0.key) })
        let installerPaths = copy.referencedInstallerPaths
        result.installerSources = installerSources.filter { installerPaths.contains($0.key) }
        return result
    }

    mutating func removeBrandingImage(_ role: BrandingImageRole) {
        let previous: String?
        switch role {
        case .logo:
            previous = project.branding.logoPath
            project.branding.logoPath = nil
        case .banner:
            previous = project.branding.bannerPath
            project.branding.bannerPath = nil
        case .overlay:
            previous = project.branding.overlayIconPath
            project.branding.overlayIconPath = nil
        case .wallpaper:
            previous = project.branding.wallpaperPath
            project.branding.wallpaperPath = nil
        }
        removeAssetIfUnreferenced(previous)
    }
}
