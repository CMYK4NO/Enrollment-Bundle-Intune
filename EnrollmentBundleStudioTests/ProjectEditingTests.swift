import XCTest
@testable import EnrollmentBundleStudio

final class ProjectEditingTests: XCTestCase {
    func testDefaultProjectContents() {
        let project = TestSupport.makeProject()
        XCTAssertEqual(project.schemaVersion, AppInfo.currentSchemaVersion)
        XCTAssertEqual(project.applicationGroups.count, 1)
        XCTAssertEqual(project.applicationGroups.first?.applications.first?.catalogID, "company-portal")
        XCTAssertEqual(project.applicationGroups.first?.applications.first?.taskIdentifier, "app.microsoft-company-portal")
        XCTAssertEqual(project.systemTasks.first?.type, .finalValidation)
        XCTAssertEqual(project.systemTasks.first?.execution.isVisible, false)
    }

    func testUniqueTaskIdentifiers() throws {
        var project = TestSupport.makeProject()
        let first = project.uniqueTaskIdentifier(for: "Microsoft Company Portal", prefix: "app")
        XCTAssertEqual(first, "app.microsoft-company-portal-2")
        XCTAssertEqual(project.uniqueTaskIdentifier(for: "!!!", prefix: "app"), "app.item")

        var duplicate = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
        duplicate.taskIdentifier = first
        let groupID = try XCTUnwrap(project.applicationGroups.first?.id)
        project.addApplication(duplicate, toGroup: groupID)
        XCTAssertEqual(project.uniqueTaskIdentifier(for: "Microsoft Company Portal", prefix: "app"), "app.microsoft-company-portal-3")
    }

    func testAddCatalogEntriesIntoCategoryGroups() throws {
        var project = TestSupport.makeProject()
        let entries = ["microsoft-edge", "google-chrome", "microsoft-365", "company-portal"].compactMap(ApplicationCatalog.entry(id:))
        let added = project.addCatalogEntries(entries, target: .categoryGroups)
        XCTAssertEqual(added, 3, "Company Portal is already present and must be skipped")
        let browsers = try XCTUnwrap(project.applicationGroups.first { $0.name == "Browsers" })
        XCTAssertEqual(browsers.applications.map { $0.catalogID }, ["microsoft-edge", "google-chrome"])
        XCTAssertNotNil(project.applicationGroups.first { $0.name == "Microsoft 365" })
        XCTAssertEqual(Set(project.allTaskIdentifiers).count, project.allApplications.count + project.systemTasks.count)
    }

    func testAddCatalogEntriesIntoSpecificGroup() throws {
        var project = TestSupport.makeProject()
        let groupID = project.addGroup(named: "Everything")
        let entries = ApplicationCatalog.entries.filter { $0.category == "Browsers" }
        XCTAssertEqual(project.addCatalogEntries(entries, target: .group(groupID)), entries.count)
        XCTAssertEqual(project.group(id: groupID)?.applications.count, entries.count)
        XCTAssertEqual(project.addCatalogEntries(entries, target: .group(UUID())), 0)
    }

    func testGroupNamesAreUnique() {
        var project = TestSupport.makeProject()
        let a = project.addGroup(named: "Tools")
        let b = project.addGroup(named: "Tools")
        let c = project.addGroup(named: "   ")
        XCTAssertEqual(project.group(id: a)?.name, "Tools")
        XCTAssertEqual(project.group(id: b)?.name, "Tools 2")
        XCTAssertEqual(project.group(id: c)?.name, "New Group")
    }

    func testRenameIgnoresEmptyNames() throws {
        var project = TestSupport.makeProject()
        let id = try XCTUnwrap(project.applicationGroups.first?.id)
        project.renameGroup(id: id, to: "  Core  ")
        XCTAssertEqual(project.group(id: id)?.name, "Core")
        project.renameGroup(id: id, to: "   ")
        XCTAssertEqual(project.group(id: id)?.name, "Core")
    }

