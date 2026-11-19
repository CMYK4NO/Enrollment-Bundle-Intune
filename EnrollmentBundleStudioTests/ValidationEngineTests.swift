import XCTest
@testable import EnrollmentBundleStudio

final class ValidationEngineTests: XCTestCase {
    private func validProject() -> EnrollmentProject {
        var project = TestSupport.makeProject()
        project.settings.organizationName = "Contoso"
        project.settings.packageIdentifier = "com.contoso.enrollment.bundle"
        project.settings.bundleIdentifier = "com.contoso.enrollment"
        project.settings.outputDirectoryPath = "/tmp"
        return project
    }

    private func validate(_ project: EnrollmentProject, assets: [String: Data] = [:],
                          environment: ValidationEnvironment = .permissive) -> ValidationReport {
        ValidationEngine.validate(project: project, assets: assets, environment: environment)
    }

    private func messages(_ report: ValidationReport, _ severity: ValidationSeverity) -> [String] {
        report.issues.filter { $0.severity == severity }.map { "\($0.component): \($0.message)" }
    }

    func testReceiptDetectedAppNeedsNoApplicationPath() {
        var project = validProject()
        var item = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
        item.taskIdentifier = "app.dt-fonts"
        item.displayName = "DT Fonts"
        item.applicationPath = ""
        item.detection = TaskCheck(method: .packageReceipt, value: "dtfonts")
        project.applicationGroups[0].applications.append(item)
        let report = validate(project)
        XCTAssertFalse(messages(report, .error).contains { $0.contains("DT Fonts") }, "\(messages(report, .error))")
        item.detection = TaskCheck(method: .applicationPath, value: "")
        project.applicationGroups[0].applications[project.applicationGroups[0].applications.count - 1] = item
        XCTAssertTrue(messages(validate(project), .error).contains { $0.contains("DT Fonts") }, "Path detection still needs an absolute path")
    }

    func testValidProjectHasNoErrors() {
        let report = validate(validProject())
        XCTAssertEqual(report.errorCount, 0, "\(messages(report, .error))")
        XCTAssertFalse(report.blocksBuild)
    }

    func testDefaultProjectReportsMissingOrganizationAndPlaceholders() {
        let report = validate(TestSupport.makeProject())
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.component == "Organization name" })
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.component == "Identifiers" })
        XCTAssertTrue(report.blocksBuild)
    }

    func testIdentifierAndVersionErrors() {
        var project = validProject()
        project.settings.packageIdentifier = "bad"
        project.settings.packageVersion = "1.0-beta"
        let components = Set(validate(project).issues.filter { $0.severity == .error }.map { $0.component })
        XCTAssertTrue(components.isSuperset(of: ["Package identifier", "Package version"]))
    }

    func testIssuesCarrySeverityComponentAndRemediation() {
        let report = validate(TestSupport.makeProject())
        for issue in report.issues {
            XCTAssertFalse(issue.component.isEmpty)
            XCTAssertFalse(issue.message.isEmpty)
            XCTAssertFalse(issue.remediation.isEmpty)
        }
        let severities = report.issues.map { $0.severity.rawValue }
        XCTAssertEqual(severities, severities.sorted(by: >), "Errors come first")
    }

    func testMissingIconAndLogoAreErrors() {
        var project = validProject()
        project.branding.logoPath = "Branding/CompanyLogo.png"
        project.applicationGroups[0].applications[0].icon = IconSource(kind: .projectAsset, value: "Icons/Portal.png")
        let report = validate(project)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.component == "Company logo" })
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("Icons/Portal.png") })
    }

    func testRequiredTaskWithoutSuccessConditionBlocksUnlock() {
        var project = validProject()
        project.applicationGroups[0].applications[0].detection = TaskCheck(method: .customCommand, value: "")
        let report = validate(project)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("can never succeed") })
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.component == "Completion button" })
    }

    func testUnlockErrorDisappearsWhenLockIsOff() {
        var project = validProject()
        project.applicationGroups[0].applications[0].execution.dependencies = ["ghost"]
        XCTAssertTrue(validate(project).issues.contains { $0.component == "Completion button" })
        project.settings.lockCompletionButtonUntilRequiredComplete = false
        XCTAssertFalse(validate(project).issues.contains { $0.component == "Completion button" })
    }

    func testDependencyErrors() {
        var project = validProject()
        project.applicationGroups[0].applications[0].execution.dependencies = ["ghost"]
        let report = validate(project)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("ghost") })
    }

    func testScriptHashMismatchAndFindings() throws {
        var document = try TestSupport.makeProjectWithScript("#!/bin/bash\ndeclare -A apps\nsudo true\n", name: "Bad.sh")
        document.project.settings = validProject().settings
        let path = try XCTUnwrap(document.project.scripts.first?.relativePath)
        var report = validate(document.project, assets: document.assets)
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.message.contains("Associative arrays") })
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.message.contains("sudo") })

        try document.setAsset(Data("#!/bin/bash\necho changed\n".utf8), at: path)
        report = validate(document.project, assets: document.assets)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("SHA-256") })
    }

    func testUnsupportedInterpreterIsAnError() throws {
        var document = try TestSupport.makeProjectWithScript("#!/usr/bin/python3\nprint('hi')\n", name: "Py.sh")
        document.project.settings = validProject().settings
        let report = validate(document.project, assets: document.assets)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("Unsupported interpreter") })
    }

    func testEnvironmentWarnings() throws {
        let document = try TestSupport.makeProjectWithScript()
        var environment = ValidationEnvironment.permissive
        environment.shellCheckPath = nil
        environment.fileExists = { _ in false }
        environment.isWritableDirectory = { _ in false }
        let report = validate(document.project, assets: document.assets, environment: environment)
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.component == "ShellCheck" })
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.component == "swiftDialog" })
        XCTAssertTrue(report.issues.contains { $0.severity == .warning && $0.message.contains("does not exist on this Mac") })
    }

    func testOutputDirectory() {
        var project = validProject()
        var environment = ValidationEnvironment.permissive
        environment.isWritableDirectory = { _ in false }
        XCTAssertTrue(validate(project, environment: environment).issues.contains { $0.severity == .error && $0.component == "Output folder" })
        project.settings.outputDirectoryPath = ""
        XCTAssertFalse(validate(project).issues.contains { $0.component == "Output folder" })
        XCTAssertTrue(project.settings.effectiveOutputDirectoryPath.hasSuffix("Downloads"))
    }

    func testShortTimeoutWarning() {
        var project = validProject()
        project.applicationGroups[0].applications[0].execution.timeoutSeconds = 60
        XCTAssertTrue(validate(project).issues.contains { $0.severity == .warning && $0.message.contains("too short") })
    }

    func testWaitConditionNeedsCommand() {
        var project = validProject()
        project.addSystemTask(type: .waitCondition)
        let report = validate(project)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.message.contains("No validation command") })
    }

    func testReportDeduplicatesAndCounts() {
        let issue = ValidationIssue(severity: .warning, area: .project, component: "X", message: "Y", remediation: "Z")
        let report = ValidationReport(issues: [issue, issue])
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertEqual(report.warningCount, 1)
        XCTAssertFalse(report.blocksBuild)
    }
}
