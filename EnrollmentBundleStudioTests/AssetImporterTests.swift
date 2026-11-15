import XCTest
@testable import EnrollmentBundleStudio

final class AssetImporterTests: XCTestCase {
    func testDetectsFormatsBySignature() {
        XCTAssertEqual(AssetImporter.detectFormat(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])), .png)
        XCTAssertEqual(AssetImporter.detectFormat(Data([0xFF, 0xD8, 0xFF, 0xE0])), .jpeg)
        XCTAssertEqual(AssetImporter.detectFormat(Data("icns".utf8) + Data([0, 0, 0, 8])), .icns)
        XCTAssertNil(AssetImporter.detectFormat(Data("GIF89a".utf8)))
        XCTAssertNil(AssetImporter.detectFormat(Data()))
    }

    func testValidGeneratedPNGPasses() throws {
        let png = try TestSupport.makePNG()
        XCTAssertEqual(try AssetImporter.validateImage(png), .png)
    }

    func testRejectsTextRenamedAsImage() {
        XCTAssertThrowsError(try AssetImporter.validateImage(Data("#!/bin/bash\necho hi\n".utf8))) { error in
            XCTAssertEqual(error as? AssetImportError, .unsupportedFormat)
        }
    }

    func testRejectsTruncatedPNG() {
        let header = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertThrowsError(try AssetImporter.validateImage(header)) { error in
            XCTAssertEqual(error as? AssetImportError, .undecodableImage)
        }
    }

    func testRejectsEmptyAndOversizedData() {
        XCTAssertThrowsError(try AssetImporter.validateImage(Data())) { error in
            XCTAssertEqual(error as? AssetImportError, .emptyFile)
        }
        XCTAssertThrowsError(try AssetImporter.validateImage(Data(count: 32), maximumBytes: 16)) { error in
            XCTAssertEqual(error as? AssetImportError, .tooLarge(32))
        }
    }

    func testReadFileRejectsDirectoriesAndLargeFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try AssetImporter.readFile(at: directory)) { error in
            XCTAssertEqual(error as? AssetImportError, .notARegularFile)
        }
        let file = directory.appendingPathComponent("big.png")
        try Data(count: 64).write(to: file)
        XCTAssertThrowsError(try AssetImporter.readFile(at: file, maximumBytes: 32)) { error in
            XCTAssertEqual(error as? AssetImportError, .tooLarge(64))
        }
        XCTAssertEqual(try AssetImporter.readFile(at: file, maximumBytes: 64).count, 64)
    }

    func testPathsAreDeterministicAndUnique() {
        XCTAssertEqual(AssetImporter.brandingPath(role: .logo, format: .png), "Branding/CompanyLogo.png")
        XCTAssertEqual(AssetImporter.brandingPath(role: .banner, format: .jpeg), "Branding/Banner.jpg")
        let existing: Set<String> = ["Icons/Microsoft-Edge.png", "Branding/Microsoft-Edge-2.png"]
        XCTAssertEqual(AssetImporter.iconPath(for: "Microsoft Edge", format: .png, existingPaths: existing), "Icons/Microsoft-Edge-2.png")
        XCTAssertEqual(AssetImporter.iconPath(for: "../../x", format: .icns, existingPaths: []), "Icons/x.icns")
    }
}
