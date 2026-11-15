import Foundation

enum ScriptImportError: LocalizedError, Equatable {
    case notARegularFile
    case unsupportedExtension(String)
    case emptyFile
    case tooLarge(Int)
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .notARegularFile:
            return "The selected item is not a regular file."
        case .unsupportedExtension(let name):
            return "\"\(name)\" is not a .sh or .zsh file."
        case .emptyFile:
            return "The script is empty."
        case .tooLarge(let bytes):
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "The script is \(formatted). Scripts must be 1 MB or smaller."
        case .notUTF8:
            return "The script is not UTF-8 text."
        }
    }
}

/// Copies a script into the project. Importing only reads and inspects the file; it never runs it.
enum ScriptImporter {
    static let maximumBytes = 1_048_576
    static let allowedExtensions: Set<String> = ["sh", "zsh"]

    /// Reads a user-selected script and reports whether it had an executable bit.
    static func readScript(at url: URL) throws -> (data: Data, wasExecutable: Bool) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let resolved = url.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ScriptImportError.notARegularFile }
        if let size = values.fileSize, size > maximumBytes { throw ScriptImportError.tooLarge(size) }
        let data = try Data(contentsOf: resolved)
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return (data, permissions & 0o111 != 0)
    }

    /// Rejects files that cannot be a usable script. Interpreter problems are reported by validation instead,
    /// so the administrator can import, see the problem and replace the file.
    static func validate(data: Data, filename: String) throws {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else { throw ScriptImportError.unsupportedExtension(filename) }
        guard !data.isEmpty else { throw ScriptImportError.emptyFile }
        guard data.count <= maximumBytes else { throw ScriptImportError.tooLarge(data.count) }
        guard String(data: data, encoding: .utf8) != nil else { throw ScriptImportError.notUTF8 }
    }

    /// A unique path inside Scripts/ derived from the original file name.
    static func scriptPath(for filename: String, existingPaths: Set<String>) -> String {
        let base = FilenameSanitizer.sanitize((filename as NSString).deletingPathExtension, fallback: "Script")
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        let prefix = "\(ProjectLayout.scriptsDirectory)/"
        let existingNames = Set(existingPaths.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        return prefix + FilenameSanitizer.uniqueName(base: base, fileExtension: fileExtension, existing: existingNames)
    }

    static func makeScriptItem(
        data: Data,
        originalFilename: String,
        wasExecutable: Bool,
        project: EnrollmentProject,
        existingAssetPaths: Set<String>,
        now: Date = Date()
    ) throws -> (item: ScriptItem, path: String) {
        try validate(data: data, filename: originalFilename)
        let inspection = ScriptInspector.inspect(data)
        let path = scriptPath(for: originalFilename, existingPaths: existingAssetPaths)
        let displayName = (originalFilename as NSString).deletingPathExtension

        var execution = TaskExecutionOptions()
        execution.isRequired = false
        execution.timeoutSeconds = project.settings.defaultTaskTimeoutSeconds
        execution.executionOrder = project.nextExecutionOrder
        execution.messages = .script

        let item = ScriptItem(
            id: UUID(),
            taskIdentifier: project.uniqueTaskIdentifier(for: displayName, prefix: "script"),
            displayName: displayName,
            relativePath: path,
            originalFilename: originalFilename,
            sha256: Hashing.sha256Hex(data),
            interpreter: inspection.interpreter ?? "",
            sourceWasExecutable: wasExecutable,
            importedAt: ProjectCoding.wholeSeconds(now),
            successExitCodes: [0],
            execution: execution
        )
        return (item, path)
    }
}
