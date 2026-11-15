import CryptoKit
import Foundation

struct InstallerInspection: Equatable {
    let originalFilename: String
    let sizeBytes: Int64
    let sha256: String
}

/// A package chosen in the editor, attached to the project when the editor is saved.
struct PendingInstaller: Equatable {
    let sourceURL: URL
    let inspection: InstallerInspection
}

enum InstallerImportError: LocalizedError, Equatable {
    case notAPackage(String)
    case bundlePackage(String)
    case emptyFile
    case notAFlatPackage(String)

    var errorDescription: String? {
        switch self {
        case .notAPackage(let name):
            return "\"\(name)\" is not a .pkg file."
        case .bundlePackage(let name):
            return "\"\(name)\" is an old bundle-style package. Only flat packages are supported; rebuild it with productbuild or pkgbuild."
        case .emptyFile:
            return "The package is empty."
        case .notAFlatPackage(let name):
            return "\"\(name)\" does not look like a flat installer package (missing xar header)."
        }
    }
}

/// Reads and hashes an installer package. The package is never opened by Installer or executed;
/// only its header bytes and SHA-256 are read. Hashing streams the file, so large packages stay out of memory.
enum InstallerImporter {
    /// Flat packages are xar archives and start with "xar!".
    static let xarMagic: [UInt8] = [0x78, 0x61, 0x72, 0x21]
    static let chunkSize = 1 << 20

    static func inspect(at url: URL) throws -> InstallerInspection {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        let resolved = url.resolvingSymlinksInPath()
        let name = url.lastPathComponent
        guard resolved.pathExtension.lowercased() == "pkg" else { throw InstallerImportError.notAPackage(name) }

        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        if values.isDirectory == true { throw InstallerImportError.bundlePackage(name) }
        guard values.isRegularFile == true else { throw InstallerImportError.notAPackage(name) }
        guard let size = values.fileSize, size > 0 else { throw InstallerImportError.emptyFile }

        let handle = try FileHandle(forReadingFrom: resolved)
        let header = (try? handle.read(upToCount: xarMagic.count)) ?? Data()
        guard [UInt8](header) == xarMagic else {
            try? handle.close()
            throw InstallerImportError.notAFlatPackage(name)
        }

        try handle.close()
        return InstallerInspection(originalFilename: name, sizeBytes: Int64(size), sha256: try sha256(of: resolved))
    }

    /// Streams a file through SHA-256 in 1 MB chunks.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A unique path inside Installers/ derived from the original file name.
    static func installerPath(for filename: String, existingPaths: Set<String>) -> String {
        let base = FilenameSanitizer.sanitize((filename as NSString).deletingPathExtension, fallback: "Installer")
        let prefix = "\(ProjectLayout.installersDirectory)/"
        let existingNames = Set(existingPaths.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        return prefix + FilenameSanitizer.uniqueName(base: base, fileExtension: "pkg", existing: existingNames)
    }

    static func isSafeInstallerPath(_ path: String) -> Bool {
        RelativePathValidator.isSafe(path, allowedRoots: [ProjectLayout.installersDirectory])
            && path.split(separator: "/").count == 2
            && path.lowercased().hasSuffix(".pkg")
    }
}
