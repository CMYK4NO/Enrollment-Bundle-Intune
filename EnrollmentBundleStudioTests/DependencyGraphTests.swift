import XCTest
@testable import EnrollmentBundleStudio

final class DependencyGraphTests: XCTestCase {
    private typealias T = TestSupport

    func testOrdersByDependenciesThenExecutionOrder() {
        let tasks = [
            T.plannedTask("c", order: 10, dependencies: ["b"]),
            T.plannedTask("a", order: 30),
            T.plannedTask("b", order: 5)
        ]
        let analysis = DependencyGraph.analyze(tasks)
        XCTAssertEqual(analysis.orderedTaskIDs, ["b", "c", "a"])
        XCTAssertTrue(analysis.issues.isEmpty, "\(analysis.issues)")
    }

    func testDetectsCycleAndReportsItOnce() {
        let tasks = [
            T.plannedTask("a", dependencies: ["c"]),
            T.plannedTask("b", dependencies: ["a"]),
            T.plannedTask("c", dependencies: ["b"]),
            T.plannedTask("d", dependencies: ["a"])
        ]
        let analysis = DependencyGraph.analyze(tasks)
        let cycles = analysis.issues.compactMap { issue -> [String]? in
            if case .cycle(let ids) = issue { return ids }
            return nil
        }
        XCTAssertEqual(cycles, [["a", "c", "b"]])
        XCTAssertEqual(analysis.tasksInCycles, ["a", "b", "c"])
        XCTAssertTrue(analysis.blockedTaskIDs.contains("d"), "Depends on a cycle, so it can never start")
        XCTAssertEqual(Set(analysis.orderedTaskIDs), ["a", "b", "c", "d"], "Every task is still listed")
        XCTAssertTrue(analysis.hasCriticalIssues)
    }

    func testSelfDependency() {
        let analysis = DependencyGraph.analyze([T.plannedTask("a", dependencies: ["a"])])
        XCTAssertTrue(analysis.issues.contains(.selfDependency("a")))
        XCTAssertTrue(analysis.blockedTaskIDs.contains("a"))
    }

    func testMissingAndDisabledDependencies() {
        let tasks = [
            T.plannedTask("a", dependencies: ["ghost"]),
            T.plannedTask("b", dependencies: ["off"]),
            T.plannedTask("off", enabled: false),
            T.plannedTask("c", dependencies: ["b"])
        ]
        let analysis = DependencyGraph.analyze(tasks)
        XCTAssertTrue(analysis.issues.contains(.missingDependency(task: "a", dependency: "ghost")))
        XCTAssertTrue(analysis.issues.contains(.disabledDependency(task: "b", dependency: "off")))
        XCTAssertEqual(analysis.blockedTaskIDs, ["a", "b", "c"])
        XCTAssertFalse(analysis.orderedTaskIDs.contains("off"), "Disabled tasks are not scheduled")
    }

    func testDisabledTaskWithBrokenDependencyIsIgnored() {
        let analysis = DependencyGraph.analyze([T.plannedTask("a", dependencies: ["ghost"], enabled: false)])
        XCTAssertTrue(analysis.issues.isEmpty)
    }

    func testDuplicateAndEmptyIdentifiersDoNotCrash() {
        let tasks = [T.plannedTask("dup"), T.plannedTask("dup", order: 5), T.plannedTask("")]
        let analysis = DependencyGraph.analyze(tasks)
        XCTAssertTrue(analysis.issues.contains(.duplicateIdentifier("dup")))
        XCTAssertTrue(analysis.issues.contains(.emptyIdentifier(displayName: "")))
        XCTAssertEqual(analysis.orderedTaskIDs, ["dup"])
    }

    func testImpossibleExecutionOrder() {
        let tasks = [T.plannedTask("defender", order: 10, dependencies: ["portal"]), T.plannedTask("portal", order: 20)]
        let analysis = DependencyGraph.analyze(tasks)
        XCTAssertTrue(analysis.issues.contains(.orderConflict(task: "defender", dependency: "portal")))
        XCTAssertEqual(analysis.orderedTaskIDs, ["portal", "defender"], "Dependencies still win at run time")
    }

