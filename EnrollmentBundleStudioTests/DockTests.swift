import XCTest
@testable import EnrollmentBundleStudio

final class DockTests: XCTestCase {
    private func project() -> EnrollmentProject {
        var project = TestSupport.makeProject()
        project.settings.organizationName = "Contoso"
        project.settings.packageIdentifier = "com.contoso.enrollment.bundle"
        project.settings.bundleIdentifier = "com.contoso.enrollment"
        project.settings.outputDirectoryPath = "/tmp"
        return project
    }

    private func enabledDock(_ items: [DockItem] = []) -> DockConfiguration {
        var dock = DockConfiguration.standard
        dock.isEnabled = true
        dock.items = items
        return dock
    }

    private func manual(_ label: String, _ path: String) -> DockItem {
        DockItem(id: UUID(), source: .manual, label: label, path: path, applicationTaskIdentifier: nil)
    }

    func testApplicationPathValidation() {
        XCTAssertTrue(DockConfiguration.isValidApplicationPath("/Applications/Safari.app"))
        XCTAssertTrue(DockConfiguration.isValidApplicationPath("/System/Applications/Utilities/Terminal.app"))
        XCTAssertFalse(DockConfiguration.isValidApplicationPath(""))
        XCTAssertFalse(DockConfiguration.isValidApplicationPath("Safari.app"))
        XCTAssertFalse(DockConfiguration.isValidApplicationPath("/Applications/Safari"))
        XCTAssertFalse(DockConfiguration.isValidApplicationPath("/Applications/../etc/Evil.app"))
        XCTAssertFalse(DockConfiguration.isValidApplicationPath("/Applications/Bad\nName.app"))
        XCTAssertFalse(DockConfiguration.isValidApplicationPath("/.app"))
    }

    func testResolvedItemsDropInvalidAndRepeatedPathsAndFillLabels() {
        var dock = enabledDock([
            manual("Safari", "/Applications/Safari.app"),
            manual("Again", "/Applications/Safari.app"),
            manual("", "/Applications/Slack.app"),
            manual("Bad", "relative.app")
        ])
        dock.items.append(manual("  Zoom  ", " /Applications/zoom.us.app "))
        let items = dock.resolvedItems(in: project())
        XCTAssertEqual(items.map { $0.path }, ["/Applications/Safari.app", "/Applications/Slack.app", "/Applications/zoom.us.app"])
        XCTAssertEqual(items.map { $0.label }, ["Safari", "Slack", "Zoom"])
    }

    func testProjectApplicationsFollowLaterEdits() throws {
        var project = project()
        let application = try XCTUnwrap(project.allApplications.first)
        var dock = enabledDock()
        XCTAssertTrue(dock.addProjectApplication(application))
        XCTAssertFalse(dock.addProjectApplication(application), "An application is listed once")
        project.dock = dock
        XCTAssertEqual(dock.resolvedItems(in: project).first?.path, application.applicationPath)

        project.applicationGroups[0].applications[0].applicationPath = "/Applications/Renamed.app"
        project.applicationGroups[0].applications[0].displayName = "Renamed"
        let item = try XCTUnwrap(dock.resolvedItems(in: project).first)
        XCTAssertEqual(item.path, "/Applications/Renamed.app")
        XCTAssertEqual(item.label, "Renamed")
    }

    func testAddApplicationRejectsInvalidAndRepeatedPaths() {
        var dock = enabledDock()
        XCTAssertTrue(dock.addApplication(label: "Safari", path: "/Applications/Safari.app", source: .system))
        XCTAssertFalse(dock.addApplication(label: "Safari", path: "/Applications/Safari.app", source: .manual))
        XCTAssertFalse(dock.addApplication(label: "X", path: "/tmp/x", source: .manual))
        XCTAssertEqual(dock.items.count, 1)
    }

    func testFingerprintChangesOnlyWhenWhatTheDeviceReceivesChanges() {
        let project = project()
        var dock = enabledDock([manual("Safari", "/Applications/Safari.app")])
        let base = dock.fingerprint(in: project)
        XCTAssertEqual(base.count, 64)
        XCTAssertEqual(dock.fingerprint(in: project), base)

        var changed = dock
        changed.position = .left
        XCTAssertNotEqual(changed.fingerprint(in: project), base)
        changed = dock
        changed.tileSize = 70
        XCTAssertNotEqual(changed.fingerprint(in: project), base)
        changed = dock
        changed.autoHide = true
        XCTAssertNotEqual(changed.fingerprint(in: project), base)
        changed = dock
        changed.removeDefaultItems = false
        XCTAssertNotEqual(changed.fingerprint(in: project), base)
        changed = dock
        changed.items.append(manual("Slack", "/Applications/Slack.app"))
        XCTAssertNotEqual(changed.fingerprint(in: project), base)

        // Internal item identifiers are not part of what the device receives.
        dock.items[0].id = UUID()
        XCTAssertEqual(dock.fingerprint(in: project), base)
    }

    func testOlderProjectsWithoutADockStillDecodeAndKeepNoDockKey() throws {
        let object = try TestSupport.projectJSONObject(TestSupport.makeProject())
        XCTAssertNil(object["dock"], "A project that never configured a Dock writes no dock object")
        let loaded = try ProjectCoding.load(try TestSupport.data(fromJSONObject: object)).project
        XCTAssertNil(loaded.dock)
    }

