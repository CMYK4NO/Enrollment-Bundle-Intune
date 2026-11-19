import XCTest
@testable import EnrollmentBundleStudio

final class CompletionCommandTests: XCTestCase {
    private func configuration(_ project: EnrollmentProject) throws -> String {
        let framework = try FrameworkGenerator.generate(project: project, assets: [:], installerSources: [:])
        return try XCTUnwrap(framework.text(at: "framework/config/enrollment.conf"))
    }

    func testDefaultOpensCompanyPortalAsUser() {
        let branding = Branding.makeDefault()
        XCTAssertEqual(branding.completionCommand, "open -a \"Company Portal\"")
        XCTAssertTrue(branding.completionCommandRunsAsUser)
    }

    func testCommandIsWrittenToConfiguration() throws {
        var project = TestSupport.makeProject()
        project.branding.completionCommand = "  open -a \"Company Portal\"  "
        let text = try configuration(project)
        XCTAssertTrue(text.contains("completion_command="))
        XCTAssertTrue(text.contains("Company Portal"))
        XCTAssertTrue(text.contains("completion_command_as_user="))
    }

    func testEmptyCommandProducesEmptyAssignment() throws {
        var project = TestSupport.makeProject()
        project.branding.completionCommand = ""
        let text = try configuration(project)
        XCTAssertTrue(text.contains("completion_command=''") || text.contains("completion_command=\"\""))
    }

    func testProjectsSavedWithoutTheFieldsGetDefaults() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        var branding = try XCTUnwrap(object["branding"] as? [String: Any])
        branding.removeValue(forKey: "completionCommand")
        branding.removeValue(forKey: "completionCommandRunsAsUser")
        object["branding"] = branding
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object))
        XCTAssertEqual(loaded.project.branding.completionCommand, "")
        XCTAssertTrue(loaded.project.branding.completionCommandRunsAsUser)
    }

    func testCommandSurvivesEncodingRoundTrip() throws {
        var project = TestSupport.makeProject()
        project.branding.completionCommand = "open -a Safari"
        project.branding.completionCommandRunsAsUser = false
        let object = try TestSupport.projectJSONObject(project)
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object))
        XCTAssertEqual(loaded.project.branding.completionCommand, "open -a Safari")
        XCTAssertFalse(loaded.project.branding.completionCommandRunsAsUser)
    }
}

final class ProjectPackageImportTests: XCTestCase {
    func testProjectDocumentCanBeImportedAsConfiguration() throws {
        var project = TestSupport.makeProject()
        project.branding.completionCommand = "open -a Safari"
        let document = EnrollmentProjectDocument(project: project, assets: [:])
        let result = try ConfigurationArchive.importResult(from: document)
        XCTAssertEqual(result.project.branding.completionCommand, "open -a Safari")
        XCTAssertFalse(result.hasErrors)
    }

    func testReadOnlyNewerSchemaProjectIsRefused() throws {
        var project = TestSupport.makeProject()
        project.schemaVersion = AppInfo.currentSchemaVersion + 1
        let data = try ProjectCoding.encode(project)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            ProjectLayout.projectFileName: FileWrapper(regularFileWithContents: data)
        ])
        let document = try EnrollmentProjectDocument(fileWrapper: wrapper)
        XCTAssertThrowsError(try ConfigurationArchive.importResult(from: document))
    }
}

final class DefaultExecutionOrderTests: XCTestCase {
    func testNewApplicationsStartAfterScripts() throws {
        let project = TestSupport.makeProject()
        let portal = try XCTUnwrap(project.allApplications.first)
        XCTAssertEqual(portal.execution.executionOrder, TaskExecutionOptions.defaultApplicationOrder)
        XCTAssertEqual(ApplicationItem.makeCustom(strategy: .detectionOnly, timeoutSeconds: 300).execution.executionOrder,
                       TaskExecutionOptions.defaultApplicationOrder)
    }

    func testImportedScriptsAreNumberedFrom100AndRunBeforeApplications() throws {
        let document = try TestSupport.makeProjectWithScript()
        let script = try XCTUnwrap(document.project.scripts.first)
        let portal = try XCTUnwrap(document.project.allApplications.first)
        XCTAssertEqual(script.execution.executionOrder, 100)
        XCTAssertLessThan(script.execution.executionOrder, portal.execution.executionOrder)
        XCTAssertEqual(document.project.nextScriptExecutionOrder, 110)
    }

    func testFinalValidationStaysLast() {
        let project = TestSupport.makeProject()
        let final = project.systemTasks.first { $0.type == .finalValidation }
        XCTAssertEqual(final?.execution.executionOrder, 900)
    }
}
