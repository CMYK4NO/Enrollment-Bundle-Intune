import XCTest
@testable import EnrollmentBundleStudio

final class InstallerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A file with a flat-package (xar) header. It is never installed or opened; only read and hashed.
    private func makeFakePackage(named name: String = "Example Tool.pkg", payload: String = "payload") throws -> URL {
        let url = directory.appendingPathComponent(name)
        var data = Data(InstallerImporter.xarMagic)
        data.append(Data(payload.utf8))
        try data.write(to: url)
        return url
    }

    private func makeDocumentWithBundledApp() -> (EnrollmentProjectDocument, UUID) {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        var item = ApplicationItem.makeCustom(strategy: .bundledInstaller, timeoutSeconds: 900)
        item.displayName = "Example Tool"
        item.applicationPath = "/Applications/Example Tool.app"
        item.taskIdentifier = "app.example-tool"
        let groupID = document.project.addGroup(named: "Custom Applications")
        document.project.addApplication(item, toGroup: groupID)
        return (document, item.id)
    }

    func testInspectFlatPackage() throws {
        let url = try makeFakePackage()
        let inspection = try InstallerImporter.inspect(at: url)
        XCTAssertEqual(inspection.originalFilename, "Example Tool.pkg")
        XCTAssertEqual(inspection.sizeBytes, Int64(InstallerImporter.xarMagic.count + 7))
        XCTAssertEqual(inspection.sha256, Hashing.sha256Hex(try Data(contentsOf: url)))
    }

    func testStreamingHashMatchesForMultiChunkFiles() throws {
        let url = directory.appendingPathComponent("big.pkg")
        var data = Data(InstallerImporter.xarMagic)
        data.append(Data(repeating: 0xAB, count: InstallerImporter.chunkSize * 2 + 17))
        try data.write(to: url)
        XCTAssertEqual(try InstallerImporter.inspect(at: url).sha256, Hashing.sha256Hex(data))
    }

    func testRejectsNonPackages() throws {
        let text = directory.appendingPathComponent("notes.pkg")
        try Data("hello".utf8).write(to: text)
        XCTAssertThrowsError(try InstallerImporter.inspect(at: text)) { error in
            XCTAssertEqual(error as? InstallerImportError, .notAFlatPackage("notes.pkg"))
        }
        let wrongExtension = directory.appendingPathComponent("tool.dmg")
        try Data(InstallerImporter.xarMagic).write(to: wrongExtension)
        XCTAssertThrowsError(try InstallerImporter.inspect(at: wrongExtension)) { error in
            XCTAssertEqual(error as? InstallerImportError, .notAPackage("tool.dmg"))
        }
        let bundle = directory.appendingPathComponent("Legacy.pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try InstallerImporter.inspect(at: bundle)) { error in
            XCTAssertEqual(error as? InstallerImportError, .bundlePackage("Legacy.pkg"))
        }
        let empty = directory.appendingPathComponent("empty.pkg")
        try Data().write(to: empty)
        XCTAssertThrowsError(try InstallerImporter.inspect(at: empty)) { error in
            XCTAssertEqual(error as? InstallerImportError, .emptyFile)
        }
    }

    func testInstallerPathsAreSafeAndUnique() {
        XCTAssertEqual(InstallerImporter.installerPath(for: "Example Tool.pkg", existingPaths: []), "Installers/Example-Tool.pkg")
        XCTAssertEqual(InstallerImporter.installerPath(for: "Example Tool.pkg", existingPaths: ["Installers/Example-Tool.pkg"]), "Installers/Example-Tool-2.pkg")
        XCTAssertEqual(InstallerImporter.installerPath(for: "../../evil.pkg", existingPaths: []), "Installers/evil.pkg")
        XCTAssertTrue(InstallerImporter.isSafeInstallerPath("Installers/a.pkg"))
        XCTAssertFalse(InstallerImporter.isSafeInstallerPath("Installers/../a.pkg"))
        XCTAssertFalse(InstallerImporter.isSafeInstallerPath("Scripts/a.pkg"))
        XCTAssertFalse(InstallerImporter.isSafeInstallerPath("Installers/a.sh"))
    }

    func testAttachSaveAndReopen() throws {
        let packageURL = try makeFakePackage()
        var (document, appID) = makeDocumentWithBundledApp()
        document.attachInstaller(PendingInstaller(sourceURL: packageURL, inspection: try InstallerImporter.inspect(at: packageURL)), toApplication: appID)
        let reference = try XCTUnwrap(document.project.application(id: appID)?.installer)
        XCTAssertEqual(reference.relativePath, "Installers/Example-Tool.pkg")

        let projectURL = directory.appendingPathComponent("Test.ebsproject", isDirectory: true)
        try document.makeFileWrapper(existing: nil).write(to: projectURL, options: .atomic, originalContentsURL: nil)
        let copied = projectURL.appendingPathComponent("Installers/Example-Tool.pkg")
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: packageURL), "The package is copied into the project")

        let reopened = try EnrollmentProjectDocument(fileWrapper: try FileWrapper(url: projectURL, options: []))
        XCTAssertNotNil(reopened.installerSources["Installers/Example-Tool.pkg"])
        XCTAssertTrue(reopened.loadNotes.isEmpty, "\(reopened.loadNotes)")
        let report = ValidationEngine.validate(project: reopened.project, assets: reopened.assets, environment: .permissive,
                                               installerPaths: Set(reopened.installerSources.keys))
        XCTAssertFalse(report.issues.contains { $0.message.contains("installer") && $0.severity == .error })
    }

    func testSavingAgainAfterTheOriginalPackageWasDeletedKeepsTheCopy() throws {
        let packageURL = try makeFakePackage()
        let original = try Data(contentsOf: packageURL)
        var (document, appID) = makeDocumentWithBundledApp()
        document.attachInstaller(PendingInstaller(sourceURL: packageURL, inspection: try InstallerImporter.inspect(at: packageURL)), toApplication: appID)

        let projectURL = directory.appendingPathComponent("Test.ebsproject", isDirectory: true)
        try document.makeFileWrapper(existing: nil).write(to: projectURL, options: .atomic, originalContentsURL: nil)
        try FileManager.default.removeItem(at: packageURL)

        document.project.settings.projectName = "Edited after the original was deleted"
        let saved = try document.makeFileWrapper(existing: try FileWrapper(url: projectURL, options: .immediate))
        let resaved = directory.appendingPathComponent("Resaved.ebsproject", isDirectory: true)
        try saved.write(to: resaved, options: .atomic, originalContentsURL: nil)
        XCTAssertEqual(try Data(contentsOf: resaved.appendingPathComponent("Installers/Example-Tool.pkg")), original)
    }

    func testReplacingAndRemovingInstaller() throws {
        let first = try makeFakePackage(named: "One.pkg")
        let second = try makeFakePackage(named: "Two.pkg", payload: "other")
        var (document, appID) = makeDocumentWithBundledApp()
        document.attachInstaller(PendingInstaller(sourceURL: first, inspection: try InstallerImporter.inspect(at: first)), toApplication: appID)
        document.attachInstaller(PendingInstaller(sourceURL: second, inspection: try InstallerImporter.inspect(at: second)), toApplication: appID)
        XCTAssertEqual(Set(document.installerSources.keys), ["Installers/Two.pkg"], "The replaced package is dropped")

        let wrapper = try document.makeFileWrapper(existing: nil)
        XCTAssertEqual(Set(wrapper.fileWrappers?["Installers"]?.fileWrappers?.keys.map { $0 } ?? []), ["Two.pkg"])

        document.project.removeApplication(id: appID)
        document.removeInstallerIfUnreferenced("Installers/Two.pkg")
        XCTAssertTrue(document.installerSources.isEmpty)
        let saved = try document.makeFileWrapper(existing: wrapper)
        XCTAssertEqual(saved.fileWrappers?["Installers"]?.fileWrappers?.isEmpty, true, "Unreferenced packages are removed on save")
    }

    func testValidationOfBundledInstaller() throws {
        var (document, appID) = makeDocumentWithBundledApp()
        var report = ValidationEngine.validate(project: document.project, assets: document.assets, environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.message.contains("no installer package is attached") },
                      "Optional app: warning")

        var item = try XCTUnwrap(document.project.application(id: appID))
        item.execution.isRequired = true
        item.installer = InstallerReference(relativePath: "Installers/Missing.pkg", originalFilename: "Missing.pkg",
                                            sha256: "00", sizeBytes: 1, importedAt: Date(timeIntervalSince1970: 0))
        document.project.updateApplication(item)
        report = ValidationEngine.validate(project: document.project, assets: document.assets, environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("missing from the project") })
        XCTAssertTrue(report.issues.contains { $0.component == "Completion button" && $0.message.contains("installer package") })
    }

    func testUnsafeInstallerReferenceIsRemovedOnOpen() throws {
        var project = TestSupport.makeProject()
        project.applicationGroups[0].applications[0].installer = InstallerReference(
            relativePath: "../../etc/evil.pkg", originalFilename: "evil.pkg", sha256: "", sizeBytes: 0, importedAt: Date(timeIntervalSince1970: 0))
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let projectFile = FileWrapper(regularFileWithContents: try ProjectCoding.encode(project))
        projectFile.preferredFilename = "project.json"
        _ = root.addFileWrapper(projectFile)
        let document = try EnrollmentProjectDocument(fileWrapper: root)
        XCTAssertNil(document.project.allApplications.first?.installer)
        XCTAssertTrue(document.loadNotes.contains { $0.contains("unsafe installer") })
    }

    func testExportClearsInstallerReferences() throws {
        let packageURL = try makeFakePackage()
        var (document, appID) = makeDocumentWithBundledApp()
        document.attachInstaller(PendingInstaller(sourceURL: packageURL, inspection: try InstallerImporter.inspect(at: packageURL)), toApplication: appID)
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"base64\" : \"eGFyIQ"), "Package bytes are never exported")
        let result = try ConfigurationArchive.parse(data)
        XCTAssertNil(result.project.application(id: appID)?.installer)
        XCTAssertTrue(result.issues.contains { $0.message.contains("Attach it again") })
    }

    func testNewProjectCopyKeepsInstallers() throws {
        let packageURL = try makeFakePackage()
        var (document, appID) = makeDocumentWithBundledApp()
        document.attachInstaller(PendingInstaller(sourceURL: packageURL, inspection: try InstallerImporter.inspect(at: packageURL)), toApplication: appID)
        XCTAssertEqual(document.asNewProject().installerSources.keys.sorted(), ["Installers/Example-Tool.pkg"])
    }

    func testEqualityIgnoresNothingImportant() throws {
        let document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        var changed = document
        XCTAssertEqual(document, changed)
        changed.project.settings.projectName = "Other"
        XCTAssertNotEqual(document, changed)
    }
}

