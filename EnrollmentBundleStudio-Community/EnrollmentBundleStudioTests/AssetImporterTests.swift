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

final class WallpaperTests: XCTestCase {
    private func documentWithWallpaper() throws -> EnrollmentProjectDocument {
        var document = try TestSupport.makeProjectWithScript()
        document.project.settings.organizationName = "Contoso Ltd"
        try document.replaceBrandingImage(.wallpaper, data: try TestSupport.makePNG(), path: "Branding/Wallpaper.png")
        return document
    }

    private func text(_ framework: GeneratedFramework, _ path: String) -> String? {
        framework.files.first { $0.path == path }.map { String(decoding: $0.contents, as: UTF8.self) }
    }

    func testWallpaperAcceptsPNGAndJPEGOnly() throws {
        XCTAssertEqual(try AssetImporter.validateWallpaper(try TestSupport.makePNG()), .png)
        var icns = Data([0x69, 0x63, 0x6E, 0x73])
        icns.append(Data(repeating: 0, count: 32))
        XCTAssertThrowsError(try AssetImporter.validateWallpaper(icns))
        XCTAssertThrowsError(try AssetImporter.validateWallpaper(Data()))
    }

    func testWallpaperPathAndRemoval() throws {
        var document = try documentWithWallpaper()
        XCTAssertEqual(AssetImporter.brandingPath(role: .wallpaper, format: .jpeg), "Branding/Wallpaper.jpg")
        XCTAssertEqual(document.project.branding.wallpaperPath, "Branding/Wallpaper.png")
        XCTAssertNotNil(document.assets["Branding/Wallpaper.png"])
        document.removeBrandingImage(.wallpaper)
        XCTAssertNil(document.project.branding.wallpaperPath)
        XCTAssertNil(document.assets["Branding/Wallpaper.png"], "An unreferenced wallpaper file is removed")
    }

    func testOlderProjectsWithoutAWallpaperStillDecode() throws {
        var object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        var branding = try XCTUnwrap(object["branding"] as? [String: Any])
        branding.removeValue(forKey: "wallpaperPath")
        object["branding"] = branding
        let project = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object)).project
        XCTAssertNil(project.branding.wallpaperPath)
    }

    func testGeneratorBundlesTheWallpaperAndConfiguresIt() throws {
        let document = try documentWithWallpaper()
        let framework = try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)
        let name = FrameworkGenerator.wallpaperFileName(project: document.project, assetPath: "Branding/Wallpaper.png")
        XCTAssertEqual(name, "Contoso-Ltd-Wallpaper.png")
        XCTAssertTrue(framework.files.contains { $0.path == "framework/wallpaper/\(name)" })
        let configuration = try XCTUnwrap(text(framework, "framework/config/enrollment.conf"))
        XCTAssertTrue(configuration.contains("wallpaper_source='wallpaper/\(name)'"), configuration)
        XCTAssertTrue(configuration.contains("wallpaper_target='/Library/Desktop Pictures/\(name)'"), configuration)
    }

    func testNoWallpaperMeansNoWallpaperFilesOrSettings() throws {
        let document = try TestSupport.makeProjectWithScript()
        let framework = try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)
        XCTAssertFalse(framework.files.contains { $0.path.hasPrefix("framework/wallpaper/") })
        let configuration = try XCTUnwrap(text(framework, "framework/config/enrollment.conf"))
        XCTAssertFalse(configuration.contains("wallpaper_"))
    }

    func testTheDeviceAppliesTheWallpaperOnlyOncePerImage() {
        let script = FrameworkTemplates.libraryUser
        XCTAssertTrue(script.contains("apply_wallpaper()"))
        XCTAssertTrue(script.contains("wallpaper.applied"), "The applied image's fingerprint is remembered")
        XCTAssertTrue(FrameworkTemplates.enrollmentScript.contains("apply_wallpaper || true"), "A wallpaper problem never fails enrollment")
    }

    func testMissingWallpaperFileIsAValidationError() throws {
        let document = try documentWithWallpaper()
        // The document's assets are read-only from outside; validate against a copy that lacks the file.
        var assets = document.assets
        assets.removeValue(forKey: "Branding/Wallpaper.png")
        let report = ValidationEngine.validate(project: document.project, assets: assets, environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.severity == .error && $0.component == "Desktop wallpaper" })
    }
}
