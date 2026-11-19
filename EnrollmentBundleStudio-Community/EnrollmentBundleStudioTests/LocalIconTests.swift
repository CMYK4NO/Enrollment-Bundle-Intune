import AppKit
import XCTest
@testable import EnrollmentBundleStudio

final class LocalIconTests: XCTestCase {
    private func pngData() throws -> Data {
        try TestSupport.makePNG()
    }

    private func documentWithApps() -> EnrollmentProjectDocument {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let entries = ["microsoft-edge", "google-chrome"].compactMap(ApplicationCatalog.entry(id:))
        document.addCatalogEntries(entries, target: .categoryGroups, iconData: { _ in nil })
        return document
    }

    private func application(_ catalogID: String, in document: EnrollmentProjectDocument) throws -> ApplicationItem {
        try XCTUnwrap(document.project.allApplications.first { $0.catalogID == catalogID })
    }

    func testEmbedsIconsThatCanBeRead() throws {
        var document = documentWithApps()
        let total = document.project.allApplications.filter { $0.icon.kind == .applicationBundle }.count
        let data = try pngData()
        let edgePath = try XCTUnwrap(document.project.allApplications.first { $0.catalogID == "microsoft-edge" }?.applicationPath)
        let result = document.embedLocalApplicationIcons(iconData: { $0 == edgePath ? data : nil })
        XCTAssertEqual(result.embedded.count, 1)
        XCTAssertEqual(result.notFound.count, total - 1)
        let edge = try application("microsoft-edge", in: document)
        XCTAssertEqual(edge.icon.kind, .projectAsset)
        XCTAssertTrue(edge.icon.value.hasPrefix("Icons/"))
        XCTAssertEqual(document.assets[edge.icon.value], data)
        let chrome = try application("google-chrome", in: document)
        XCTAssertEqual(chrome.icon.kind, .applicationBundle, "An app whose icon cannot be read stays unchanged")
    }

    func testSecondRunHasNothingLeftToEmbed() throws {
        var document = documentWithApps()
        let data = try pngData()
        _ = document.embedLocalApplicationIcons(iconData: { _ in data })
        let again = document.embedLocalApplicationIcons(iconData: { _ in data })
        XCTAssertEqual(again, LocalIconEmbedResult())
    }

    func testRejectsDataThatIsNotAnImage() {
        var document = documentWithApps()
        let total = document.project.allApplications.filter { $0.icon.kind == .applicationBundle }.count
        let result = document.embedLocalApplicationIcons(iconData: { _ in Data("not an image".utf8) })
        XCTAssertTrue(result.embedded.isEmpty)
        XCTAssertEqual(result.notFound.count, total)
        XCTAssertTrue(document.assets.keys.filter { $0.hasPrefix("Icons/") }.isEmpty)
    }

    func testCatalogueAddUsesTheLocalIconWhenNothingShips() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let data = try pngData()
        let entries = ["microsoft-edge"].compactMap(ApplicationCatalog.entry(id:))
        document.addCatalogEntries(entries, target: .categoryGroups, iconData: { _ in nil }, applicationIconData: { _ in data })
        let edge = try application("microsoft-edge", in: document)
        XCTAssertEqual(edge.icon.kind, .projectAsset)
        XCTAssertEqual(document.assets[edge.icon.value], data)
    }

    func testCatalogueAddPrefersTheShippedIcon() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let shipped = try pngData()
        let local = Data(shipped + [0])
        let entries = ["microsoft-edge"].compactMap(ApplicationCatalog.entry(id:))
        document.addCatalogEntries(entries, target: .categoryGroups, iconData: { _ in shipped }, applicationIconData: { _ in local })
        let edge = try application("microsoft-edge", in: document)
        XCTAssertEqual(document.assets[edge.icon.value], shipped)
    }

    func testCatalogueAddWithoutLocalReaderLeavesTheDefaultIcon() throws {
        var document = EnrollmentProjectDocument(project: TestSupport.makeProject())
        let entries = ["microsoft-edge"].compactMap(ApplicationCatalog.entry(id:))
        document.addCatalogEntries(entries, target: .categoryGroups, iconData: { _ in nil })
        XCTAssertEqual(try application("microsoft-edge", in: document).icon.kind, .applicationBundle)
    }

    func testExtractorRefusesPathsThatAreNotInstalledApps() {
        XCTAssertNil(AppIconExtractor.applicationIconPNG(atPath: ""))
        XCTAssertNil(AppIconExtractor.applicationIconPNG(atPath: "relative/Thing.app"))
        XCTAssertNil(AppIconExtractor.applicationIconPNG(atPath: "/Applications/Definitely Not Installed 4711.app"))
        XCTAssertNil(AppIconExtractor.applicationIconPNG(atPath: "/etc/hosts"))
    }

    func testRenderedIconIsAValidSquarePNG() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let data = try XCTUnwrap(AppIconExtractor.renderPNG(image, pixelSize: 64))
        XCTAssertEqual(AssetImporter.detectFormat(data), .png)
        XCTAssertNoThrow(try AssetImporter.validateImage(data))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(decoded.pixelsWide, 64)
        XCTAssertEqual(decoded.pixelsHigh, 64)
        XCTAssertNil(AppIconExtractor.renderPNG(image, pixelSize: 0))
    }

    func testWallpaperStepSendsNoAppleEvents() throws {
        let framework = try FrameworkGenerator.generate(project: TestSupport.makeProject(), assets: [:], installerSources: [:])
        let library = try XCTUnwrap(framework.allPaths.first { $0.hasSuffix("lib/user.sh") })
        let text = try XCTUnwrap(framework.text(at: library))
        XCTAssertTrue(text.contains("apply_wallpaper()"))
        XCTAssertTrue(text.contains("setDesktopImageURLForScreenOptionsError"))
        XCTAssertFalse(text.contains("tell application"), "No Apple events are sent")
    }
}
