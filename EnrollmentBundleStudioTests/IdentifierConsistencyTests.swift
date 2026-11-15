import UniformTypeIdentifiers
import XCTest
@testable import EnrollmentBundleStudio

/// Guards the identifiers that must never drift apart after the first release.
final class IdentifierConsistencyTests: XCTestCase {
    func testDocumentTypeIdentifier() {
        XCTAssertEqual(UTType.enrollmentProject.identifier, "com.example.enrollmentbundlestudio.project")
        XCTAssertTrue(UTType.enrollmentProject.conforms(to: .package))
    }

    func testInfoPlistDeclaresTheSameDocumentType() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let exported = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let identifiers = exported.compactMap { $0["UTTypeIdentifier"] as? String }
        XCTAssertTrue(identifiers.contains(UTType.enrollmentProject.identifier), "\(identifiers)")

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = documentTypes.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }
        XCTAssertTrue(contentTypes.contains(UTType.enrollmentProject.identifier), "\(contentTypes)")
    }

    func testConfigurationTypeIdentifier() throws {
        XCTAssertEqual(UTType.enrollmentConfiguration.identifier, "com.example.enrollmentbundlestudio.configuration")
        XCTAssertEqual(UTType.enrollmentConfiguration.identifier, ConfigurationArchive.formatIdentifier)
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let exported = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertTrue(exported.contains { $0["UTTypeIdentifier"] as? String == UTType.enrollmentConfiguration.identifier })
    }

    func testHostApplicationBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.example.enrollmentbundlestudio")
    }
}
