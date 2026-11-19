import XCTest
@testable import EnrollmentBundleStudio

final class RuntimeSettingsDefaultsTests: XCTestCase {
    private func makeStore() throws -> (AppSettingsStore, UserDefaults, String) {
        let suite = "RuntimeSettingsDefaultsTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (AppSettingsStore(preferences: preferences), preferences, suite)
    }

    func testNothingSavedGivesBuiltInValues() throws {
        let (store, preferences, suite) = try makeStore()
        defer { preferences.removePersistentDomain(forName: suite) }
        XCTAssertEqual(store.load(), .builtIn())
        XCTAssertEqual(RuntimeSettingsDefaults.builtIn(), RuntimeSettingsDefaults(.makeDefault()))
    }

    func testSaveLoadAndReset() throws {
        let (store, preferences, suite) = try makeStore()
        defer { preferences.removePersistentDomain(forName: suite) }
        var values = RuntimeSettingsDefaults.builtIn()
        values.windowWidth = 1000
        values.debugLogging = true
        try store.save(values)
        XCTAssertEqual(store.load(), values)
        store.reset()
        XCTAssertEqual(store.load(), .builtIn())
    }

    func testInvalidSavedDataFallsBackToBuiltIn() throws {
        let (store, preferences, suite) = try makeStore()
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(Data("not json".utf8), forKey: AppSettingsStore.storageKey)
        XCTAssertEqual(store.load(), .builtIn())
        var invalid = RuntimeSettingsDefaults.builtIn()
        invalid.swiftDialogPath = "relative/dialog"
        XCTAssertFalse(invalid.isValid)
        preferences.set(try JSONEncoder().encode(invalid), forKey: AppSettingsStore.storageKey)
        XCTAssertEqual(store.load(), .builtIn())
    }

    func testApplyChangesOnlyRuntimeSettings() {
        var values = RuntimeSettingsDefaults.builtIn()
        values.windowWidth = 1100
        values.enrollmentWindowHours = 48
        var settings = ProjectSettings.makeDefault()
        settings.organizationName = "Contoso"
        values.apply(to: &settings)
        XCTAssertEqual(settings.windowWidth, 1100)
        XCTAssertEqual(settings.enrollmentWindowHours, 48)
        XCTAssertEqual(settings.organizationName, "Contoso")
    }

    func testNewDocumentStartsFromDefaults() {
        var values = RuntimeSettingsDefaults.builtIn()
        values.defaultTaskTimeoutSeconds = 1_200
        let document = EnrollmentProjectDocument(settingsDefaults: values)
        XCTAssertEqual(document.project.settings.defaultTaskTimeoutSeconds, 1_200)
    }

    func testAppliedSettingsAreIncludedInConfigurationExport() throws {
        var values = RuntimeSettingsDefaults.builtIn()
        values.windowHeight = 700
        var document = EnrollmentProjectDocument()
        values.apply(to: &document.project.settings)
        let data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        let result = try ConfigurationArchive.parse(data)
        XCTAssertEqual(result.project.settings.windowHeight, 700)
    }
}
