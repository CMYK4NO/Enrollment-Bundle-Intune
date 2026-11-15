import XCTest
@testable import EnrollmentBundleStudio

final class MigrationTests: XCTestCase {
    /// A schema 1 project.json: the current format minus the schema 2 script fields.
    private func schema1Data(withScript: Bool) throws -> Data {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        object["schemaVersion"] = 1
        if withScript {
            let execution = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(TaskExecutionOptions())))
            object["scripts"] = [[
                "id": UUID().uuidString,
                "taskIdentifier": "script.legacy",
                "displayName": "Legacy",
                "relativePath": "Scripts/Legacy.sh",
                "originalFilename": "Legacy.sh",
                "sha256": Hashing.sha256Hex(Data(TestSupport.cleanScript.utf8)),
                "interpreter": "/bin/bash",
                "successExitCodes": [0],
                "execution": execution
            ]]
        }
        return try TestSupport.data(fromJSONObject: object)
    }

    func testMigratorAddsSchema2Fields() throws {
        let result = try ProjectMigrator.migrate(try schema1Data(withScript: true), from: 1)
        XCTAssertEqual(result.fromVersion, 1)
        XCTAssertEqual(result.toVersion, AppInfo.currentSchemaVersion)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppInfo.currentSchemaVersion)
        let script = try XCTUnwrap((object["scripts"] as? [[String: Any]])?.first)
        XCTAssertEqual(script["sourceWasExecutable"] as? Bool, false)
        XCTAssertNotNil(script["importedAt"] as? String)
        XCTAssertTrue(result.summary.first?.contains("1 script") ?? false)
        XCTAssertTrue(result.summary.contains { $0.contains("Schema 2 → 3") })
    }

    func testLoadMigratesAndReportsSummary() throws {
        let loaded = try ProjectCoding.load(try schema1Data(withScript: true))
        XCTAssertEqual(loaded.migratedFromVersion, 1)
        XCTAssertFalse(loaded.isReadOnly)
        XCTAssertEqual(loaded.project.schemaVersion, AppInfo.currentSchemaVersion)
        XCTAssertEqual(loaded.project.scripts.first?.sourceWasExecutable, false)
        XCTAssertFalse(loaded.migrationSummary.isEmpty)
    }

    func testMissingStepIsReported() {
        let beyond = AppInfo.currentSchemaVersion + 1
        XCTAssertThrowsError(try ProjectMigrator.migrate(Data("{\"schemaVersion\": 1}".utf8), from: 1, to: beyond)) { error in
            XCTAssertEqual(error as? ProjectFileError, .migrationRequired(AppInfo.currentSchemaVersion))
        }
    }

    func testDocumentWritesBackupOnFirstSaveOnly() throws {
        let original = try schema1Data(withScript: false)
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let projectFile = FileWrapper(regularFileWithContents: original)
        projectFile.preferredFilename = "project.json"
        _ = root.addFileWrapper(projectFile)

        let document = try EnrollmentProjectDocument(fileWrapper: root)
        XCTAssertEqual(document.migratedFromVersion, 1)
        XCTAssertTrue(document.migrationSummary.contains { $0.contains("project.schema-1.backup.json") })

        let saved = try document.makeFileWrapper(existing: root)
        let backup = try XCTUnwrap(saved.fileWrappers?["project.schema-1.backup.json"])
        XCTAssertEqual(backup.regularFileContents, original, "The backup is the untouched original")

        let reopened = try EnrollmentProjectDocument(fileWrapper: saved)
        XCTAssertNil(reopened.migratedFromVersion, "The saved project is already current")
        XCTAssertEqual(reopened.project.schemaVersion, AppInfo.currentSchemaVersion)
    }

    func testExistingBackupIsNeverOverwritten() throws {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let projectFile = FileWrapper(regularFileWithContents: try schema1Data(withScript: false))
        projectFile.preferredFilename = "project.json"
        _ = root.addFileWrapper(projectFile)
        let oldBackup = FileWrapper(regularFileWithContents: Data("older backup".utf8))
        oldBackup.preferredFilename = "project.schema-1.backup.json"
        _ = root.addFileWrapper(oldBackup)

        let document = try EnrollmentProjectDocument(fileWrapper: root)
        let saved = try document.makeFileWrapper(existing: root)
        XCTAssertEqual(saved.fileWrappers?["project.schema-1.backup.json"]?.regularFileContents, Data("older backup".utf8))
    }

    func testSchema2ProjectMigratesToCurrent() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        object["schemaVersion"] = 2
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object))
        XCTAssertEqual(loaded.migratedFromVersion, 2)
        XCTAssertEqual(loaded.project.schemaVersion, AppInfo.currentSchemaVersion)
        XCTAssertNil(loaded.project.allApplications.first?.installer)
    }
}
