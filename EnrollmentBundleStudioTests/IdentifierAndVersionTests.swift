import XCTest
@testable import EnrollmentBundleStudio

final class IdentifierAndVersionTests: XCTestCase {
    func testOrganizationLabel() {
        XCTAssertEqual(IdentifierSuggestion.label(forOrganization: "Contoso"), "contoso")
        XCTAssertEqual(IdentifierSuggestion.label(forOrganization: "Contoso & Partners, Ltd."), "contosopartnersltd")
        XCTAssertEqual(IdentifierSuggestion.label(forOrganization: "Café Zürich"), "cafezurich")
        XCTAssertEqual(IdentifierSuggestion.label(forOrganization: "  "), "example")
        XCTAssertEqual(IdentifierSuggestion.label(forOrganization: "日本"), "example")
        XCTAssertLessThanOrEqual(IdentifierSuggestion.label(forOrganization: String(repeating: "a", count: 200)).count, 40)
    }

    func testSuggestedIdentifiersAreValidReverseDNS() {
        for name in ["Contoso", "3M", "A", "Acme Inc."] {
            XCTAssertTrue(FieldValidator.isValidReverseDNS(IdentifierSuggestion.packageIdentifier(forOrganization: name)), name)
            XCTAssertTrue(FieldValidator.isValidReverseDNS(IdentifierSuggestion.bundleIdentifier(forOrganization: name)), name)
        }
        XCTAssertEqual(IdentifierSuggestion.packageIdentifier(forOrganization: "Contoso"), "com.contoso.enrollment.bundle")
        XCTAssertEqual(IdentifierSuggestion.bundleIdentifier(forOrganization: "Contoso"), "com.contoso.enrollment")
    }

    func testIdentifiersFollowTheOrganizationName() {
        var settings = ProjectSettings.makeDefault()
        XCTAssertEqual(settings.packageIdentifier, "com.example.enrollment.bundle")
        settings.setOrganizationName("Contoso")
        XCTAssertEqual(settings.packageIdentifier, "com.contoso.enrollment.bundle")
        XCTAssertEqual(settings.bundleIdentifier, "com.contoso.enrollment")
        settings.setOrganizationName("Fabrikam")
        XCTAssertEqual(settings.packageIdentifier, "com.fabrikam.enrollment.bundle")
        settings.setOrganizationName("")
        XCTAssertEqual(settings.packageIdentifier, "com.example.enrollment.bundle")
    }

    func testTypingCharacterByCharacterEndsOnTheFinalName() {
        var settings = ProjectSettings.makeDefault()
        for prefix in ["C", "Co", "Con", "Cont", "Conto", "Contos", "Contoso"] {
            settings.organizationNameLinkedToIdentifiers = prefix
        }
        XCTAssertEqual(settings.packageIdentifier, "com.contoso.enrollment.bundle")
        XCTAssertEqual(settings.bundleIdentifier, "com.contoso.enrollment")
    }

    func testManuallyEditedIdentifierIsLeftAlone() {
        var settings = ProjectSettings.makeDefault()
        settings.setOrganizationName("Contoso")
        settings.packageIdentifier = "com.contoso.custom.package"
        settings.setOrganizationName("Fabrikam")
        XCTAssertEqual(settings.packageIdentifier, "com.contoso.custom.package")
        XCTAssertEqual(settings.bundleIdentifier, "com.fabrikam.enrollment", "The other identifier still follows")
    }

    func testVersionIsSharedByPackageAndBundle() {
        var project = EnrollmentProject.makeDefault()
        project.setVersion("2.1.0")
        XCTAssertEqual(project.settings.packageVersion, "2.1.0")
        XCTAssertEqual(project.projectVersion, "2.1.0")
    }

    func testGeneratedFilesUseThePackageVersionForTheBundleToo() throws {
        var project = TestSupport.makeProject()
        project.settings.packageVersion = "3.4.5"
        project.projectVersion = "9.9.9"
        let framework = try FrameworkGenerator.generate(project: project, assets: [:], installerSources: [:])
        let configuration = try ShellLiteralReader.assignments(in: try XCTUnwrap(framework.text(at: "framework/config/enrollment.conf")))
        XCTAssertEqual(configuration["bundle_version"], "3.4.5")
        XCTAssertEqual(configuration["package_version"], "3.4.5")
    }

    func testSavedProjectKeepsBothVersionsEqual() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        document.project.settings.packageVersion = "4.0.0"
        document.project.projectVersion = "1.0.0"
        let reopened = try EnrollmentProjectDocument(fileWrapper: try document.makeFileWrapper(existing: nil))
        XCTAssertEqual(reopened.project.projectVersion, "4.0.0")
    }

    func testOnlyMacOS26And27AreOffered() {
        XCTAssertEqual(ProjectSettings.supportedMinimumMacOSVersions.map { $0.version }, ["26.0", "27.0"])
        XCTAssertEqual(ProjectSettings.makeDefault().minimumMacOSVersion, "26.0")
    }

    func testOlderMinimumIsRaisedOnOpenWithANote() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        document.project.settings.minimumMacOSVersion = "14.0"
        let reopened = try EnrollmentProjectDocument(fileWrapper: try document.makeFileWrapper(existing: nil))
        XCTAssertEqual(reopened.project.settings.minimumMacOSVersion, "26.0")
        XCTAssertTrue(reopened.loadNotes.contains { $0.contains("14.0") && $0.contains("26.0") })
    }

    func testMacOS27IsKept() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        document.project.settings.minimumMacOSVersion = "27.0"
        let reopened = try EnrollmentProjectDocument(fileWrapper: try document.makeFileWrapper(existing: nil))
        XCTAssertEqual(reopened.project.settings.minimumMacOSVersion, "27.0")
        XCTAssertFalse(reopened.loadNotes.contains { $0.contains("minimum macOS") })
    }

    func testExistingMicrosoft365ItemGetsTheBundledIcon() throws {
        var project = TestSupport.makeProject()
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        project.addCatalogEntries([entry], target: .categoryGroups)
        var document = EnrollmentProjectDocument(project: project, assets: [:])
        let png = try TestSupport.makePNG()
        document.applyBundledCatalogIcons(iconData: { $0.id == "microsoft-365" ? png : nil })
        let item = try XCTUnwrap(document.project.allApplications.first { $0.catalogID == "microsoft-365" })
        XCTAssertEqual(item.icon.kind, .projectAsset)
        XCTAssertNotNil(document.assets[item.icon.value])
    }

    func testChosenIconIsNeverReplaced() throws {
        var project = TestSupport.makeProject()
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        project.addCatalogEntries([entry], target: .categoryGroups)
        var item = try XCTUnwrap(project.allApplications.first)
        item.icon = IconSource(kind: .sfSymbol, value: "star")
        _ = project.updateApplication(item)
        var document = EnrollmentProjectDocument(project: project, assets: [:])
        document.applyBundledCatalogIcons(iconData: { _ in try? TestSupport.makePNG() })
        XCTAssertEqual(document.project.allApplications.first?.icon, IconSource(kind: .sfSymbol, value: "star"))
    }
}