    func testMoveGroup() {
        var project = TestSupport.makeProject()
        let first = project.applicationGroups[0].id
        let second = project.addGroup(named: "Second")
        project.moveGroup(id: second, by: -1)
        XCTAssertEqual(project.applicationGroups.map { $0.id }, [second, first])
        project.moveGroup(id: second, by: -1)
        XCTAssertEqual(project.applicationGroups.map { $0.id }, [second, first], "Moving past the top is ignored")
    }

    func testMoveApplicationBetweenGroups() throws {
        var project = TestSupport.makeProject()
        let source = try XCTUnwrap(project.applicationGroups.first)
        let application = try XCTUnwrap(source.applications.first)
        let destination = project.addGroup(named: "Other")
        project.moveApplication(id: application.id, toGroup: destination)
        XCTAssertTrue(project.group(id: source.id)?.applications.isEmpty ?? false)
        XCTAssertEqual(project.group(id: destination)?.applications.first?.id, application.id)
    }

    func testReorderApplicationsWithinGroup() throws {
        var project = TestSupport.makeProject()
        let groupID = project.addGroup(named: "Browsers")
        let entries = ["microsoft-edge", "google-chrome", "mozilla-firefox"].compactMap(ApplicationCatalog.entry(id:))
        project.addCatalogEntries(entries, target: .group(groupID))
        project.moveApplications(inGroup: groupID, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(project.group(id: groupID)?.applications.map { $0.catalogID }, ["mozilla-firefox", "microsoft-edge", "google-chrome"])
    }

    func testRemoveApplicationAndGroup() throws {
        var project = TestSupport.makeProject()
        let group = try XCTUnwrap(project.applicationGroups.first)
        let application = try XCTUnwrap(group.applications.first)
        XCTAssertEqual(project.removeApplication(id: application.id)?.id, application.id)
        XCTAssertNil(project.removeApplication(id: application.id))
        XCTAssertEqual(project.removeGroup(id: group.id)?.id, group.id)
        XCTAssertTrue(project.applicationGroups.isEmpty)
    }

    func testReferencedAssetPaths() {
        var project = TestSupport.makeProject()
        project.branding.logoPath = "Branding/CompanyLogo.png"
        project.applicationGroups[0].applications[0].icon = IconSource(kind: .projectAsset, value: "Icons/Portal.png")
        XCTAssertEqual(project.referencedAssetPaths, ["Branding/CompanyLogo.png", "Icons/Portal.png"])
    }
}

final class ArrayMoveTests: XCTestCase {
    func testMatchesOnMoveSemantics() {
        var values = ["a", "b", "c", "d"]
        values.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(values, ["b", "c", "d", "a"])

        values = ["a", "b", "c", "d"]
        values.moveElements(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(values, ["d", "a", "b", "c"])

        values = ["a", "b", "c", "d"]
        values.moveElements(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(values, ["b", "d", "a", "c"])

        values = ["a", "b", "c", "d"]
        values.moveElements(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        XCTAssertEqual(values, ["a", "b", "c", "d"])
    }

    func testIgnoresOutOfRangeOffsets() {
        var values = [1, 2, 3]
        values.moveElements(fromOffsets: IndexSet(integer: 9), toOffset: 0)
        XCTAssertEqual(values, [1, 2, 3])
    }
}

final class LinkedScriptTests: XCTestCase {
    func testCustomScriptAppWaitsForItsLinkedScript() {
        var project = TestSupport.makeProject()
        var app = ApplicationItem.makeCustom(strategy: .customScript, timeoutSeconds: 900)
        app.taskIdentifier = "app.linked"
        app.displayName = "Linked"
        app.customScriptTaskIdentifier = "script.setup"
        project.applicationGroups[0].applications.append(app)
        let planned = TaskPlanner.plan(project).first { $0.taskIdentifier == "app.linked" }
        XCTAssertEqual(planned?.implicitDependencies, ["script.setup"])
    }

    func testOtherStrategiesIgnoreALeftoverLink() {
        var app = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
        app.taskIdentifier = "app.other"
        app.customScriptTaskIdentifier = "script.setup"
        var project = TestSupport.makeProject()
        project.applicationGroups[0].applications.append(app)
        let planned = TaskPlanner.plan(project).first { $0.taskIdentifier == "app.other" }
        XCTAssertEqual(planned?.implicitDependencies, [])
    }
}
