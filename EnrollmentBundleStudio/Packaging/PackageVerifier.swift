import Foundation

struct PackageCheck: Equatable, Identifiable {
    let title: String
    let passed: Bool
    let detail: String
    var id: String { title }
}

struct PackageVerification: Equatable {
    let packagePath: String
    let sizeBytes: Int64
    let sha256: String
    let identifier: String
    let version: String
    /// Human-readable signature state reported by pkgutil. Unsigned is expected: packages are not signed.
    let signatureStatus: String
    let payloadFileCount: Int
    let checks: [PackageCheck]

    var passed: Bool { checks.allSatisfy { $0.passed } }
}

/// Inspects a built package with pkgutil without installing it: signature state, payload contents and the
/// package metadata (identifier, version, install scripts). Never runs the package or its scripts.
enum PackageVerifier {
    static func verify(packageURL: URL, plan: PackagePlan, runner: CommandRunning) async throws -> PackageVerification {
        let pkgutil = URL(fileURLWithPath: PackagePlan.pkgutil)
        var checks: [PackageCheck] = []

        let signature = try await runner.run(executable: pkgutil, arguments: ["--check-signature", packageURL.path], standardInput: nil, timeout: 60)
        let signatureStatus = parseSignatureStatus(signature.standardOutputText + signature.standardErrorText)

        let payload = try await runner.run(executable: pkgutil, arguments: ["--payload-files", packageURL.path], standardInput: nil, timeout: 120)
        let payloadFiles = payload.standardOutputText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if payload.exitCode != 0 {
            checks.append(PackageCheck(title: "Payload readable", passed: false, detail: payload.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let payloadSet = Set(payloadFiles)
        for expected in plan.expectedPayloadPaths {
            checks.append(PackageCheck(title: "Contains \(expected)", passed: payloadSet.contains(expected), detail: payloadSet.contains(expected) ? "Present" : "Missing from the payload"))
        }

        let expandRoot = FileManager.default.temporaryDirectory.appendingPathComponent("EnrollmentBundleStudio-Verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: expandRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: expandRoot) }
        let expanded = expandRoot.appendingPathComponent("expanded", isDirectory: true)
        let expand = try await runner.run(executable: pkgutil, arguments: ["--expand", packageURL.path, expanded.path], standardInput: nil, timeout: 300)
        var identifier = ""
        var version = ""
        if expand.exitCode == 0, let info = try? String(contentsOf: expanded.appendingPathComponent("PackageInfo"), encoding: .utf8) {
            let metadata = parsePackageInfo(info)
            identifier = metadata.identifier
            version = metadata.version
            checks.append(PackageCheck(title: "Package identifier", passed: identifier == plan.packageIdentifier, detail: identifier.isEmpty ? "Not found" : identifier))
            checks.append(PackageCheck(title: "Package version", passed: version == plan.packageVersion, detail: version.isEmpty ? "Not found" : version))
            checks.append(PackageCheck(title: "preinstall script", passed: metadata.hasPreinstall, detail: metadata.hasPreinstall ? "Included" : "Missing"))
            checks.append(PackageCheck(title: "postinstall script", passed: metadata.hasPostinstall, detail: metadata.hasPostinstall ? "Included" : "Missing"))
        } else {
            checks.append(PackageCheck(title: "Package metadata", passed: false, detail: "pkgutil --expand failed: \(expand.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines))"))
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: packageURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return PackageVerification(
            packagePath: packageURL.path,
            sizeBytes: size,
            sha256: try InstallerImporter.sha256(of: packageURL),
            identifier: identifier,
            version: version,
            signatureStatus: signatureStatus,
            payloadFileCount: payloadFiles.filter { $0 != "." }.count,
            checks: checks
        )
    }

    /// pkgutil prints "Status: no signature" for unsigned packages.
    static func parseSignatureStatus(_ output: String) -> String {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Status:") {
                let status = trimmed.dropFirst("Status:".count).trimmingCharacters(in: .whitespaces)
                return status == "no signature" ? "Unsigned (flat package, signing not used)" : status
            }
        }
        return "Unknown"
    }

    struct PackageInfoMetadata: Equatable {
        let identifier: String
        let version: String
        let hasPreinstall: Bool
        let hasPostinstall: Bool
    }

    /// Reads the attributes of the <pkg-info> element and the <scripts> entries of a PackageInfo file.
    static func parsePackageInfo(_ xml: String) -> PackageInfoMetadata {
        // The attribute must follow whitespace: a word boundary (\b) would also match after the hyphen in
        // format-version="2", which pkgutil writes before version="…".
        func attribute(_ name: String) -> String {
            guard let pkgInfo = xml.range(of: "<pkg-info[^>]*>", options: .regularExpression) else { return "" }
            let element = String(xml[pkgInfo])
            guard let regex = try? NSRegularExpression(pattern: "\\s\(name)=\"([^\"]*)\""),
                  let match = regex.firstMatch(in: element, range: NSRange(element.startIndex..., in: element)),
                  let value = Range(match.range(at: 1), in: element) else {
                return ""
            }
            return String(element[value])
        }
        return PackageInfoMetadata(
            identifier: attribute("identifier"),
            version: attribute("version"),
            hasPreinstall: xml.range(of: "<preinstall\\b", options: .regularExpression) != nil,
            hasPostinstall: xml.range(of: "<postinstall\\b", options: .regularExpression) != nil
        )
    }
}