    func testDockRoundTripsThroughProjectJSON() throws {
        var project = project()
        project.dock = enabledDock([manual("Safari", "/Applications/Safari.app")])
        project.dock?.position = .right
        project.dock?.autoHide = true
        let data = try ProjectCoding.encode(project)
        let loaded = try ProjectCoding.load(data).project
        XCTAssertEqual(loaded.dock, project.dock)
    }

    func testSidebarPlacesDockDirectlyAfterExecution() throws {
        let all = SidebarSection.allCases
        let execution = try XCTUnwrap(all.firstIndex(of: .execution))
        XCTAssertEqual(all[execution + 1], .dock)
        XCTAssertTrue(SidebarSection.dock.isAvailable)
        XCTAssertEqual(ValidationArea.dock.sidebarSection, .dock)
    }

    // MARK: Generated configuration

    private func conf(_ project: EnrollmentProject) -> String {
        FrameworkGenerator.configurationFile(project: project, installDirectory: "/Library/Application Support/Contoso/Enrollment", now: Date(timeIntervalSince1970: 0))
    }

    func testConfigurationHasNoDockValuesUnlessEnabled() {
        var project = project()
        XCTAssertFalse(conf(project).contains("dock_"))
        project.dock = DockConfiguration.standard
        project.dock?.items = [manual("Safari", "/Applications/Safari.app")]
        XCTAssertFalse(conf(project).contains("dock_"), "A disabled Dock writes nothing")
    }

    func testConfigurationQuotesDockValuesSafely() {
        var project = project()
        var dock = enabledDock([
            manual("Bob's \"Editor\" $HOME", "/Applications/Bob's Editor.app"),
            manual("Safari", "/Applications/Safari.app")
        ])
        dock.position = .left
        dock.tileSize = 999
        dock.autoHide = true
        dock.removeDefaultItems = false
        project.dock = dock
        let text = conf(project)
        XCTAssertTrue(text.contains("dock_enabled=1"))
        XCTAssertTrue(text.contains("dock_remove_default=0"))
        XCTAssertTrue(text.contains("dock_position='left'"))
        XCTAssertTrue(text.contains("dock_tile_size=128"), "The size is clamped")
        XCTAssertTrue(text.contains("dock_autohide=1"))
        XCTAssertTrue(text.contains("dock_item_count=2"))
        XCTAssertTrue(text.contains("dock_fingerprint='\(dock.fingerprint(in: project))'"))
        XCTAssertTrue(text.contains("dock_item_2_path='/Applications/Safari.app'"))
        // Single quotes inside a value are closed, escaped and reopened; nothing is left to expand.
        XCTAssertTrue(text.contains("dock_item_1_label='Bob'\\''s \"Editor\" $HOME'"))
    }

    func testFrameworkRunsTheDockOnlyAfterSuccess() throws {
        let document = try TestSupport.makeProjectWithScript()
        let framework = try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)
        let user = try XCTUnwrap(framework.files.first { $0.path == "framework/lib/user.sh" })
        let enrollment = try XCTUnwrap(framework.files.first { $0.path == "framework/enrollment.sh" })
        XCTAssertTrue(String(decoding: user.contents, as: UTF8.self).contains("apply_dock()"))
        let script = String(decoding: enrollment.contents, as: UTF8.self)
        XCTAssertTrue(script.contains("success|warnings) apply_dock || true ;;"))
    }

    // MARK: Validation

    func testValidationOnlyChecksAnEnabledDock() {
        var project = project()
        project.dock = DockConfiguration.standard
        project.dock?.items = [manual("Bad", "not-a-path")]
        let report = ValidationEngine.validate(project: project, assets: [:], environment: .permissive)
        XCTAssertFalse(report.issues.contains { $0.area == .dock })
    }

    func testValidationReportsBadPathsDuplicatesAndEmptyDocks() {
        var project = project()
        project.dock = enabledDock([
            manual("Bad", "not-a-path"),
            manual("Safari", "/Applications/Safari.app"),
            manual("Safari 2", "/Applications/Safari.app")
        ])
        var report = ValidationEngine.validate(project: project, assets: [:], environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.area == .dock && $0.severity == .error && $0.component == "Dock: Bad" })
        XCTAssertTrue(report.issues.contains { $0.area == .dock && $0.severity == .warning && $0.component == "Dock: Safari 2" })

        project.dock = enabledDock()
        report = ValidationEngine.validate(project: project, assets: [:], environment: .permissive)
        let empty = report.issues.first { $0.area == .dock }
        XCTAssertEqual(empty?.severity, .warning)
        XCTAssertFalse(report.issues.contains { $0.area == .dock && $0.severity == .error })
    }

    func testValidationWarnsWhenALinkedApplicationWasRemoved() {
        var project = project()
        project.dock = enabledDock([
            DockItem(id: UUID(), source: .project, label: "Gone", path: "/Applications/Gone.app", applicationTaskIdentifier: "app.gone")
        ])
        let report = ValidationEngine.validate(project: project, assets: [:], environment: .permissive)
        XCTAssertTrue(report.issues.contains { $0.area == .dock && $0.severity == .warning && $0.component == "Dock: Gone" })
    }
}
