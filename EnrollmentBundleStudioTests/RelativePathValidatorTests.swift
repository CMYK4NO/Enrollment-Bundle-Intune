import XCTest
@testable import EnrollmentBundleStudio

final class RelativePathValidatorTests: XCTestCase {
    private let roots = ProjectLayout.managedAssetDirectories

    func testSafePaths() {
        XCTAssertTrue(RelativePathValidator.isSafe("Icons/Edge.png", allowedRoots: roots))
        XCTAssertTrue(RelativePathValidator.isSafe("Scripts/CheckDefender.sh", allowedRoots: roots))
        XCTAssertTrue(RelativePathValidator.isSafe("Branding/Company Logo.png", allowedRoots: roots))
    }

    func testTraversalIsRejected() {
        for path in ["../../somewhere", "Icons/../../x.png", "Icons/../Scripts/x.sh", "Icons/./x.png", ".."] {
            XCTAssertFalse(RelativePathValidator.isSafe(path, allowedRoots: roots), path)
        }
    }

    func testAbsoluteAndHomePathsAreRejected() {
        for path in ["/etc/passwd", "~/Desktop/x.png", "~root/x"] {
            XCTAssertFalse(RelativePathValidator.isSafe(path, allowedRoots: roots), path)
        }
    }

    func testMalformedPathsAreRejected() {
        for path in ["", "Icons", "Icons/", "Icons//x.png", "Icons\\x.png", "Icons/x\u{0}.png", "Icons/x\n.png", "Builds/x.pkg", "icons/x.png"] {
            XCTAssertFalse(RelativePathValidator.isSafe(path, allowedRoots: roots), path.debugDescription)
        }
    }

    func testResolveStaysInsideRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/Example.enrollmentproject", isDirectory: true)
        let resolved = try XCTUnwrap(RelativePathValidator.resolve("Icons/Edge.png", in: root, allowedRoots: roots))
        XCTAssertEqual(resolved.path, "/tmp/Example.enrollmentproject/Icons/Edge.png")
        XCTAssertNil(RelativePathValidator.resolve("Icons/../../x", in: root, allowedRoots: roots))
    }
}
