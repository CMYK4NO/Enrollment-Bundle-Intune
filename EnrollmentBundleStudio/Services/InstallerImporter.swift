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

// MARK: - Package metadata

/// An application bundle that a package installs, taken from the package's own PackageInfo.
struct PackageApplication: Equatable, Hashable, Identifiable {
    /// CFBundleIdentifier. PackageInfo records it only for nested bundles, so for an app that is the install
    /// location itself it is read from the payload's Info.plist and is empty until then.
    var bundleIdentifier: String
    /// Absolute install path, for example /Applications/Microsoft Edge.app.
    let path: String
    /// Identifier of the package component that installs the bundle (its installer receipt).
    let receiptIdentifier: String
    /// Folder of the component inside a product archive, for example "gp.pkg"; empty for a plain component package.
    var component: String = ""
    /// Where the app's Info.plist sits inside the component's payload, for example "Contents/Info.plist".
    var infoPlistPath: String = ""

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

/// The installer receipt of one package component.
struct PackageReceipt: Equatable {
    let identifier: String
    let version: String
    let installLocation: String
}

/// What the administrator can learn about a package without installing it.
struct PackageMetadata: Equatable {
    var receipts: [PackageReceipt] = []
    var applications: [PackageApplication] = []

    /// The receipt identifier to suggest: the one that installs the given application, otherwise the only
    /// receipt in the package. Nil when the package has several receipts and no application was chosen.
    func receiptIdentifier(for application: PackageApplication?) -> String? {
        if let application, !application.receiptIdentifier.isEmpty { return application.receiptIdentifier }
        return receipts.count == 1 ? receipts[0].identifier : nil
    }

    /// Adds another component's details, skipping receipts and applications already present.
    mutating func merge(_ other: PackageMetadata) {
        for receipt in other.receipts where !receipts.contains(receipt) {
            receipts.append(receipt)
        }
        for application in other.applications where !applications.contains(where: { $0.path == application.path }) {
            applications.append(application)
        }
    }
}

/// Reads PackageInfo XML. Pure functions on data, so it is easy to test and never touches the package.
enum PackageMetadataParser {
    /// Files larger than this are ignored; a real PackageInfo is a few kilobytes.
    static let maximumPackageInfoBytes = 2 * 1024 * 1024

    static func parse(packageInfos: [Data]) -> PackageMetadata {
        var metadata = PackageMetadata()
        for data in packageInfos where data.count <= maximumPackageInfoBytes {
            guard let parsed = parseOne(data) else { continue }
            var single = PackageMetadata()
            if !parsed.receipt.identifier.isEmpty {
                single.receipts = [parsed.receipt]
            }
            single.applications = parsed.applications
            metadata.merge(single)
        }
        return metadata
    }

    /// Joins an install location and a bundle path from PackageInfo ("./Foo.app") into an absolute path.
    /// Returns nil for paths that climb out of the location with "..".
    static func absolutePath(installLocation: String, bundlePath: String) -> String? {
        let location = installLocation.isEmpty ? "/" : installLocation
        var parts: [String] = []
        for component in "\(location)/\(bundlePath)".split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." { return nil }
            parts.append(String(component))
        }
        return "/" + parts.joined(separator: "/")
    }

    /// True for an application bundle that is not nested inside another bundle's .app folder.
    static func isTopLevelApplication(_ path: String) -> Bool {
        let components = path.split(separator: "/").map { $0.lowercased() }
        guard let last = components.last, last.hasSuffix(".app") else { return false }
        return !components.dropLast().contains { $0.hasSuffix(".app") }
    }

