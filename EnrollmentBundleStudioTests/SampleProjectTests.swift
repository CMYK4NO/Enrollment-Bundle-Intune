import XCTest
@testable import EnrollmentBundleStudio

/// Verifies the sample project shipped in the repository opens cleanly.
final class SampleProjectTests: XCTestCase {
    private var sampleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SampleProjects/Contoso.enrollmentproject", isDirectory: true)
    }

    func testSampleProjectOpensWithoutNotes() throws {
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Sample project not found next to the test sources.")
        }
        let wrapper = try FileWrapper(url: sampleURL, options: .immediate)
        let document = try EnrollmentProjectDocument(fileWrapper: wrapper)
        XCTAssertFalse(document.isReadOnly)
        XCTAssertTrue(document.loadNotes.isEmpty, "\(document.loadNotes)")
        XCTAssertEqual(document.project.settings.organizationName, "Contoso")
        XCTAssertTrue(FieldValidator.isValidReverseDNS(document.project.settings.packageIdentifier))
        XCTAssertNotNil(document.assets["Branding/CompanyLogo.png"])
        XCTAssertEqual(document.project.schemaVersion, AppInfo.currentSchemaVersion)
        XCTAssertNil(document.migratedFromVersion)
        for script in document.project.scripts {
            let data = try XCTUnwrap(document.assets[script.relativePath])
            XCTAssertEqual(Hashing.sha256Hex(data), script.sha256, script.displayName)
            XCTAssertFalse(ScriptInspector.inspect(data).hasErrors, script.displayName)
        }
        let report = ValidationEngine.validate(project: document.project, assets: document.assets, environment: .permissive)
        XCTAssertEqual(report.errorCount, 0, "\(report.issues.filter { $0.severity == .error })")
        XCTAssertEqual(Set(document.project.allTaskIdentifiers).count, document.project.allApplications.count + document.project.systemTasks.count + document.project.scripts.count)
    }
}