final class PackageMetadataTests: XCTestCase {
    private let packageInfo = """
    <?xml version="1.0" encoding="utf-8"?>
    <pkg-info overwrite-permissions="true" relocatable="false" identifier="com.example.tool.pkg" version="1.2.3" install-location="/Applications" auth="root">
      <payload numberOfFiles="10" installKBytes="100"/>
      <bundle-version>
        <bundle id="com.example.tool" CFBundleIdentifier="com.example.tool" path="./Example Tool.app" CFBundleVersion="1"/>
        <bundle id="com.example.helper" path="./Example Tool.app/Contents/Library/Helper.app"/>
      </bundle-version>
      <upgrade-bundle>
        <bundle id="com.example.old" path="./Old.app"/>
      </upgrade-bundle>
    </pkg-info>
    """

    func testParsesApplicationReceiptAndIdentifier() {
        let metadata = PackageMetadataParser.parse(packageInfos: [Data(packageInfo.utf8)])
        XCTAssertEqual(metadata.receipts, [PackageReceipt(identifier: "com.example.tool.pkg", version: "1.2.3", installLocation: "/Applications")])
        XCTAssertEqual(metadata.applications, [
            PackageApplication(bundleIdentifier: "com.example.tool", path: "/Applications/Example Tool.app", receiptIdentifier: "com.example.tool.pkg",
                               infoPlistPath: "Example Tool.app/Contents/Info.plist")
        ], "Nested helper apps and upgrade-bundle entries are ignored")
        XCTAssertEqual(metadata.receiptIdentifier(for: metadata.applications.first), "com.example.tool.pkg")
    }

