import XCTest
@testable import EnrollmentBundleStudio

final class FilenameSanitizerTests: XCTestCase {
    func testSanitizeKeepsSafeCharacters() {
        XCTAssertEqual(FilenameSanitizer.sanitize("Company Portal"), "Company-Portal")
        XCTAssertEqual(FilenameSanitizer.sanitize("Defender_v2.icon"), "Defender_v2.icon")
    }

    func testSanitizeFoldsAccentsAndCollapsesSeparators() {
        XCTAssertEqual(FilenameSanitizer.sanitize("Café   Logo!!"), "Cafe-Logo")
        XCTAssertEqual(FilenameSanitizer.sanitize("a..b"), "a.b")
    }

    func testSanitizeRemovesTraversal() {
        XCTAssertEqual(FilenameSanitizer.sanitize("../../etc/passwd"), "etc-passwd")
        XCTAssertEqual(FilenameSanitizer.sanitize(".."), "item")
        XCTAssertEqual(FilenameSanitizer.sanitize("/"), "item")
    }

    func testSanitizeFallbackAndLength() {
        XCTAssertEqual(FilenameSanitizer.sanitize("🙂🙂", fallback: "Icon"), "Icon")
        XCTAssertEqual(FilenameSanitizer.sanitize(String(repeating: "a", count: 100)).count, 64)
        XCTAssertEqual(FilenameSanitizer.sanitize(String(repeating: "a", count: 63) + "-b", maxLength: 64), String(repeating: "a", count: 63))
    }

    func testSlug() {
        XCTAssertEqual(FilenameSanitizer.slug("Microsoft Defender"), "microsoft-defender")
        XCTAssertEqual(FilenameSanitizer.slug("OneDrive (Files) & Sync"), "onedrive-files-sync")
        XCTAssertEqual(FilenameSanitizer.slug("Ünïcode Äpp"), "unicode-app")
        XCTAssertEqual(FilenameSanitizer.slug("!!!"), "")
    }

    func testUniqueName() {
        let existing: Set<String> = ["Edge.png", "Edge-2.png"]
        XCTAssertEqual(FilenameSanitizer.uniqueName(base: "Edge", fileExtension: "png", existing: existing), "Edge-3.png")
        XCTAssertEqual(FilenameSanitizer.uniqueName(base: "Teams", fileExtension: "png", existing: existing), "Teams.png")
    }
}