    /// CFBundleIdentifier from an Info.plist, or nil when it is missing or not a valid identifier
    /// (for example an unexpanded $(PRODUCT_BUNDLE_IDENTIFIER)).
    static func bundleIdentifier(fromInfoPlist data: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any],
              let identifier = dictionary["CFBundleIdentifier"] as? String,
              FieldValidator.isValidReverseDNS(identifier) else { return nil }
        return identifier
    }

    private static func parseOne(_ data: Data) -> (receipt: PackageReceipt, applications: [PackageApplication])? {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse(), collector.sawPackageInfo else { return nil }
        let receipt = PackageReceipt(identifier: collector.identifier, version: collector.version, installLocation: collector.installLocation)
        var applications: [PackageApplication] = []
        // The install location can be the application itself (install-location="/Applications/Foo.app"); the
        // bundles listed then are things inside it, such as extensions.
        if let location = absolutePath(installLocation: collector.installLocation, bundlePath: ""),
           !collector.installLocation.isEmpty, isTopLevelApplication(location) {
            applications.append(PackageApplication(bundleIdentifier: "", path: location, receiptIdentifier: collector.identifier,
                                                   infoPlistPath: "Contents/Info.plist"))
        }
        for bundle in collector.bundles {
            guard let path = absolutePath(installLocation: collector.installLocation, bundlePath: bundle.path),
                  isTopLevelApplication(path) else { continue }
            let relative = bundle.path.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
            applications.append(PackageApplication(bundleIdentifier: bundle.identifier, path: path, receiptIdentifier: collector.identifier,
                                                   infoPlistPath: "\(relative)/Contents/Info.plist"))
        }
        return (receipt, applications)
    }

    /// Collects pkg-info attributes and the bundles listed under bundle-version. Bundles under
    /// upgrade-bundle, update-bundle and similar elements describe other software and are ignored.
    private final class Collector: NSObject, XMLParserDelegate {
        var sawPackageInfo = false
        var identifier = ""
        var version = ""
        var installLocation = ""
        var bundles: [(identifier: String, path: String)] = []
        private var stack: [String] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "pkg-info", !sawPackageInfo {
                sawPackageInfo = true
                identifier = attributeDict["identifier"] ?? ""
                version = attributeDict["version"] ?? ""
                installLocation = attributeDict["install-location"] ?? ""
            } else if elementName == "bundle", let parent = stack.last, parent == "bundle-version" || parent == "pkg-info",
                      let path = attributeDict["path"], !path.isEmpty {
                bundles.append((attributeDict["id"] ?? attributeDict["CFBundleIdentifier"] ?? "", path))
            }
            stack.append(elementName)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }
    }
}

enum PackageMetadataError: LocalizedError, Equatable {
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolFailed(let detail): return "The package contents could not be read (\(detail))."
        }
    }
}

/// Lists a flat package's archive with /usr/bin/xar and extracts only its small PackageInfo files into a
/// temporary folder. When an application's bundle identifier is not in PackageInfo, it also extracts that one
/// component's payload and reads a single Info.plist from it with /usr/bin/bsdtar. Nothing is installed, no
/// package script runs, and the temporary folder is removed afterwards.
struct PackageMetadataReader {
    static let xarPath = "/usr/bin/xar"
    static let bsdtarPath = "/usr/bin/bsdtar"
    static let maximumPackageInfoFiles = 64
    /// Payloads are only opened for this many applications, so a large suite is not unpacked several times.
    static let maximumPayloadReads = 2

    let runner: CommandRunning

    static func live() -> PackageMetadataReader {
        PackageMetadataReader(runner: ProcessCommandRunner(allowedExecutables: [xarPath, bsdtarPath]))
    }

    func read(at url: URL) async throws -> PackageMetadata {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        let path = url.resolvingSymlinksInPath().path
        let xar = URL(fileURLWithPath: Self.xarPath)

        let listing = try await runner.run(executable: xar, arguments: ["-t", "-f", path], standardInput: nil, timeout: 60)
        guard listing.exitCode == 0, !listing.timedOut else {
            throw PackageMetadataError.toolFailed("xar could not list the archive")
        }
        let allNames = Set(Self.archiveNames(in: listing.standardOutputText))
        let names = Self.packageInfoNames(in: listing.standardOutputText)
        guard !names.isEmpty else { return PackageMetadata() }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EBS-pkginfo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let extraction = try await runner.run(executable: xar, arguments: ["-x", "-f", path, "-C", folder.path] + names,
                                              standardInput: nil, timeout: 60)
        guard extraction.exitCode == 0, !extraction.timedOut else {
            throw PackageMetadataError.toolFailed("xar could not extract PackageInfo")
        }
        var metadata = PackageMetadata()
        for name in names {
            let file = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file), data.count <= PackageMetadataParser.maximumPackageInfoBytes else { continue }
            var component = PackageMetadataParser.parse(packageInfos: [data])
            let folderName = (name as NSString).deletingLastPathComponent
            component.applications = component.applications.map { application in
                var tagged = application
                tagged.component = folderName
                return tagged
            }
            metadata.merge(component)
        }

