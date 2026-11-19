import XCTest
@testable import EnrollmentBundleStudio

final class OnboardingGuardTests: XCTestCase {
    private func project(flag: String = ProjectSettings.defaultOnboardingFlagPath, hours: Int = 20) -> EnrollmentProject {
        var project = TestSupport.makeProject()
        project.settings.organizationName = "Contoso"
        project.settings.onboardingFlagPath = flag
        project.settings.enrollmentWindowHours = hours
        return project
    }

    func testDefaultFlagLocation() {
        let settings = ProjectSettings.makeDefault()
        XCTAssertEqual(settings.onboardingFlagPath, "/Library/Logs/Microsoft/IntuneScripts/onBoarding/onboarding.flag")
        XCTAssertEqual(settings.enrollmentWindowHours, 20)
    }

    func testIntunePreinstallScriptIsOutsideThePackagePayload() throws {
        let framework = try FrameworkGenerator.generate(project: project(), assets: [:], installerSources: [:])
        XCTAssertNotNil(framework.file(at: "intune/pre-install.sh"))
        XCTAssertEqual(framework.allPaths.filter { $0.hasPrefix("intune/") }, ["intune/pre-install.sh"])
        XCTAssertFalse(framework.allPaths.contains { $0.hasPrefix("framework/") && $0.contains("pre-install") })
    }

    func testGuardOffLeavesFlagEmpty() throws {
        let framework = try FrameworkGenerator.generate(project: project(flag: ""), assets: [:], installerSources: [:])
        let configuration = try ShellLiteralReader.assignments(in: try XCTUnwrap(framework.text(at: "framework/config/enrollment.conf")))
        XCTAssertEqual(configuration["onboarding_flag"], "")
    }

    func testFrameworkReceivesTheFlagPath() throws {
        let framework = try FrameworkGenerator.generate(project: project(), assets: [:], installerSources: [:])
        let configuration = try ShellLiteralReader.assignments(in: try XCTUnwrap(framework.text(at: "framework/config/enrollment.conf")))
        XCTAssertEqual(configuration["onboarding_flag"], ProjectSettings.defaultOnboardingFlagPath)
        XCTAssertEqual(configuration["enrollment_window_hours"], "20")
        let enrollment = FrameworkTemplates.enrollmentScript
        XCTAssertTrue(enrollment.contains("write_onboarding_flag \"$outcome\""), "Written after success")
        XCTAssertTrue(enrollment.contains("Already onboarded (flag present)"), "Skipped when present")
        XCTAssertTrue(FrameworkTemplates.uninstallScript.contains("Keeping the onboarding flag"), "Uninstall keeps it")
    }

    func testValidation() {
        let inside = project(flag: "/Library/Application Support/EnrollmentBundle/onboarding.flag")
        XCTAssertTrue(ValidationEngine.validate(project: inside, assets: [:], environment: .permissive)
            .issues.contains { $0.severity == .error && $0.component == "Onboarding flag" })
        XCTAssertTrue(ValidationEngine.validate(project: project(flag: "relative.flag"), assets: [:], environment: .permissive)
            .issues.contains { $0.severity == .error && $0.component == "Onboarding flag" })
        XCTAssertTrue(ValidationEngine.validate(project: project(flag: ""), assets: [:], environment: .permissive)
            .issues.contains { $0.severity == .information && $0.component == "Onboarding flag" })
        XCTAssertTrue(ValidationEngine.validate(project: project(hours: 0), assets: [:], environment: .permissive)
            .issues.contains { $0.severity == .error && $0.component == "Enrollment window" })
        XCTAssertFalse(ValidationEngine.validate(project: project(), assets: [:], environment: .permissive)
            .issues.contains { $0.component == "Onboarding flag" || $0.component == "Enrollment window" })
    }

    func testSchema3ProjectMigratesWithDefaults() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        object["schemaVersion"] = 3
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "onboardingFlagPath")
        settings.removeValue(forKey: "enrollmentWindowHours")
        object["settings"] = settings
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object))
        XCTAssertEqual(loaded.migratedFromVersion, 3)
        XCTAssertEqual(loaded.project.settings.onboardingFlagPath, ProjectSettings.defaultOnboardingFlagPath)
        XCTAssertEqual(loaded.project.settings.enrollmentWindowHours, 20)
        XCTAssertTrue(loaded.migrationSummary.contains { $0.contains("Schema 3 → 4") })
    }

    func testCurrentSchemaProjectWithoutWindowSettingGetsTheDefault() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "enrollmentWindowHours")
        object["settings"] = settings
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object))
        XCTAssertNil(loaded.migratedFromVersion)
        XCTAssertEqual(loaded.project.settings.enrollmentWindowHours, 20)
    }

    func testEnrollmentWindowIsCheckedInsideTheFramework() {
        let script = FrameworkTemplates.enrollmentScript
        XCTAssertTrue(script.contains("enrollment_window_ok()"))
        XCTAssertTrue(script.contains("profileIdentifier: Microsoft.Profiles.MDM"))
        XCTAssertTrue(script.contains("Not a fresh enrollment"))
        XCTAssertTrue(script.contains("first_run_pending"), "Only the first run is gated, so resumes are not blocked")
    }

    func testReportShowsTheGuard() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try TestSupport.makeGeneratorProject(packageURL: try TestSupport.makeFakePackage(in: directory))
        let output = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let tools = FakePackageTools()
        let builder = PackageBuilder(runner: MockCommandRunner(handler: tools.handle))
        let result = try await builder.build(project: document.project, assets: document.assets, installerSources: document.installerSources,
                                             validation: ValidationReport(issues: []), outputDirectory: output, replaceExisting: false)
        let report = try String(contentsOf: result.reportURL, encoding: .utf8)
        XCTAssertTrue(report.contains("Onboarding flag"))
        XCTAssertTrue(report.contains("20 hours"))
    }
}
