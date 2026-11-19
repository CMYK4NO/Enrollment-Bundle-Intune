import Foundation

struct ConfigurationImportIssue: Identifiable, Equatable {
    let severity: ValidationSeverity
    let message: String
    var id: String { "\(severity.rawValue)|\(message)" }
}

struct ConfigurationImportResult {
    let project: EnrollmentProject
    let assets: [String: Data]
    let issues: [ConfigurationImportIssue]
    let exportedAt: String
    let sourceApplicationVersion: String
    let sourceSchemaVersion: Int
    let migrationSummary: [String]

    var hasErrors: Bool { issues.contains { $0.severity == .error } }
}

/// A single, readable JSON file that carries project.json plus every referenced icon and script,
/// each with its SHA-256 and size. Files are base64 encoded so the archive needs no zip tooling.
/// Installer packages are not included; their references are cleared on import with a warning.
///
/// ```
/// { "format": "com.example.enrollmentbundlestudio.configuration", "formatVersion": 1,
///   "exportedAt": "...", "applicationVersion": "...", "schemaVersion": 2,
///   "project": { ...project.json... },
///   "files": [ { "path": "Icons/Edge.png", "sha256": "...", "size": 1234, "base64": "..." } ] }
/// ```
enum ConfigurationArchive {
    static let formatIdentifier = "com.example.enrollmentbundlestudio.configuration"
    static let currentFormatVersion = 1
    static let fileExtension = "enrollmentconfig"
    static let maximumArchiveBytes = 64 * 1024 * 1024

    // MARK: Export

