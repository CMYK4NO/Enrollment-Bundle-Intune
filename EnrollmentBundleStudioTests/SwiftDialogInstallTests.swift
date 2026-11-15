import XCTest
@testable import EnrollmentBundleStudio

final class SwiftDialogInstallTests: XCTestCase {
    func testDialogLibraryInstallsSwiftDialogFromTheOfficialRelease() {
        let library = FrameworkTemplates.libraryDialog
        XCTAssertTrue(library.contains("dialog_ensure_installed()"))
        XCTAssertTrue(library.contains("https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest"))
        XCTAssertTrue(library.contains("https://github.com/swiftDialog/swiftDialog/releases/download/*"), "Download URL is restricted")
        XCTAssertTrue(library.contains("pkgutil --check-signature"), "Signature is verified before installing")
        XCTAssertTrue(library.contains("PWA5E9TQ59"))
        XCTAssertTrue(library.contains("installer -pkg"))
    }

    func testEnrollmentInstallsBeforeShowingTheDialogButNotInDryRunOrPreview() {
        let script = FrameworkTemplates.enrollmentScript
        let install = script.range(of: "dialog_ensure_installed || true")
        let prepare = script.range(of: "    if dialog_prepare; then")
        XCTAssertNotNil(install)
        XCTAssertNotNil(prepare)
        if let install, let prepare {
            XCTAssertTrue(install.lowerBound < prepare.lowerBound, "Installed before the dialog is prepared")
        }
        XCTAssertEqual(script.components(separatedBy: "dialog_ensure_installed").count - 1, 1, "Only the normal run installs")
        XCTAssertTrue(script.contains("a normal run installs it automatically"))
    }
}
