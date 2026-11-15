import XCTest
@testable import EnrollmentBundleStudio

final class WindowAndLogoTests: XCTestCase {
    private func dialogJSON(_ project: EnrollmentProject, assets: [String: Data] = [:]) throws -> [String: Any] {
        let framework = try FrameworkGenerator.generate(project: project, assets: assets, installerSources: [:])
        let text = try XCTUnwrap(framework.text(at: "framework/config/dialog.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testBlurScreenIsOnByDefaultAndNeverFullScreen() throws {
        XCTAssertTrue(Branding.makeDefault().blurScreen)
        let json = try dialogJSON(TestSupport.makeProject())
        XCTAssertEqual(json["blurscreen"] as? Bool, true)
        XCTAssertNil(json["fullscreen"])
    }

    func testBlurScreenCanBeTurnedOff() throws {
        var project = TestSupport.makeProject()
        project.branding.blurScreen = false
        XCTAssertEqual(try dialogJSON(project)["blurscreen"] as? Bool, false)
    }

    func testProjectsSavedWithoutTheOptionGetBlurScreen() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        var branding = try XCTUnwrap(object["branding"] as? [String: Any])
        branding.removeValue(forKey: "blurScreen")
        object["branding"] = branding
        let data = try TestSupport.data(fromJSONObject: object)
        let loaded = try ProjectCoding.load(data)
        XCTAssertTrue(loaded.project.branding.blurScreen)
    }
}