        var payloadReads = 0
        for index in metadata.applications.indices where metadata.applications[index].bundleIdentifier.isEmpty {
            guard payloadReads < Self.maximumPayloadReads else { break }
            let application = metadata.applications[index]
            let payloadName = application.component.isEmpty ? "Payload" : "\(application.component)/Payload"
            guard allNames.contains(payloadName) else { continue }
            payloadReads += 1
            if let identifier = await bundleIdentifier(of: application, payloadName: payloadName, packagePath: path, folder: folder) {
                metadata.applications[index].bundleIdentifier = identifier
            }
        }
        return metadata
    }

    /// Extracts one component's payload and pulls the application's Info.plist out of it. Any failure returns
    /// nil, and the administrator then enters the identifier by hand.
    private func bundleIdentifier(of application: PackageApplication, payloadName: String, packagePath: String, folder: URL) async -> String? {
        guard !application.infoPlistPath.isEmpty else { return nil }
        let xar = URL(fileURLWithPath: Self.xarPath)
        let bsdtar = URL(fileURLWithPath: Self.bsdtarPath)
        guard let extraction = try? await runner.run(executable: xar, arguments: ["-x", "-f", packagePath, "-C", folder.path, payloadName],
                                                     standardInput: nil, timeout: 180),
              extraction.exitCode == 0, !extraction.timedOut else { return nil }
        let payload = folder.appendingPathComponent(payloadName)
        let output = folder.appendingPathComponent("plist-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)) != nil else { return nil }
        // Payload archives usually store names with a leading "./".
        for member in ["./\(application.infoPlistPath)", application.infoPlistPath] {
            guard let result = try? await runner.run(executable: bsdtar, arguments: ["-xf", payload.path, "-C", output.path, member],
                                                     standardInput: nil, timeout: 180),
                  result.exitCode == 0 else { continue }
            let file = output.appendingPathComponent(application.infoPlistPath)
            if let data = try? Data(contentsOf: file), data.count <= PackageMetadataParser.maximumPackageInfoBytes,
               let identifier = PackageMetadataParser.bundleIdentifier(fromInfoPlist: data) {
                return identifier
            }
        }
        return nil
    }

    /// Every member name in an `xar -t` listing that is safe to pass back to xar.
    static func archiveNames(in listing: String) -> [String] {
        listing.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init).filter { name in
            !name.hasPrefix("/") && !name.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        }
    }

    /// Archive members named PackageInfo, at the top level or inside a component package. Names that are
    /// absolute or contain ".." are skipped so extraction can never leave the temporary folder.
    static func packageInfoNames(in listing: String) -> [String] {
        var names: [String] = []
        for name in archiveNames(in: listing) where name.split(separator: "/", omittingEmptySubsequences: false).last == "PackageInfo" {
            guard !names.contains(name) else { continue }
            names.append(name)
            if names.count == maximumPackageInfoFiles { break }
        }
        return names
    }
}


/// Suggests a display name for an application that is delivered by a package.
enum DisplayNameSuggestion {
    /// The name of the application in the package, else of the application at `applicationPath`, else the
    /// package file name without its extension. Empty when none of them gives a name.
    static func suggest(packageApplicationPath: String?, applicationPath: String, packageFilename: String) -> String {
        for candidate in [packageApplicationPath ?? "", applicationPath] {
            let path = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.lowercased().hasSuffix(".app") else { continue }
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        let file = (packageFilename as NSString).lastPathComponent
        let name = ((file as NSString).pathExtension.lowercased() == "pkg" ? (file as NSString).deletingPathExtension : file)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name
    }
}
