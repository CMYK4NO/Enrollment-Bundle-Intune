import XCTest
@testable import EnrollmentBundleStudio

final class DocumentPackageTests: XCTestCase {
    func testInMemoryRoundTripPreservesProjectAndAssets() throws {
        let png = try TestSupport.makePNG()
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        try document.replaceBrandingImage(.logo, data: png, path: "Branding/CompanyLogo.png")

        let wrapper = try document.makeFileWrapper(existing: nil)
        let reopened = try EnrollmentProjectDocument(fileWrapper: wrapper)

        XCTAssertEqual(reopened.project.branding.logoPath, "Branding/CompanyLogo.png")
        XCTAssertEqual(reopened.assets["Branding/CompanyLogo.png"], png)
        XCTAssertEqual(reopened.project.id, document.project.id)
        XCTAssertEqual(reopened.project.applicationGroups, document.project.applicationGroups)
        XCTAssertTrue(reopened.loadNotes.isEmpty, "\(reopened.loadNotes)")
    }

    func testWrapperHasHumanReadableLayout() throws {
        let wrapper = try EnrollmentProjectDocument(project: TestSupport.makeProject()).makeFileWrapper(existing: nil)
        let names = Set(wrapper.fileWrappers?.keys.map { $0 } ?? [])
        for expected in ["project.json", "Branding", "Icons", "Scripts", "Templates", "Generated", "Builds"] {
            XCTAssertTrue(names.contains(expected), "Missing \(expected)")
        }
    }

    func testDiskRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let packageURL = directory.appendingPathComponent("Test.ebsproject", isDirectory: true)

        let document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let wrapper = try document.makeFileWrapper(existing: nil)
        try wrapper.write(to: packageURL, options: .atomic, originalContentsURL: nil)

        let reread = try FileWrapper(url: packageURL, options: .immediate)
        let reopened = try EnrollmentProjectDocument(fileWrapper: reread)
        XCTAssertEqual(reopened.project.settings, document.project.settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("project.json").path))
    }

    func testSavePreservesUnmanagedFolders() throws {
        let document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let existing = try document.makeFileWrapper(existing: nil)
        let builds = try XCTUnwrap(existing.fileWrappers?["Builds"])
        let report = FileWrapper(regularFileWithContents: Data("report".utf8))
        report.preferredFilename = "EnrollmentBundle-1.0.0-build-report.txt"
        _ = builds.addFileWrapper(report)

        let saved = try document.makeFileWrapper(existing: existing)
        let preserved = saved.fileWrappers?["Builds"]?.fileWrappers?["EnrollmentBundle-1.0.0-build-report.txt"]
        XCTAssertEqual(preserved?.regularFileContents, Data("report".utf8))
    }

    func testRemovedAssetIsDeletedOnSave() throws {
        let png = try TestSupport.makePNG()
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        try document.replaceBrandingImage(.logo, data: png, path: "Branding/CompanyLogo.png")
        let first = try document.makeFileWrapper(existing: nil)
        XCTAssertNotNil(first.fileWrappers?["Branding"]?.fileWrappers?["CompanyLogo.png"])

        document.removeBrandingImage(.logo)
        let second = try document.makeFileWrapper(existing: first)
        XCTAssertNil(second.fileWrappers?["Branding"]?.fileWrappers?["CompanyLogo.png"])
        XCTAssertNil(document.assets["Branding/CompanyLogo.png"])
    }

    func testReplacingLogoWithDifferentFormatRemovesOldFile() throws {
        let png = try TestSupport.makePNG()
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        try document.replaceBrandingImage(.logo, data: png, path: "Branding/CompanyLogo.png")
        try document.replaceBrandingImage(.logo, data: png, path: "Branding/CompanyLogo.jpg")
        XCTAssertNil(document.assets["Branding/CompanyLogo.png"])
        XCTAssertNotNil(document.assets["Branding/CompanyLogo.jpg"])
    }

    func testReadOnlyDocumentRefusesToSave() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        object["schemaVersion"] = AppInfo.currentSchemaVersion + 1
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let projectFile = FileWrapper(regularFileWithContents: try TestSupport.data(fromJSONObject: object))
        projectFile.preferredFilename = "project.json"
        _ = root.addFileWrapper(projectFile)

        let document = try EnrollmentProjectDocument(fileWrapper: root)
        XCTAssertTrue(document.isReadOnly)
        XCTAssertThrowsError(try document.makeFileWrapper(existing: root)) { error in
            XCTAssertEqual(error as? ProjectFileError, .readOnlyProject(AppInfo.currentSchemaVersion + 1))
        }
    }

    func testUnsafeLogoReferenceIsClearedOnOpen() throws {
        var project = TestSupport.makeProject()
        project.branding.logoPath = "../../etc/passwd"
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let projectFile = FileWrapper(regularFileWithContents: try ProjectCoding.encode(project))
        projectFile.preferredFilename = "project.json"
        _ = root.addFileWrapper(projectFile)

        let document = try EnrollmentProjectDocument(fileWrapper: root)
        XCTAssertNil(document.project.branding.logoPath)
        XCTAssertTrue(document.loadNotes.contains { $0.contains("unsafe") })
    }

    func testMissingAssetIsReportedButReferenceKept() throws {
        var project = TestSupport.makeProject()
        project.branding.logoPath = "Branding/Missing.png"
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let projectFile = FileWrapper(regularFileWithContents: try ProjectCoding.encode(project))
        projectFile.preferredFilename = "project.json"
        _ = root.addFileWrapper(projectFile)

        let document = try EnrollmentProjectDocument(fileWrapper: root)
        XCTAssertEqual(document.project.branding.logoPath, "Branding/Missing.png")
        XCTAssertTrue(document.loadNotes.contains { $0.contains("missing") })
    }

    func testHiddenFilesAreIgnoredAndPreserved() throws {
        let document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let existing = try document.makeFileWrapper(existing: nil)
        let icons = try XCTUnwrap(existing.fileWrappers?["Icons"])
        let dsStore = FileWrapper(regularFileWithContents: Data([0x00]))
        dsStore.preferredFilename = ".DS_Store"
        _ = icons.addFileWrapper(dsStore)

        let reopened = try EnrollmentProjectDocument(fileWrapper: existing)
        XCTAssertNil(reopened.assets["Icons/.DS_Store"])
        let saved = try reopened.makeFileWrapper(existing: existing)
        XCTAssertNotNil(saved.fileWrappers?["Icons"]?.fileWrappers?[".DS_Store"])
    }

    func testRegularFileWherePackageExpectedIsRejected() {
        let file = FileWrapper(regularFileWithContents: Data("x".utf8))
        XCTAssertThrowsError(try EnrollmentProjectDocument(fileWrapper: file)) { error in
            XCTAssertEqual(error as? ProjectFileError, .notAProjectPackage)
        }
    }

    func testSetAssetRejectsTraversalAndNestedPaths() {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        XCTAssertThrowsError(try document.setAsset(Data(), at: "Icons/../../evil.png"))
        XCTAssertThrowsError(try document.setAsset(Data(), at: "Builds/x.pkg"))
        XCTAssertThrowsError(try document.setAsset(Data(), at: "Icons/sub/x.png"))
        XCTAssertNoThrow(try document.setAsset(Data([1]), at: "Icons/x.png"))
    }
}
