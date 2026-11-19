import XCTest
@testable import EnrollmentBundleStudio

final class ProjectCodingTests: XCTestCase {
    func testDefaultProjectRoundTrips() throws {
        let project = TestSupport.makeProject()
        let data = try ProjectCoding.encode(project)
        let loaded = try ProjectCoding.load(data)
        XCTAssertEqual(loaded.project, project)
        XCTAssertFalse(loaded.isReadOnly)
        XCTAssertTrue(loaded.notes.isEmpty)
    }

    func testEncodedJSONIsReadableAndContainsVersionFields() throws {
        let data = try ProjectCoding.encode(TestSupport.makeProject())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"schemaVersion\" : \(AppInfo.currentSchemaVersion)"))
        XCTAssertTrue(text.contains("\"applicationVersion\""))
        XCTAssertTrue(text.contains("\"projectVersion\" : \"1.0.0\""))
        XCTAssertTrue(text.contains("\"accentColor\" : \"#0A64D2\""))
        XCTAssertTrue(text.contains("\n  "), "Output should be pretty-printed")
        XCTAssertFalse(text.contains("\\/"), "Slashes should not be escaped")
    }

    func testDatesUseISO8601() throws {
        let object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        let created = try XCTUnwrap(object["createdAt"] as? String)
        XCTAssertTrue(created.hasSuffix("Z"))
        XCTAssertNotNil(ISO8601DateFormatter().date(from: created))
    }

    func testNewerSchemaOpensReadOnly() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        object["schemaVersion"] = AppInfo.currentSchemaVersion + 1
        let loaded = try ProjectCoding.load(TestSupport.data(fromJSONObject: object))
        XCTAssertTrue(loaded.isReadOnly)
        XCTAssertFalse(loaded.notes.isEmpty)
    }

    func testNewerSchemaThatCannotBeDecodedIsRejected() throws {
        let data = Data("{\"schemaVersion\": 99, \"somethingNew\": true}".utf8)
        XCTAssertThrowsError(try ProjectCoding.load(data)) { error in
            XCTAssertEqual(error as? ProjectFileError, .newerSchemaUnreadable(99))
        }
    }

    func testOlderUnsupportedSchemaIsRejected() throws {
        let data = Data("{\"schemaVersion\": 0}".utf8)
        XCTAssertThrowsError(try ProjectCoding.load(data)) { error in
            XCTAssertEqual(error as? ProjectFileError, .unsupportedSchema(0))
        }
    }

    func testInvalidJSONIsRejected() {
        XCTAssertThrowsError(try ProjectCoding.load(Data("not json".utf8))) { error in
            guard case .invalidProjectFile = error as? ProjectFileError else {
                return XCTFail("Expected invalidProjectFile, got \(error)")
            }
        }
    }

    func testMissingKeyProducesReadableMessage() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "packageIdentifier")
        object["settings"] = settings
        XCTAssertThrowsError(try ProjectCoding.load(TestSupport.data(fromJSONObject: object))) { error in
            let description = (error as? ProjectFileError)?.errorDescription ?? ""
            XCTAssertTrue(description.contains("packageIdentifier"), description)
        }
    }

    func testWholeSecondsTruncatesFraction() {
        let date = Date(timeIntervalSince1970: 100.75)
        XCTAssertEqual(ProjectCoding.wholeSeconds(date).timeIntervalSince1970, 100)
    }
}
