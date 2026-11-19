import XCTest
@testable import EnrollmentBundleStudio

/// Simulates pkgbuild and pkgutil. pkgbuild records the payload it was given; pkgutil reports that payload.
/// No package is built and nothing is installed.
final class FakePackageTools {
    var payloadFiles: [String] = []
    var scriptNames: [String] = []
    var identifier = ""
    var version = ""
    var pkgbuildExitCode: Int32 = 0
    var dropFromPayload: String?

    static func ok(_ text: String = "") -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: Data(text.utf8), standardError: Data(), timedOut: false)
    }

    func handle(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        if executable == PackagePlan.pkgbuild {
            guard pkgbuildExitCode == 0 else {
                return CommandResult(exitCode: pkgbuildExitCode, standardOutput: Data(), standardError: Data("pkgbuild: error: bad root".utf8), timedOut: false)
            }
            let root = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--root")! + 1])
            let scripts = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--scripts")! + 1])
            identifier = arguments[arguments.firstIndex(of: "--identifier")! + 1]
            version = arguments[arguments.firstIndex(of: "--version")! + 1]
            payloadFiles = ["."] + listFiles(root)
            if let dropFromPayload { payloadFiles.removeAll { $0 == dropFromPayload } }
            scriptNames = (try? FileManager.default.contentsOfDirectory(atPath: scripts.path))?.sorted() ?? []
            try Data("xar!fake package".utf8).write(to: URL(fileURLWithPath: arguments.last!))
            return Self.ok()
        }
        switch arguments.first {
        case "--check-signature":
            return CommandResult(exitCode: 1, standardOutput: Data("Package \"built.pkg\":\n   Status: no signature\n".utf8), standardError: Data(), timedOut: false)
        case "--payload-files":
            return Self.ok(payloadFiles.joined(separator: "\n") + "\n")
        case "--expand":
            let target = URL(fileURLWithPath: arguments[2])
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let scriptsXML = scriptNames.map { "<\($0) file=\"./\($0)\"/>" }.joined()
            let info = "<?xml version=\"1.0\"?><pkg-info format-version=\"2\" identifier=\"\(identifier)\" version=\"\(version)\" install-location=\"/\" auth=\"root\"><scripts>\(scriptsXML)</scripts></pkg-info>"
            try Data(info.utf8).write(to: target.appendingPathComponent("PackageInfo"))
            return Self.ok()
        default:
            return CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data("unexpected".utf8), timedOut: false)
        }
    }

    private func listFiles(_ root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var paths: [String] = []
        while let relative = enumerator.nextObject() as? String {
            paths.append("./" + relative)
        }
        return paths.sorted()
    }
}

final class PackagePlanTests: XCTestCase {
    private func project() -> EnrollmentProject {
        var project = TestSupport.makeProject()
        project.settings.packageIdentifier = "com.contoso.enrollment.bundle"
        project.settings.bundleIdentifier = "com.contoso.enrollment"
        project.settings.packageDisplayName = "Contoso Enrollment"
        project.settings.packageVersion = "1.2.0"
        project.settings.installLocation = "/Library/Application Support/Contoso/Enrollment/"
        return project
    }

    func testPathsAndArguments() {
        let plan = PackagePlan(project: project(), outputDirectory: URL(fileURLWithPath: "/tmp/out", isDirectory: true))
        XCTAssertEqual(plan.packageURL.path, "/tmp/out/Contoso-Enrollment-1.2.0.pkg")
        XCTAssertEqual(plan.reportURL.path, "/tmp/out/Contoso-Enrollment-1.2.0-build-report.txt")
        XCTAssertEqual(plan.installLocation, "/Library/Application Support/Contoso/Enrollment")
        let payload = URL(fileURLWithPath: "/stage/payload", isDirectory: true)
        XCTAssertEqual(plan.payloadFrameworkDirectory(in: payload).path, "/stage/payload/Library/Application Support/Contoso/Enrollment")
        XCTAssertEqual(plan.payloadLaunchDaemon(in: payload).path, "/stage/payload/Library/LaunchDaemons/com.contoso.enrollment.plist")
        XCTAssertEqual(
            plan.pkgbuildArguments(payload: payload, scripts: URL(fileURLWithPath: "/stage/scripts"), output: URL(fileURLWithPath: "/stage/built.pkg")),
            ["--root", "/stage/payload", "--scripts", "/stage/scripts", "--identifier", "com.contoso.enrollment.bundle",
             "--version", "1.2.0", "--install-location", "/", "--ownership", "recommended", "/stage/built.pkg"]
        )
        XCTAssertFalse(plan.pkgbuildArguments(payload: payload, scripts: payload, output: payload).contains("--sign"), "Packages are not signed")
        XCTAssertTrue(plan.expectedPayloadPaths.contains("./Library/Application Support/Contoso/Enrollment/enrollment.sh"))
        XCTAssertTrue(plan.expectedPayloadPaths.contains("./Library/LaunchDaemons/com.contoso.enrollment.plist"))
        XCTAssertEqual(PackagePlan.allowedTools, ["/usr/bin/pkgbuild", "/usr/sbin/pkgutil"])
    }

