import XCTest
@testable import EnrollmentBundleStudio

final class CatalogIconTests: XCTestCase {
    func testMicrosoft365EntryNamesItsBundledIcon() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        XCTAssertEqual(entry.bundledIconResource, "Microsoft365")
    }

    func testBundledMicrosoft365IconShipsInTheApp() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        let data = try XCTUnwrap(CatalogIconLoader.data(for: entry), "Microsoft365.png must be in the app bundle")
        XCTAssertEqual(try AssetImporter.validateImage(data), .png)
    }

    func testAddingMicrosoft365CopiesTheIconIntoTheProject() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-365"))
        let icns = Data([0x69, 0x63, 0x6E, 0x73, 0, 0, 0, 8])
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject(), assets: [:])
        // The stub is not a decodable image, so the document must keep the default icon.
        XCTAssertEqual(document.addCatalogEntries([entry], target: .categoryGroups, iconData: { _ in icns }), 1)
        let item = try XCTUnwrap(document.project.allApplications.first { $0.catalogID == "microsoft-365" })
        XCTAssertEqual(item.icon.kind, .applicationBundle)
        XCTAssertTrue(document.assets.keys.filter { $0.hasPrefix("Icons/") }.isEmpty)
    }

    func testAddingMicrosoft365WithTheRealIconSetsAProjectAsset() throws {
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
}
