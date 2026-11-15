import XCTest
@testable import EnrollmentBundleStudio

final class OverlayIconTests: XCTestCase {
    private func png() throws -> Data { try TestSupport.makePNG() }

    func testDefaultHasNoOverlayIcon() {
        XCTAssertNil(EnrollmentProject.makeDefault().branding.overlayIconPath)
    }

    func testPathLivesInBrandingFolder() {
        XCTAssertEqual(AssetImporter.brandingPath(role: .overlay, format: .png), "Branding/OverlayIcon.png")
    }

    func testChooseReplaceAndRemove() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        try document.replaceBrandingImage(.overlay, data: try png(), path: "Branding/OverlayIcon.png")
        XCTAssertEqual(document.project.branding.overlayIconPath, "Branding/OverlayIcon.png")
        XCTAssertNotNil(document.assets["Branding/OverlayIcon.png"])
        XCTAssertTrue(document.project.referencedAssetPaths.contains("Branding/OverlayIcon.png"))

        document.removeBrandingImage(.overlay)
        XCTAssertNil(document.project.branding.overlayIconPath)
        XCTAssertNil(document.assets["Branding/OverlayIcon.png"], "The file is deleted once nothing references it")
    }

    func testFrameworkBundlesTheOverlayAndNamesItInTheDialogConfig() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        try document.replaceBrandingImage(.overlay, data: try png(), path: "Branding/OverlayIcon.png")
        let framework = try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: [:])
        let relative = FrameworkGenerator.iconRelativePath(for: "Branding/OverlayIcon.png")
        XCTAssertNotNil(framework.file(at: "framework/" + relative))
        let text = try XCTUnwrap(framework.text(at: "framework/config/dialog.json"))
        XCTAssertTrue(text.contains("\"overlayicon\""))
        XCTAssertTrue(text.contains("__INSTALL_DIR__/" + relative))
    }

    func testNoOverlayMeansNoOverlayKeyAndNoShellLogic() throws {
        let framework = try FrameworkGenerator.generate(project: TestSupport.makeProject(), assets: [:], installerSources: [:])
        let text = try XCTUnwrap(framework.text(at: "framework/config/dialog.json"))
        XCTAssertFalse(text.contains("overlayicon"))
        XCTAssertFalse(FrameworkTemplates.libraryDialog.contains("overlay"))
    }

    func testMissingOverlayFileIsAValidationError() {
        var project = TestSupport.makeProject()
        project.branding.overlayIconPath = "Branding/OverlayIcon.png"
        let report = ValidationEngine.validate(project: project, assets: [:], environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.component == "Overlay icon" })
    }
}
