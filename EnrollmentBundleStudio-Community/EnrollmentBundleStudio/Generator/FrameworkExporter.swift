import Foundation

enum FrameworkExportError: LocalizedError, Equatable {
    case destinationExists(String)
    case installerHashMismatch(String)
    case installerUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let path):
            return "\(path) already exists."
        case .installerHashMismatch(let path):
            return "The copied package \(path) does not match the SHA-256 recorded when it was attached. Attach the package again."
        case .installerUnreadable(let path):
            return "The installer package for \(path) could not be read."
        }
    }
}

struct FrameworkExportResult: Equatable {
    let destination: URL
    let fileCount: Int
    let totalBytes: Int64
}

/// Writes a generated framework to disk. Files are written to a temporary sibling folder first and moved
/// into place only when everything succeeded, so a failed export never leaves a half-written folder.
/// An existing export is replaced only when the caller confirmed it, and it goes to the Trash.
enum FrameworkExporter {
    static func destination(for framework: GeneratedFramework, in outputDirectory: URL) -> URL {
        outputDirectory.appendingPathComponent(framework.rootName, isDirectory: true)
    }

    /// Moves a replaced export to the Trash, so replacing is recoverable. Tests inject plain removal.
    static let moveToTrash: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func write(
        _ framework: GeneratedFramework,
        to destination: URL,
        replacingExisting: Bool,
        removeExisting: (URL) throws -> Void = FrameworkExporter.moveToTrash
    ) throws -> FrameworkExportResult {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) && !replacingExisting {
            throw FrameworkExportError.destinationExists(destination.path)
        }
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var succeeded = false
        defer {
            if !succeeded {
                try? fileManager.removeItem(at: staging)
            }
        }

        var totalBytes: Int64 = 0
        for file in framework.files {
            let url = staging.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: file.isExecutable ? 0o755 : 0o644], ofItemAtPath: url.path)
            totalBytes += Int64(file.contents.count)
        }
        for copy in framework.installerCopies {
            let url = staging.appendingPathComponent(copy.path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let wrapper = copy.source.wrapper {
                try wrapper.write(to: url, options: [], originalContentsURL: nil)
            } else if let sourceURL = copy.source.sourceURL {
                let didAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }
                try fileManager.copyItem(at: sourceURL, to: url)
            } else {
                throw FrameworkExportError.installerUnreadable(copy.path)
            }
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            guard try InstallerImporter.sha256(of: url) == copy.sha256.lowercased() else {
                throw FrameworkExportError.installerHashMismatch(copy.path)
            }
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            totalBytes += size
        }

        if fileManager.fileExists(atPath: destination.path) {
            try removeExisting(destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        succeeded = true
        return FrameworkExportResult(
            destination: destination,
            fileCount: framework.files.count + framework.installerCopies.count,
            totalBytes: totalBytes
        )
    }
}
