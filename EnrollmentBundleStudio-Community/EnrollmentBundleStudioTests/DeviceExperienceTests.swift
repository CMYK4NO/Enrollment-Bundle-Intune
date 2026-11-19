import XCTest
@testable import EnrollmentBundleStudio

final class DeviceExperienceTests: XCTestCase {
    private func generated() throws -> GeneratedFramework {
        try FrameworkGenerator.generate(project: TestSupport.makeProject(), assets: [:], installerSources: [:])
    }

    func testMarkdownLineBreaks() {
        XCTAssertEqual(DialogConfigBuilder.markdownLineBreaks("A\nB\nC"), "A  \nB  \nC")
        XCTAssertEqual(DialogConfigBuilder.markdownLineBreaks("A\n\nB"), "A\n\nB")
        XCTAssertEqual(DialogConfigBuilder.markdownLineBreaks("A  \nB"), "A  \nB")
        XCTAssertEqual(DialogConfigBuilder.markdownLineBreaks("single line"), "single line")
        XCTAssertEqual(DialogConfigBuilder.markdownLineBreaks(""), "")
    }

    func testInfoboxLinesAreSeparatedInTheDialogConfiguration() throws {
        let framework = try generated()
        let json = try XCTUnwrap(framework.text(at: "framework/config/dialog.json"))
        XCTAssertTrue(json.contains("  \\n**Computer:**"), "Every infobox line ends with a markdown line break")
    }

    func testLogsAreReadableByTheUser() throws {
        let framework = try generated()
        let logging = try XCTUnwrap(framework.text(at: "framework/lib/logging.sh"))
        XCTAssertTrue(logging.contains("chmod 644 \"$logfile\""))
        XCTAssertFalse(logging.contains("chmod 600 \"$logfile\""))
        for path in ["package-scripts/preinstall", "package-scripts/postinstall", "intune/pre-install.sh"] {
            let script = try XCTUnwrap(framework.text(at: path), path)
            XCTAssertTrue(script.contains("chmod 644 \"$logfile\""), path)
            XCTAssertFalse(script.contains("chmod 600 \"$logfile\""), path)
        }
    }

    func testWallpaperFillsTheScreen() throws {
        let framework = try generated()
        let user = try XCTUnwrap(framework.text(at: "framework/lib/user.sh"))
        XCTAssertTrue(user.contains("NSWorkspaceDesktopImageScalingKey"))
        XCTAssertTrue(user.contains("numberWithInt(3)"), "NSImageScaleProportionallyUpOrDown")
        XCTAssertTrue(user.contains("NSWorkspaceDesktopImageAllowClippingKey"))
        XCTAssertTrue(user.contains("fingerprint=\"$fingerprint:fill\""))
    }
}
