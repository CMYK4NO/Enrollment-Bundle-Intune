import XCTest
@testable import EnrollmentBundleStudio

@MainActor
final class SplashLayoutTests: XCTestCase {
    func testSplashIs800By450() {
        XCTAssertEqual(SplashWindowController.size, NSSize(width: 800, height: 450))
        XCTAssertEqual(SplashWindowController.displayDuration, 2.5)
    }

    func testSplashIsCentredInTheUsableArea() {
        // A 1440x900 screen whose Dock takes 60 points at the bottom and whose menu bar takes 25 at the top.
        let visible = NSRect(x: 0, y: 60, width: 1440, height: 815)
        let frame = SplashWindowController.frame(centeredIn: visible)
        XCTAssertEqual(frame.size, SplashWindowController.size)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 1)
    }

    func testSplashIsCentredOnASecondaryOffsetScreen() {
        let visible = NSRect(x: 1440, y: -200, width: 1920, height: 1055)
        let frame = SplashWindowController.frame(centeredIn: visible)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 1)
    }

    func testSplashImageIsInTheBundle() {
        XCTAssertNotNil(NSImage(named: SplashWindowController.imageName))
    }
}