    static func export(project: EnrollmentProject, assets: [String: Data], now: Date = Date()) throws -> Data {
        let projectObject = try JSONSerialization.jsonObject(with: ProjectCoding.encode(project))
        let referenced = project.referencedAssetPaths
        let files: [[String: Any]] = assets.keys.filter { referenced.contains($0) }.sorted().compactMap { path in
            guard let data = assets[path] else { return nil }
            return [
                "path": path,
                "sha256": Hashing.sha256Hex(data),
                "size": data.count,
                "base64": data.base64EncodedString()
            ]
        }
        let root: [String: Any] = [
            "format": formatIdentifier,
            "formatVersion": currentFormatVersion,
            "exportedAt": ISO8601DateFormatter().string(from: ProjectCoding.wholeSeconds(now)),
            "applicationVersion": AppInfo.version,
            "schemaVersion": project.schemaVersion,
            "project": projectObject,
            "files": files
        ]
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    // MARK: Import

    /// Imported projects can carry commands and scripts that run as root on every Mac the package reaches.
    /// This notice makes sure the administrator knows to read them before building.
    private static func commandNotice(for project: EnrollmentProject) -> ConfigurationImportIssue? {
        guard let summary = project.commandSummary else { return nil }
        return ConfigurationImportIssue(
            severity: .warning,
            message: "This project contains \(summary) that will run on enrolled Macs, most of them as root. Review them in Scripts, Applications and Branding before building a package, and import only projects you trust."
        )
    }

    /// Builds an import result from a project package the administrator picked in the import panel, so an
    /// `.enrollmentproject` can be imported as a new project just like an exported configuration.
    /// Installer packages are not carried over; their references are cleared with a warning.
    static func importResult(from document: EnrollmentProjectDocument, now: Date = Date()) throws -> ConfigurationImportResult {
        if document.isReadOnly {
            throw ProjectFileError.newerSchemaUnreadable(document.project.schemaVersion)
        }
        var project = document.project
        var issues: [ConfigurationImportIssue] = []
        for groupIndex in project.applicationGroups.indices {
            for itemIndex in project.applicationGroups[groupIndex].applications.indices {
                if let installer = project.applicationGroups[groupIndex].applications[itemIndex].installer {
                    let name = project.applicationGroups[groupIndex].applications[itemIndex].displayName
                    project.applicationGroups[groupIndex].applications[itemIndex].installer = nil
                    issues.append(ConfigurationImportIssue(
                        severity: .warning,
                        message: "\(name) used the installer package \(installer.originalFilename), which imports do not carry. Attach it again after import."
                    ))
                }
            }
        }
        for script in project.scripts {
            if let data = document.assets[script.relativePath], Hashing.sha256Hex(data) != script.sha256 {
                issues.append(ConfigurationImportIssue(
                    severity: .error,
                    message: "Script \(script.displayName) does not match the hash recorded in the project."
                ))
            }
        }
        if let notice = commandNotice(for: project) {
            issues.append(notice)
        }
        for note in document.loadNotes {
            issues.append(ConfigurationImportIssue(severity: .information, message: note))
        }
        for summary in document.migrationSummary {
            issues.append(ConfigurationImportIssue(severity: .information, message: summary))
        }
        let referenced = project.referencedAssetPaths
        let assets = document.assets.filter { referenced.contains($0.key) }
        return ConfigurationImportResult(
            project: project,
            assets: assets,
            issues: issues,
            exportedAt: ISO8601DateFormatter().string(from: ProjectCoding.wholeSeconds(now)),
            sourceApplicationVersion: project.applicationVersion,
            sourceSchemaVersion: document.migratedFromVersion ?? project.schemaVersion,
            migrationSummary: document.migrationSummary
        )
    }

    /// Parses and validates an archive. Nothing in it is trusted: paths, hashes, sizes, images,
    /// identifiers and schema are all checked. Throws only when the file is not an archive at all.
    static func parse(_ data: Data) throws -> ConfigurationImportResult {
        guard data.count <= maximumArchiveBytes else {
            throw ProjectFileError.invalidProjectFile("The configuration file is larger than 64 MB.")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectFileError.invalidProjectFile("The file is not a JSON configuration export.")
        }
        guard root["format"] as? String == formatIdentifier else {
            throw ProjectFileError.invalidProjectFile("The file is not an Enrollment Bundle Studio configuration export.")
        }
        guard let formatVersion = root["formatVersion"] as? Int else {
            throw ProjectFileError.invalidProjectFile("The configuration has no format version.")
        }
        guard formatVersion <= currentFormatVersion else {
            throw ProjectFileError.invalidProjectFile("The configuration uses format version \(formatVersion), which is newer than this application supports.")
        }
        guard let projectObject = root["project"] as? [String: Any] else {
            throw ProjectFileError.invalidProjectFile("The configuration does not contain a project.")
        }

        var issues: [ConfigurationImportIssue] = []
        func add(_ severity: ValidationSeverity, _ message: String) {
            issues.append(ConfigurationImportIssue(severity: severity, message: message))
        }

        let projectData = try JSONSerialization.data(withJSONObject: projectObject, options: [.sortedKeys])
        let loaded = try ProjectCoding.load(projectData)
        if loaded.isReadOnly {
            throw ProjectFileError.newerSchemaUnreadable(loaded.project.schemaVersion)
        }
        var project = loaded.project

        // Installer packages are too large for a JSON export and are never included.
        for groupIndex in project.applicationGroups.indices {
            for itemIndex in project.applicationGroups[groupIndex].applications.indices {
                if let installer = project.applicationGroups[groupIndex].applications[itemIndex].installer {
                    let name = project.applicationGroups[groupIndex].applications[itemIndex].displayName
                    project.applicationGroups[groupIndex].applications[itemIndex].installer = nil
                    add(.warning, "\(name) used the installer package \(installer.originalFilename), which exports do not carry. Attach it again after import.")
                }
            }
        }

        var assets: [String: Data] = [:]
        let roots = ProjectLayout.managedAssetDirectories
        for (index, entry) in ((root["files"] as? [[String: Any]]) ?? []).enumerated() {
            guard let path = entry["path"] as? String,
                  let expectedHash = entry["sha256"] as? String,
                  let expectedSize = entry["size"] as? Int,
                  let encoded = entry["base64"] as? String else {
                add(.error, "File entry \(index + 1) is incomplete and was skipped.")
                continue
            }
            guard RelativePathValidator.isSafe(path, allowedRoots: roots), path.split(separator: "/").count == 2 else {
                add(.error, "Refused unsafe file path \"\(path)\".")
                continue
            }
            guard assets[path] == nil else {
                add(.error, "The file \(path) appears more than once.")
                continue
            }
            guard let fileData = Data(base64Encoded: encoded) else {
                add(.error, "The contents of \(path) are not valid base64.")
                continue
            }
            guard fileData.count == expectedSize else {
                add(.error, "\(path) has \(fileData.count) bytes but the export lists \(expectedSize).")
                continue
            }
            guard Hashing.sha256Hex(fileData) == expectedHash.lowercased() else {
                add(.error, "The SHA-256 of \(path) does not match the export; the file may have been altered.")
                continue
            }
            if path.hasPrefix("\(ProjectLayout.brandingDirectory)/") || path.hasPrefix("\(ProjectLayout.iconsDirectory)/") {
                if (try? AssetImporter.validateImage(fileData)) == nil {
                    add(.error, "\(path) is not a valid PNG, JPEG or ICNS image.")
                    continue
                }
            }
            assets[path] = fileData
        }

        for path in project.referencedAssetPaths.sorted() {
            if !RelativePathValidator.isSafe(path, allowedRoots: roots) {
                add(.error, "The project references an unsafe path \"\(path)\".")
            } else if assets[path] == nil {
                add(.error, "The project references \(path), which is not in the export.")
            }
        }
        for script in project.scripts {
            if let data = assets[script.relativePath], Hashing.sha256Hex(data) != script.sha256 {
                add(.error, "Script \(script.displayName) does not match the hash recorded in the project.")
            }
        }
        let unreferenced = Set(assets.keys).subtracting(project.referencedAssetPaths)
        for path in unreferenced.sorted() {
            assets.removeValue(forKey: path)
            add(.information, "\(path) is not used by the project and was left out.")
        }

        for issue in DependencyGraph.analyze(TaskPlanner.plan(project)).issues {
            if case .duplicateIdentifier(let id) = issue {
                add(.error, "More than one task uses the identifier \(id).")
            }
        }
        if let notice = commandNotice(for: project) {
            issues.append(notice)
        }
        for summary in loaded.migrationSummary {
            add(.information, summary)
        }

        return ConfigurationImportResult(
            project: project,
            assets: assets,
            issues: issues,
            exportedAt: (root["exportedAt"] as? String) ?? "unknown",
            sourceApplicationVersion: (root["applicationVersion"] as? String) ?? "unknown",
            sourceSchemaVersion: loaded.migratedFromVersion ?? project.schemaVersion,
            migrationSummary: loaded.migrationSummary
        )
    }
}
