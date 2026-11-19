import XCTest
@testable import EnrollmentBundleStudio

final class DetectionAppTests: XCTestCase {
    private func project(organization: String = "Contoso Ltd", directory: String? = nil) -> EnrollmentProject {
        var project = TestSupport.makeProject()
        project.settings.organizationName = organization
        project.settings.packageIdentifier = "com.contoso.enrollment.bundle"
        project.settings.bundleIdentifier = "com.contoso.enrollment"
        project.settings.packageVersion = "2.1.0"
        project.settings.installLocation = "/Library/Application Support/Contoso/Enrollment/"
        project.settings.detectionAppDirectory = directory
        return project
    }

    func testDefaultsToTheInstallLocation() {
        let app = FrameworkGenerator.detectionApp(project: project())
        XCTAssertEqual(app.name, "Contoso-Ltd-Bundle.app")
        XCTAssertEqual(app.directory, "/Library/Application Support/Contoso/Enrollment")
        XCTAssertEqual(app.path, "/Library/Application Support/Contoso/Enrollment/Contoso-Ltd-Bundle.app")
    }

    func testConfiguredFolderAndEmptyOrganization() {
        XCTAssertEqual(FrameworkGenerator.detectionApp(project: project(directory: "/Applications/")).path, "/Applications/Contoso-Ltd-Bundle.app")
        XCTAssertEqual(FrameworkGenerator.detectionApp(project: project(directory: "  ")).directory, "/Library/Application Support/Contoso/Enrollment")
        XCTAssertEqual(FrameworkGenerator.detectionApp(project: project(organization: "")).name, "Enrollment-Bundle.app")
    }

    func testInfoPlistCarriesThePackageIdentifierAndVersion() throws {
        let files = try FrameworkGenerator.detectionAppFiles(project: project())
        let info = try XCTUnwrap(files.first { $0.path.hasSuffix("Contents/Info.plist") })
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: info.contents, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.contoso.enrollment.bundle")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "2.1.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "2.1.0")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "marker")
        let executable = try XCTUnwrap(files.first { $0.path.hasSuffix("Contents/MacOS/marker") })
        XCTAssertTrue(executable.isExecutable)
        XCTAssertTrue(String(decoding: executable.contents, as: UTF8.self).hasPrefix("#!/bin/sh\n"))
    }

    func testConfigurationRecordsThePathForUninstall() {
        let text = FrameworkGenerator.configurationFile(project: project(directory: "/Applications"),
                                                        installDirectory: "/Library/Application Support/Contoso/Enrollment",
                                                        now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.contains("detection_app='/Applications/Contoso-Ltd-Bundle.app'"))
    }

    func testPackagePlanPlacesAndExpectsTheApp() {
        let plan = PackagePlan(project: project(directory: "/Applications"), outputDirectory: URL(fileURLWithPath: "/tmp/out"))
        let payload = URL(fileURLWithPath: "/tmp/payload")
        XCTAssertEqual(plan.payloadDetectionApp(in: payload).path, "/tmp/payload/Applications/Contoso-Ltd-Bundle.app")
        XCTAssertTrue(plan.expectedPayloadPaths.contains("./Applications/Contoso-Ltd-Bundle.app/Contents/Info.plist"))

        let inside = PackagePlan(project: project(), outputDirectory: URL(fileURLWithPath: "/tmp/out"))
        XCTAssertEqual(inside.payloadDetectionApp(in: payload).path,
                       "/tmp/payload/Library/Application Support/Contoso/Enrollment/Contoso-Ltd-Bundle.app")
    }

    func testDirectoryValidation() {
        XCTAssertNil(FieldValidator.detectionDirectoryIssue(""))
        XCTAssertNil(FieldValidator.detectionDirectoryIssue("/Applications"))
        XCTAssertNil(FieldValidator.detectionDirectoryIssue("/Library/Application Support/Contoso/Enrollment"))
        XCTAssertNotNil(FieldValidator.detectionDirectoryIssue("Applications"))
        XCTAssertNotNil(FieldValidator.detectionDirectoryIssue("/"))
        XCTAssertNotNil(FieldValidator.detectionDirectoryIssue("/System/Library"))
        XCTAssertNotNil(FieldValidator.detectionDirectoryIssue("/Applications/../etc"))
        XCTAssertNotNil(FieldValidator.detectionDirectoryIssue("/Applications//X"))
        XCTAssertNotNil(FieldValidator.detectionDirectoryIssue("/Applications/Foo.app"))
    }

    func testValidationReportsABadDetectionFolder() {
        var bad = project(directory: "/")
        bad.settings.outputDirectoryPath = "/tmp"
        let report = ValidationEngine.validate(project: bad, assets: [:], environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.component == "Detection app folder" })
    }

    func testOlderProjectsWithoutTheSettingDecode() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertNil(settings["detectionAppDirectory"], "Nothing is written until it is set")
        settings.removeValue(forKey: "detectionAppDirectory")
        object["settings"] = settings
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object)).project
        XCTAssertNil(loaded.settings.detectionAppDirectory)
    }
}