    /// Taken from the PackageInfo files of a real GlobalProtect.pkg: the install location is the app itself.
    private let globalProtectMain = """
    <pkg-info overwrite-permissions="true" relocatable="false" identifier="com.paloaltonetworks.globalprotect.pkg" postinstall-action="none" version="6.3.3-1199" format-version="2" install-location="/Applications/GlobalProtect.app" auth="root">
      <bundle-version>
        <bundle path="./Contents/Resources/gplock.kext" id="com.paloaltonetworks.GlobalProtect.gplock" CFBundleVersion="6.3.3f1199"/>
        <bundle path="./Contents/Library/SystemExtensions/com.paloaltonetworks.GlobalProtect.client.extension.systemextension" id="com.paloaltonetworks.GlobalProtect.client.extension" CFBundleVersion="1"/>
      </bundle-version>
      <upgrade-bundle>
        <bundle id="com.paloaltonetworks.GlobalProtect.gplock"/>
      </upgrade-bundle>
    </pkg-info>
    """
    private let globalProtectUninstall = "<pkg-info identifier=\"com.paloaltonetworks.globalprotect.uninstall.pkg\" version=\"0\" auth=\"root\"><bundle-version/></pkg-info>"

    func testApplicationThatIsTheInstallLocationIsFound() {
        let metadata = PackageMetadataParser.parse(packageInfos: [
            Data(globalProtectMain.utf8), Data(globalProtectUninstall.utf8)
        ])
        XCTAssertEqual(metadata.receipts.count, 2)
        XCTAssertEqual(metadata.applications.count, 1, "Kernel extensions and system extensions inside the app are not applications")
        let application = metadata.applications[0]
        XCTAssertEqual(application.path, "/Applications/GlobalProtect.app")
        XCTAssertEqual(application.receiptIdentifier, "com.paloaltonetworks.globalprotect.pkg")
        XCTAssertEqual(application.bundleIdentifier, "", "PackageInfo does not record the app's own identifier")
        XCTAssertEqual(application.infoPlistPath, "Contents/Info.plist")
        XCTAssertEqual(metadata.receiptIdentifier(for: application), "com.paloaltonetworks.globalprotect.pkg")
    }

