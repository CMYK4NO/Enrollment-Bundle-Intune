import XCTest
@testable import EnrollmentBundleStudio


final class PreviewExecutionOrderTests: XCTestCase {
    func testPreviewListFollowsExecutionOrder() throws {
        var project = TestSupport.makeProject()
        func titles() -> [String] {
            PreviewBuilder.makeState(project: project, scenario: .initial, overrides: [:]).displayItems.map { $0.title }
        }
        var first = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
        first.taskIdentifier = "app.first"; first.displayName = "First"; first.execution.executionOrder = 10
        var second = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
        second.taskIdentifier = "app.second"; second.displayName = "Second"; second.execution.executionOrder = 20
        project.applicationGroups = [ApplicationGroup(id: UUID(), name: "Apps", symbolName: "square.grid.2x2", isRequired: false,
                                                       displayBehavior: .individualItems, applications: [first, second])]
        project.scripts = []
        project.systemTasks = []
        XCTAssertEqual(titles(), ["First", "Second"])
        project.applicationGroups[0].applications[0].execution.executionOrder = 30
        XCTAssertEqual(titles(), ["Second", "First"])
    }
}
