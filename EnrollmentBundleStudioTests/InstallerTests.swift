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

        let projectURL = directory.appendingPathComponent("Test.enrollmentproject", isDirectory: true)
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