    func testInfoPlistIdentifierIsValidated() throws {
        let good = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.paloaltonetworks.GlobalProtect.client"], format: .xml, options: 0)
        let unexpanded = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)"], format: .xml, options: 0)
        XCTAssertEqual(PackageMetadataParser.bundleIdentifier(fromInfoPlist: good), "com.paloaltonetworks.GlobalProtect.client")
        XCTAssertNil(PackageMetadataParser.bundleIdentifier(fromInfoPlist: unexpanded))
        XCTAssertNil(PackageMetadataParser.bundleIdentifier(fromInfoPlist: Data("garbage".utf8)))
    }

    func testRootInstallLocationKeepsThePathInsideThePackage() {
        let xml = """
        <pkg-info identifier="com.example.root" version="1" install-location="/">
          <bundle-version><bundle id="com.example.root.app" path="./Applications/Root.app"/></bundle-version>
        </pkg-info>
        """
        let metadata = PackageMetadataParser.parse(packageInfos: [Data(xml.utf8)])
        XCTAssertEqual(metadata.applications.first?.path, "/Applications/Root.app")
    }

    func testMissingInstallLocationDefaultsToRoot() {
        XCTAssertEqual(PackageMetadataParser.absolutePath(installLocation: "", bundlePath: "./Applications/Foo.app"), "/Applications/Foo.app")
        XCTAssertEqual(PackageMetadataParser.absolutePath(installLocation: "/Applications/", bundlePath: "Foo.app"), "/Applications/Foo.app")
    }

    func testPathsThatClimbOutAreRejected() {
        XCTAssertNil(PackageMetadataParser.absolutePath(installLocation: "/Applications", bundlePath: "../../etc/Foo.app"))
    }

    func testOnlyTopLevelApplicationsCount() {
        XCTAssertTrue(PackageMetadataParser.isTopLevelApplication("/Applications/Foo.app"))
        XCTAssertTrue(PackageMetadataParser.isTopLevelApplication("/Applications/Utilities/Foo.APP"))
        XCTAssertFalse(PackageMetadataParser.isTopLevelApplication("/Applications/Foo.app/Contents/Helper.app"))
        XCTAssertFalse(PackageMetadataParser.isTopLevelApplication("/Library/Foo.framework"))
    }

    func testSeveralComponentsGiveSeveralApplicationsAndReceipts() {
        let second = packageInfo
            .replacingOccurrences(of: "com.example.tool.pkg", with: "com.example.other.pkg")
            .replacingOccurrences(of: "Example Tool.app", with: "Other.app")
            .replacingOccurrences(of: "com.example.tool\"", with: "com.example.other\"")
        let metadata = PackageMetadataParser.parse(packageInfos: [Data(packageInfo.utf8), Data(second.utf8)])
        XCTAssertEqual(metadata.receipts.count, 2)
        XCTAssertEqual(metadata.applications.map { $0.path }, ["/Applications/Example Tool.app", "/Applications/Other.app"])
        XCTAssertNil(metadata.receiptIdentifier(for: nil), "No guess when the package has several receipts")
        XCTAssertEqual(metadata.receiptIdentifier(for: metadata.applications[1]), "com.example.other.pkg")
    }

    func testSingleReceiptIsSuggestedWithoutAnApplication() {
        let xml = "<pkg-info identifier=\"com.example.driver\" version=\"2\" install-location=\"/\"><payload/></pkg-info>"
        let metadata = PackageMetadataParser.parse(packageInfos: [Data(xml.utf8)])
        XCTAssertTrue(metadata.applications.isEmpty)
        XCTAssertEqual(metadata.receiptIdentifier(for: nil), "com.example.driver")
    }

    func testBrokenXMLIsIgnored() {
        XCTAssertEqual(PackageMetadataParser.parse(packageInfos: [Data("<pkg-info".utf8), Data("not xml".utf8)]), PackageMetadata())
    }

    func testPackageInfoNamesAreFilteredForSafety() {
        let listing = "Distribution\nExample.pkg\nExample.pkg/PackageInfo\nExample.pkg/Payload\nPackageInfo\n/etc/PackageInfo\n../x/PackageInfo\nExample.pkg/PackageInfo\n"
        XCTAssertEqual(PackageMetadataReader.packageInfoNames(in: listing), ["Example.pkg/PackageInfo", "PackageInfo"])
    }

    func testReaderExtractsOnlyPackageInfoWithoutAShell() async throws {
        let package = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pkg")
        try Data(InstallerImporter.xarMagic).write(to: package)
        defer { try? FileManager.default.removeItem(at: package) }
        let xml = packageInfo
        let runner = MockCommandRunner(handler: { executable, arguments in
            XCTAssertEqual(executable, "/usr/bin/xar")
            if arguments.first == "-t" {
                return CommandResult(exitCode: 0, standardOutput: Data("Distribution\nExample.pkg/PackageInfo\nExample.pkg/Payload\n".utf8),
                                     standardError: Data(), timedOut: false)
            }
            let folder = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "-C")! + 1])
            let file = folder.appendingPathComponent("Example.pkg/PackageInfo")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: file)
            return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data(), timedOut: false)
        })
        let metadata = try await PackageMetadataReader(runner: runner).read(at: package)
        XCTAssertEqual(metadata.applications.first?.path, "/Applications/Example Tool.app")
        XCTAssertEqual(metadata.applications.first?.bundleIdentifier, "com.example.tool")
        XCTAssertEqual(metadata.receiptIdentifier(for: metadata.applications.first), "com.example.tool.pkg")
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments.last, "Example.pkg/PackageInfo", "Only PackageInfo is extracted, never the payload")
    }

    func testReaderReadsTheBundleIdentifierFromThePayloadWhenPackageInfoLacksIt() async throws {
        let package = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pkg")
        try Data(InstallerImporter.xarMagic).write(to: package)
        defer { try? FileManager.default.removeItem(at: package) }
        let main = globalProtectMain
        let uninstall = globalProtectUninstall
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.paloaltonetworks.GlobalProtect.client"],
                                                       format: .xml, options: 0)
        let runner = MockCommandRunner(handler: { executable, arguments in
            let ok = CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data(), timedOut: false)
            if executable == "/usr/bin/xar", arguments.first == "-t" {
                let listing = "gp.pkg\ngp.pkg/Bom\ngp.pkg/Payload\ngp.pkg/Scripts\ngp.pkg/PackageInfo\ngp_uninstall.pkg\ngp_uninstall.pkg/PackageInfo\nDistribution\n"
                return CommandResult(exitCode: 0, standardOutput: Data(listing.utf8), standardError: Data(), timedOut: false)
            }
            if executable == "/usr/bin/xar" {
                let folder = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "-C")! + 1])
                for name in arguments.suffix(from: arguments.firstIndex(of: "-C")! + 2) {
                    let file = folder.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    switch name {
                    case "gp.pkg/PackageInfo": try Data(main.utf8).write(to: file)
                    case "gp_uninstall.pkg/PackageInfo": try Data(uninstall.utf8).write(to: file)
                    default: try Data("payload".utf8).write(to: file)
                    }
                }
                return ok
            }
            XCTAssertEqual(executable, "/usr/bin/bsdtar")
            let output = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "-C")! + 1])
            XCTAssertEqual(arguments.last, "./Contents/Info.plist")
            try FileManager.default.createDirectory(at: output.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try plist.write(to: output.appendingPathComponent("Contents/Info.plist"))
            return ok
        })
        let metadata = try await PackageMetadataReader(runner: runner).read(at: package)
        XCTAssertEqual(metadata.applications.count, 1)
        XCTAssertEqual(metadata.applications[0].path, "/Applications/GlobalProtect.app")
        XCTAssertEqual(metadata.applications[0].bundleIdentifier, "com.paloaltonetworks.GlobalProtect.client")
        XCTAssertEqual(metadata.applications[0].component, "gp.pkg")
        XCTAssertEqual(metadata.receiptIdentifier(for: metadata.applications[0]), "com.paloaltonetworks.globalprotect.pkg")
        XCTAssertEqual(runner.calls.filter { $0.executable == "/usr/bin/bsdtar" }.count, 1)
        XCTAssertTrue(runner.calls.contains { $0.arguments.last == "gp.pkg/Payload" }, "Only the component that holds the app is extracted")
    }

    func testReaderKeepsGoingWhenThePayloadCannotBeRead() async throws {
        let package = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pkg")
        try Data(InstallerImporter.xarMagic).write(to: package)
        defer { try? FileManager.default.removeItem(at: package) }
        let main = globalProtectMain
        let runner = MockCommandRunner(handler: { executable, arguments in
            if arguments.first == "-t" {
                return CommandResult(exitCode: 0, standardOutput: Data("gp.pkg/Payload\ngp.pkg/PackageInfo\n".utf8), standardError: Data(), timedOut: false)
            }
            if executable == "/usr/bin/xar" {
                let folder = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "-C")! + 1])
                let file = folder.appendingPathComponent(arguments.last ?? "")
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(arguments.last == "gp.pkg/PackageInfo" ? main.utf8 : "payload".utf8).write(to: file)
            }
            // bsdtar finds nothing.
            return CommandResult(exitCode: executable == "/usr/bin/bsdtar" ? 1 : 0, standardOutput: Data(), standardError: Data(), timedOut: false)
        })
        let metadata = try await PackageMetadataReader(runner: runner).read(at: package)
        XCTAssertEqual(metadata.applications.first?.path, "/Applications/GlobalProtect.app")
        XCTAssertEqual(metadata.applications.first?.bundleIdentifier, "", "Left empty for the administrator to enter")
    }

    func testReaderReportsAToolFailure() async throws {
        let package = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pkg")
        try Data(InstallerImporter.xarMagic).write(to: package)
        defer { try? FileManager.default.removeItem(at: package) }
        let runner = MockCommandRunner(result: CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data(), timedOut: false))
        do {
            _ = try await PackageMetadataReader(runner: runner).read(at: package)
            XCTFail("Expected a failure")
        } catch {
            XCTAssertTrue(error is PackageMetadataError)
        }
    }
}