    func testParallelBatches() {
        let tasks = [
            T.plannedTask("word", order: 30, group: "m365"),
            T.plannedTask("excel", order: 30, group: "m365"),
            T.plannedTask("outlook", order: 30, dependencies: ["word"], group: "m365"),
            T.plannedTask("edge", order: 40)
        ]
        let analysis = DependencyGraph.analyze(tasks)
        XCTAssertEqual(analysis.batches, [["word", "excel"], ["outlook"], ["edge"]])
        XCTAssertTrue(analysis.issues.contains(.parallelGroupDependency(task: "outlook", dependency: "word", group: "m365")))
        XCTAssertFalse(analysis.hasCriticalIssues, "A shared parallel group is only a warning")
    }
}

final class TaskPlannerTests: XCTestCase {
    func testPlanIncludesEveryTaskSourceAndFinalValidationDependencies() throws {
        var document = try TestSupport.makeProjectWithScript()
        let entries = ["microsoft-edge"].compactMap(ApplicationCatalog.entry(id:))
        document.project.addCatalogEntries(entries, target: .categoryGroups)
        var script = try XCTUnwrap(document.project.scripts.first)
        script.execution.isRequired = true
        document.project.updateScript(script)

        let plan = TaskPlanner.plan(document.project)
        XCTAssertEqual(plan.map { $0.taskIdentifier }, ["app.microsoft-company-portal", "app.microsoft-edge", "script.checkexample", "system.final-validation"])
        let final = try XCTUnwrap(plan.last)
        XCTAssertEqual(final.type, .finalValidation)
        XCTAssertEqual(Set(final.implicitDependencies), ["app.microsoft-company-portal", "script.checkexample"], "Edge is optional")
        XCTAssertEqual(plan.first?.isRequired, true, "Required group makes the app required")
    }

    func testStrategyMapsToTaskType() {
        XCTAssertEqual(TaskPlanner.taskType(for: .waitForIntune), .applicationDetection)
        XCTAssertEqual(TaskPlanner.taskType(for: .detectionOnly), .applicationDetection)
        XCTAssertEqual(TaskPlanner.taskType(for: .bundledInstaller), .packageInstallation)
        XCTAssertEqual(TaskPlanner.taskType(for: .customScript), .shellScript)
    }

    func testDefaultProjectHasNoDependencyIssues() {
        let analysis = DependencyGraph.analyze(TaskPlanner.plan(TestSupport.makeProject()))
        XCTAssertTrue(analysis.issues.isEmpty, "\(analysis.issues)")
        XCTAssertEqual(analysis.orderedTaskIDs.last, "system.final-validation")
    }

    func testRequiredTaskDependingOnFinalValidationIsACycle() throws {
        var project = TestSupport.makeProject()
        var portal = try XCTUnwrap(project.allApplications.first)
        portal.execution.dependencies = ["system.final-validation"]
        project.updateApplication(portal)
        let analysis = DependencyGraph.analyze(TaskPlanner.plan(project))
        XCTAssertTrue(analysis.issues.contains { if case .cycle = $0 { return true } else { return false } })
    }

    func testSystemTaskEditing() throws {
        var project = TestSupport.makeProject()
        let id = project.addSystemTask(type: .waitCondition)
        let task = try XCTUnwrap(project.systemTask(id: id))
        XCTAssertEqual(task.taskIdentifier, "system.wait-condition")
        XCTAssertEqual(task.validation?.method, .customCommand)
        XCTAssertEqual(project.nextExecutionOrder, 520)

        var options = try XCTUnwrap(project.executionOptions(forTask: task.taskIdentifier))
        options.dependencies = ["app.microsoft-company-portal"]
        project.setExecutionOptions(options, forTask: task.taskIdentifier)
        XCTAssertEqual(project.dependents(of: "app.microsoft-company-portal"), ["system.wait-condition"])

        let portalID = try XCTUnwrap(project.allApplications.first?.id)
        project.removeApplication(id: portalID)
        XCTAssertEqual(project.systemTask(id: id)?.execution.dependencies, [], "Removing a task drops references to it")
        XCTAssertEqual(project.removeSystemTask(id: id)?.id, id)
    }
}
