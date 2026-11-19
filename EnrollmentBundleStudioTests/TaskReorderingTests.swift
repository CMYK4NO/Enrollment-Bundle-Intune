import XCTest
@testable import EnrollmentBundleStudio

final class TaskReorderingTests: XCTestCase {
    private let none: [String: Set<String>] = [:]

    func testPureMoveUpAndDownSwapNeighbours() {
        let sequence = ["a", "b", "c", "d"]
        XCTAssertEqual(TaskReordering.moved(sequence, "c", .up, dependencies: none), ["a", "c", "b", "d"])
        XCTAssertEqual(TaskReordering.moved(sequence, "b", .down, dependencies: none), ["a", "c", "b", "d"])
        XCTAssertNil(TaskReordering.moved(sequence, "a", .up, dependencies: none))
        XCTAssertNil(TaskReordering.moved(sequence, "d", .down, dependencies: none))
        XCTAssertNil(TaskReordering.moved(sequence, "missing", .up, dependencies: none))
    }

    func testMovingUpCarriesTheDependencyRightAboveIt() {
        let sequence = ["x", "a", "c", "y"]
        let dependencies = ["c": Set(["a"])]
        XCTAssertEqual(TaskReordering.moved(sequence, "c", .up, dependencies: dependencies), ["a", "c", "x", "y"])
    }

    func testMovingDownCarriesTheDependentRightBelowIt() {
        let sequence = ["x", "a", "c", "y"]
        let dependencies = ["c": Set(["a"])]
        XCTAssertEqual(TaskReordering.moved(sequence, "a", .down, dependencies: dependencies), ["x", "y", "a", "c"])
    }

    func testChainsMoveTogether() {
        // c needs b, b needs a: moving c up takes the whole chain over x.
        let dependencies = ["b": Set(["a"]), "c": Set(["b"])]
        XCTAssertEqual(TaskReordering.moved(["x", "a", "b", "c"], "c", .up, dependencies: dependencies), ["a", "b", "c", "x"])
        XCTAssertNil(TaskReordering.moved(["a", "b", "c"], "c", .up, dependencies: dependencies), "The chain is already first")
        XCTAssertNil(TaskReordering.moved(["a", "b", "c"], "a", .down, dependencies: dependencies), "The chain is already last")
    }

    func testResultIsAlwaysADependencyRespectingOrder() {
        let dependencies = ["d": Set(["b"]), "c": Set(["a"]), "e": Set(["c", "d"])]
        let start = ["a", "b", "c", "d", "e"]
        for id in start {
            for direction in [TaskMoveDirection.up, .down] {
                guard let result = TaskReordering.moved(start, id, direction, dependencies: dependencies) else { continue }
                XCTAssertEqual(Set(result), Set(start))
                XCTAssertEqual(result.count, start.count)
                for (task, needed) in dependencies {
                    let position = result.firstIndex(of: task) ?? -1
                    for dependency in needed {
                        XCTAssertLessThan(result.firstIndex(of: dependency) ?? Int.max, position, "\(dependency) before \(task)")
                    }
                }
            }
        }
    }

    // MARK: Project level

    private func project() -> EnrollmentProject {
        var project = TestSupport.makeProject()
        for name in ["a", "b", "c"] {
            var app = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
            app.taskIdentifier = "app.\(name)"
            app.displayName = name.uppercased()
            if name == "c" { app.execution.dependencies = ["app.a"] }
            project.applicationGroups[0].applications.append(app)
        }
        return project
    }

    private func order(_ project: EnrollmentProject) -> [String] {
        DependencyGraph.analyze(TaskPlanner.plan(project)).orderedTaskIDs
    }

    func testMoveTaskRewritesTheExecutionOrder() throws {
        var project = project()
        XCTAssertEqual(order(project), ["app.microsoft-company-portal", "app.a", "app.b", "app.c", "system.final-validation"])

        XCTAssertTrue(project.moveTask("app.c", .up))
        XCTAssertEqual(order(project), ["app.microsoft-company-portal", "app.a", "app.c", "app.b", "system.final-validation"])

        // c depends on a: moving c up again moves a with it, above the Company Portal.
        XCTAssertTrue(project.moveTask("app.c", .up))
        XCTAssertEqual(order(project), ["app.a", "app.c", "app.microsoft-company-portal", "app.b", "system.final-validation"])

        let plan = TaskPlanner.plan(project)
        let analysis = DependencyGraph.analyze(plan)
        XCTAssertFalse(analysis.hasCriticalIssues, "No order conflict: dependencies keep lower orders")
        let orders = analysis.orderedTaskIDs.compactMap { id in plan.first { $0.taskIdentifier == id }?.execution.executionOrder }
        XCTAssertEqual(orders, orders.sorted())
        XCTAssertEqual(Set(orders).count, orders.count, "Every task has its own order, so the shown order is unambiguous")
        XCTAssertEqual(try XCTUnwrap(project.executionOptions(forTask: "app.a")).executionOrder, 100)
    }

    func testFinalValidationStaysLast() {
        var project = project()
        XCTAssertTrue(project.moveTask("app.b", .down))
        XCTAssertEqual(order(project).last, "system.final-validation")
        XCTAssertGreaterThanOrEqual(project.executionOptions(forTask: "system.final-validation")?.executionOrder ?? 0, 900)
        XCTAssertFalse(project.moveTask("system.final-validation", .down))
    }

    func testMoveIsRefusedWhenTheOrderIsNotWellDefined() {
        var project = project()
        project.applicationGroups[0].applications[1].execution.dependencies = ["app.c"]
        project.applicationGroups[0].applications[3].execution.dependencies = ["app.a"]
        project.applicationGroups[0].applications[2].execution.dependencies = ["app.microsoft-company-portal"]
        // a (index 1) now depends on c, c depends on a: a cycle.
        let before = project
        XCTAssertFalse(project.moveTask("app.b", .up))
        XCTAssertEqual(project, before, "Nothing changes when a move is refused")
    }

    func testDisabledTasksCannotMove() {
        var project = project()
        project.applicationGroups[0].applications[2].isEnabled = false
        XCTAssertFalse(project.moveTask("app.b", .up))
        XCTAssertFalse(project.moveTask("app.b", .down))
    }

    func testDefaultProjectNameIsEnrollmentBundle() {
        XCTAssertEqual(EnrollmentProject.makeDefault().settings.projectName, "Enrollment Bundle")
    }
}