final class DisplayNameSuggestionTests: XCTestCase {
    func testPrefersTheApplicationInThePackage() {
        XCTAssertEqual(DisplayNameSuggestion.suggest(packageApplicationPath: "/Applications/Microsoft Edge.app",
                                                     applicationPath: "/Applications/Other.app",
                                                     packageFilename: "Edge-1.pkg"), "Microsoft Edge")
    }

    func testUsesTheApplicationPathWhenThePackageHasNoApplication() {
        XCTAssertEqual(DisplayNameSuggestion.suggest(packageApplicationPath: nil,
                                                     applicationPath: "/Applications/zoom.us.app",
                                                     packageFilename: "Zoom.pkg"), "zoom.us")
    }

    func testFallsBackToThePackageNameWithoutExtension() {
        XCTAssertEqual(DisplayNameSuggestion.suggest(packageApplicationPath: nil, applicationPath: "/Applications/",
                                                     packageFilename: "FreshServiceAgent 6.1.0-DT.pkg"), "FreshServiceAgent 6.1.0-DT")
        XCTAssertEqual(DisplayNameSuggestion.suggest(packageApplicationPath: nil, applicationPath: "",
                                                     packageFilename: "DT Fonts.PKG"), "DT Fonts")
        XCTAssertEqual(DisplayNameSuggestion.suggest(packageApplicationPath: nil, applicationPath: "", packageFilename: ""), "")
    }
}