    func testTestCommandsQuotePaths() {
        let commands = TestCommands.make(exportFolder: "/Users/me/It's here/Export", installLocation: "/Library/Application Support/X")
        XCTAssertTrue(commands.contains("EXPORT='/Users/me/It'\\''s here/Export'"))
        XCTAssertTrue(commands.contains("INSTALL='/Library/Application Support/X'"))
        XCTAssertTrue(commands.contains(#"sudo cp -R "$EXPORT/framework/." "$INSTALL/""#))
        XCTAssertTrue(commands.contains(#"sudo "$INSTALL/enrollment.sh" --dry-run"#))
    }
}

final class PackageVerifierTests: XCTestCase {
    func testParsesSignatureAndPackageInfo() {
        XCTAssertEqual(PackageVerifier.parseSignatureStatus("Package \"x.pkg\":\n   Status: no signature\n"), "Unsigned (flat package, signing not used)")
        XCTAssertEqual(PackageVerifier.parseSignatureStatus("nothing"), "Unknown")
        let info = PackageVerifier.parsePackageInfo(#"<pkg-info format-version="2" identifier="com.x.y" version="1.0.0" auth="root"><scripts><preinstall file="./preinstall"/><postinstall file="./postinstall"/></scripts></pkg-info>"#)
        XCTAssertEqual(info, PackageVerifier.PackageInfoMetadata(identifier: "com.x.y", version: "1.0.0", hasPreinstall: true, hasPostinstall: true))
        XCTAssertFalse(PackageVerifier.parsePackageInfo(#"<pkg-info identifier="a" version="1"></pkg-info>"#).hasPostinstall)
        // Real pkgutil output: format-version and generator-version must not be mistaken for version.
        let real = PackageVerifier.parsePackageInfo(#"""
        <?xml version="1.0" encoding="utf-8"?>
        <pkg-info overwrite-permissions="true" relocatable="false" identifier="com.contoso.enrollment.bundle" postinstall-action="none" version="1.4.2" format-version="2" generator-version="InstallCmds-866" install-location="/" auth="root">
            <scripts><preinstall file="./preinstall"/><postinstall file="./postinstall"/></scripts>
        </pkg-info>
        """#)
        XCTAssertEqual(real.identifier, "com.contoso.enrollment.bundle")
        XCTAssertEqual(real.version, "1.4.2")
    }
}

final class PackageBuilderTests: XCTestCase {
    private var directory: URL!
    private var output: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        output = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDocument() throws -> EnrollmentProjectDocument {
        try TestSupport.makeGeneratorProject(packageURL: try TestSupport.makeFakePackage(in: directory))
    }

    private func build(_ document: EnrollmentProjectDocument, tools: FakePackageTools, validation: ValidationReport = ValidationReport(issues: []),
                       replace: Bool = false, removed: ((URL) -> Void)? = nil) async throws -> PackageBuildResult {
        var builder = PackageBuilder(runner: MockCommandRunner(handler: tools.handle))
        builder.removeExisting = { url in
            removed?(url)
            try FileManager.default.removeItem(at: url)
        }
        builder.now = { Date(timeIntervalSince1970: 1_794_000_000) }
        return try await builder.build(project: document.project, assets: document.assets, installerSources: document.installerSources,
                                       validation: validation, outputDirectory: output, replaceExisting: replace)
    }

    func testBuildsVerifiesAndReports() async throws {
        let document = try makeDocument()
        let tools = FakePackageTools()
        let result = try await build(document, tools: tools)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.packageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURL.path))
        XCTAssertEqual(result.packageURL.lastPathComponent, "Enrollment-Bundle-1.0.0.pkg")
        XCTAssertTrue(result.verification.passed, "\(result.verification.checks.filter { !$0.passed })")
        XCTAssertEqual(result.verification.identifier, "com.contoso.enrollment.bundle")
        XCTAssertEqual(result.verification.signatureStatus, "Unsigned (flat package, signing not used)")
        XCTAssertEqual(result.verification.sha256, Hashing.sha256Hex(try Data(contentsOf: result.packageURL)))

        // The payload pkgbuild received mirrors the target volume.
        XCTAssertTrue(tools.payloadFiles.contains("./Library/Application Support/Contoso/Enrollment/enrollment.sh"))
        XCTAssertTrue(tools.payloadFiles.contains("./Library/Application Support/Contoso/Enrollment/installers/Example-Tool.pkg"))
        XCTAssertTrue(tools.payloadFiles.contains("./Library/LaunchDaemons/com.contoso.enrollment.plist"))
        XCTAssertEqual(tools.scriptNames, ["postinstall", "preinstall"])

        XCTAssertEqual(result.record.packageVersion, "1.0.0")
        XCTAssertEqual(result.record.sha256, result.verification.sha256)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        XCTAssertEqual(leftovers, ["Enrollment-Bundle-1.0.0-build-report.txt", "Enrollment-Bundle-1.0.0.pkg"], "Only the package and report land in the output folder")
    }

    func testReportContentsAndNoScriptSource() async throws {
        let document = try makeDocument()
        let result = try await build(document, tools: FakePackageTools())
        let report = try String(contentsOf: result.reportURL, encoding: .utf8)
        for expected in ["Project ID", document.project.id.uuidString, "Package identifier", "com.contoso.enrollment.bundle",
                         "SHA-256", result.verification.sha256, "Unsigned", "Verification", "Passed", "Required (", "Optional (",
                         "framework/enrollment.sh", "script.checkexample"] {
            XCTAssertTrue(report.contains(expected), "Report is missing \(expected)")
        }
        XCTAssertFalse(report.contains("/Applications/Example.app\" ]; then"), "Script contents are never copied into the report")
    }

    func testBlockedByValidationErrors() async throws {
        let document = try makeDocument()
        let error = ValidationReport(issues: [ValidationIssue(severity: .error, area: .project, component: "X", message: "Y", remediation: "Z")])
        do {
            _ = try await build(document, tools: FakePackageTools(), validation: error)
            XCTFail("Expected a validation block")
        } catch {
            XCTAssertEqual(error as? PackageBuildError, .blockedByValidation(1))
        }
    }

    func testExistingPackageNeedsConfirmation() async throws {
        let document = try makeDocument()
        let first = try await build(document, tools: FakePackageTools())
        do {
            _ = try await build(document, tools: FakePackageTools())
            XCTFail("Expected packageExists")
        } catch {
            XCTAssertEqual(error as? PackageBuildError, .packageExists(first.packageURL.path))
        }
        var removed: [String] = []
        _ = try await build(document, tools: FakePackageTools(), replace: true, removed: { removed.append($0.lastPathComponent) })
        XCTAssertEqual(removed.sorted(), ["Enrollment-Bundle-1.0.0-build-report.txt", "Enrollment-Bundle-1.0.0.pkg"])
    }

    func testPkgbuildFailureLeavesNothingBehind() async throws {
        let document = try makeDocument()
        let tools = FakePackageTools()
        tools.pkgbuildExitCode = 1
        do {
            _ = try await build(document, tools: tools)
            XCTFail("Expected pkgbuild failure")
        } catch {
            XCTAssertEqual(error as? PackageBuildError, .pkgbuildFailed("pkgbuild: error: bad root"))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    func testVerificationFailureLeavesNothingBehind() async throws {
        let document = try makeDocument()
        let tools = FakePackageTools()
        tools.dropFromPayload = "./Library/LaunchDaemons/com.contoso.enrollment.plist"
        do {
            _ = try await build(document, tools: tools)
            XCTFail("Expected verification failure")
        } catch {
            guard case .verificationFailed(let failures)? = error as? PackageBuildError else { return XCTFail("\(error)") }
            XCTAssertTrue(failures.contains { $0.contains("LaunchDaemons") })
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
}

final class BuildHistoryStoreTests: XCTestCase {
    func testAppendReadRemove() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BuildHistoryStore(directory: directory)
        let projectID = UUID()
        XCTAssertTrue(store.records(for: projectID).isEmpty)
        func record(_ seconds: TimeInterval) -> BuildRecord {
            BuildRecord(id: UUID(), builtAt: Date(timeIntervalSince1970: seconds), packagePath: "/p.pkg", reportPath: "/r.txt",
                        sha256: "abc", sizeBytes: 10, packageIdentifier: "com.x.y", packageVersion: "1.0", bundleVersion: "1.0",
                        verificationPassed: true, warningCount: 0, applicationVersion: "1.0.0")
        }
        let older = record(1_000)
        let newer = record(2_000)
        try store.append(older, for: projectID)
        try store.append(newer, for: projectID)
        XCTAssertEqual(store.records(for: projectID).map { $0.id }, [newer.id, older.id], "Newest first")
        XCTAssertTrue(store.records(for: UUID()).isEmpty, "History is per project")
        try store.remove(recordID: older.id, for: projectID)
        XCTAssertEqual(store.records(for: projectID).map { $0.id }, [newer.id])
    }
}

final class ZshSupportTests: XCTestCase {
    func testZshScriptsImportWithoutFindings() {
        let inspection = ScriptInspector.inspect(Data("#!/bin/zsh\nsetopt extended_glob\nprint -r -- ${(U)name}\n".utf8))
        XCTAssertEqual(inspection.shell, .zsh)
        XCTAssertTrue(inspection.findings.isEmpty, "\(inspection.findings)")
    }

    func testShellCheckWarningOnlyForCheckableScripts() throws {
        var environment = ValidationEnvironment.permissive
        environment.shellCheckPath = nil
        let zsh = try TestSupport.makeProjectWithScript("#!/bin/zsh\necho hi\n", name: "Setup.zsh")
        XCTAssertFalse(ValidationEngine.validate(project: zsh.project, assets: zsh.assets, environment: environment)
            .issues.contains { $0.component == "ShellCheck" })
        let bash = try TestSupport.makeProjectWithScript()
        XCTAssertTrue(ValidationEngine.validate(project: bash.project, assets: bash.assets, environment: environment)
            .issues.contains { $0.component == "ShellCheck" })
    }
}
