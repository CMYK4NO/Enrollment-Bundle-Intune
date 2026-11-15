import XCTest
@testable import EnrollmentBundleStudio

final class CatalogIconTests: XCTestCase {
    func testBundledMicrosoft365IconShipsInTheApp() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        let data = try XCTUnwrap(CatalogIconLoader.data(for: entry), "Microsoft365.png must be in the app bundle")
        XCTAssertEqual(try AssetImporter.validateImage(data), .png)
    }

    func testAddingAnEntryWithABundledIconCopiesItIntoTheProject() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        XCTAssertEqual(document.addCatalogEntries([entry], target: .categoryGroups), 1)
        let item = try XCTUnwrap(document.project.allApplications.first { $0.catalogID == "microsoft-365" })
        XCTAssertEqual(item.icon.kind, .projectAsset)
        XCTAssertTrue(item.icon.value.hasPrefix("Icons/"))
        XCTAssertTrue(item.icon.value.hasSuffix(".png"))
        XCTAssertNotNil(document.assets[item.icon.value])
        // Adding it again is a no-op and adds no second icon.
        XCTAssertEqual(document.addCatalogEntries([entry], target: .categoryGroups), 0)
        XCTAssertEqual(document.assets.keys.filter { $0.hasPrefix("Icons/") }.count, 1)
    }

    func testAnUndecodableIconKeepsTheDefaultIcon() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        let stub = Data([0x69, 0x63, 0x6E, 0x73, 0, 0, 0, 8])
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        XCTAssertEqual(document.addCatalogEntries([entry], target: .categoryGroups, iconData: { _ in stub }), 1)
        let item = try XCTUnwrap(document.project.allApplications.first { $0.catalogID == "microsoft-365" })
        XCTAssertEqual(item.icon.kind, .applicationBundle)
        XCTAssertTrue(document.assets.keys.filter { $0.hasPrefix("Icons/") }.isEmpty)
    }
}
