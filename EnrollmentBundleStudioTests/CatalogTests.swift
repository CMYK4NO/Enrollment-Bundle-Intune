import XCTest
@testable import EnrollmentBundleStudio

final class CatalogTests: XCTestCase {
    func testContainsRequiredTemplates() {
        let names = Set(ApplicationCatalog.entries.map { $0.displayName })
        let required = [
            "Microsoft Company Portal", "Microsoft Defender", "Microsoft Edge",
            "Microsoft 365 and Office", "GlobalProtect", "Visual Studio Code",
            "Google Chrome", "Firefox", "Slack", "Zoom.us", "App Catalog", "BeyondTrust"
        ]
        for name in required {
            XCTAssertTrue(names.contains(name), "Missing \(name)")
        }
    }

    func testIndividualOfficeAppsAreNotListed() {
        let ids = Set(ApplicationCatalog.entries.map { $0.id })
        for removed in ["microsoft-word", "microsoft-excel", "microsoft-powerpoint", "microsoft-outlook",
                        "microsoft-onenote", "microsoft-teams", "microsoft-onedrive"] {
            XCTAssertFalse(ids.contains(removed), removed)
        }
    }

    func testEntriesAreWellFormed() {
        var ids = Set<String>()
        for entry in ApplicationCatalog.entries {
            XCTAssertTrue(ids.insert(entry.id).inserted, "Duplicate id \(entry.id)")
            XCTAssertTrue(FieldValidator.isValidReverseDNS(entry.bundleIdentifier), entry.bundleIdentifier)
            XCTAssertTrue(entry.applicationPath.hasPrefix("/"), entry.applicationPath)
            XCTAssertTrue(entry.applicationPath.hasSuffix(".app"), entry.applicationPath)
            XCTAssertTrue(ProjectSettings.taskTimeoutRange.contains(entry.defaultTimeoutSeconds))
            XCTAssertFalse(entry.suggestedValidation.requiresValue, "Catalogue entries must not need extra input")
        }
    }

    func testCategoriesAreOrderedAndUnique() {
        let categories = ApplicationCatalog.categories
        XCTAssertEqual(categories.count, Set(categories).count)
        XCTAssertEqual(categories.first, "Device Management")
    }

    func testMakeApplicationItem() throws {
        let entry = try XCTUnwrap(ApplicationCatalog.entry(id: "microsoft-defender"))
        let item = entry.makeApplicationItem(taskIdentifier: "app.microsoft-defender", strategy: .waitForIntune)
        XCTAssertEqual(item.catalogID, "microsoft-defender")
        XCTAssertEqual(item.detection.method, .bundleIdentifier)
        XCTAssertTrue(item.execution.isRequired)
        XCTAssertEqual(item.execution.timeoutSeconds, 1800)
        XCTAssertEqual(item.icon.kind, .applicationBundle)
    }
}
