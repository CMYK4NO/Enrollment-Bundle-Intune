import XCTest
@testable import EnrollmentBundleStudio

final class PreviewBuilderTests: XCTestCase {
    /// Company Portal (required group) plus Edge and Chrome (optional, in Browsers).
    private func makeProject() -> EnrollmentProject {
        var project = TestSupport.makeProject()
        let entries = ["microsoft-edge", "google-chrome"].compactMap(ApplicationCatalog.entry(id:))
        project.addCatalogEntries(entries, target: .categoryGroups)
        return project
    }

    func testScenarioStatuses() {
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.initial, requiredFlags: [true, false]), [.pending, .pending])
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.inProgress, requiredFlags: [true, true, true, true]), [.complete, .complete, .running, .waiting])
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.completeWithWarnings, requiredFlags: [true, false]), [.complete, .failed])
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.completeWithWarnings, requiredFlags: [true, true]), [.complete, .completeWithWarnings])
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.requiredFailure, requiredFlags: [false, true]), [.complete, .failed])
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.requiredTimeout, requiredFlags: [false, true]), [.complete, .timedOut])
        XCTAssertEqual(PreviewBuilder.scenarioStatuses(.allComplete, requiredFlags: []), [])
    }

    func testAllCompleteUnlocksAndSucceeds() {
        let state = PreviewBuilder.makeState(project: makeProject(), scenario: .allComplete, overrides: [:])
        XCTAssertTrue(state.isButtonEnabled)
        XCTAssertEqual(state.outcome, .success)
        XCTAssertEqual(state.finishedCount, state.totalCount)
        XCTAssertEqual(state.progress, 1)
    }

    func testHiddenFinalValidationCountsButIsNotDisplayed() {
        let state = PreviewBuilder.makeState(project: makeProject(), scenario: .allComplete, overrides: [:])
        XCTAssertEqual(state.hiddenCount, 1)
        XCTAssertFalse(state.displayItems.contains { $0.id == "system.final-validation" })
        XCTAssertTrue(state.evaluationItems.contains { $0.id == "system.final-validation" && $0.status == .complete })
    }

    func testOptionalFailureStillUnlocksWithWarnings() {
        let state = PreviewBuilder.makeState(project: makeProject(), scenario: .completeWithWarnings, overrides: [:])
        XCTAssertTrue(state.isButtonEnabled)
        XCTAssertEqual(state.outcome, .successWithWarnings)
    }

    func testRequiredFailureKeepsButtonLocked() {
        let state = PreviewBuilder.makeState(project: makeProject(), scenario: .requiredFailure, overrides: [:])
        XCTAssertFalse(state.isButtonEnabled)
        XCTAssertEqual(state.outcome, .failed)
        let finalValidation = state.evaluationItems.first { $0.id == "system.final-validation" }
        XCTAssertEqual(finalValidation?.status, .pending)
    }

    func testDisabledLockAlwaysEnablesButton() {
        var project = makeProject()
        project.settings.lockCompletionButtonUntilRequiredComplete = false
        let state = PreviewBuilder.makeState(project: project, scenario: .initial, overrides: [:])
        XCTAssertTrue(state.isButtonEnabled)
        XCTAssertFalse(state.isButtonLockActive)
    }

    func testOverridesApplyAndDriveFinalValidation() {
        let project = makeProject()
        let portalID = "app.microsoft-company-portal"
        let state = PreviewBuilder.makeState(project: project, scenario: .allComplete, overrides: [portalID: .running])
        XCTAssertEqual(state.evaluationItems.first { $0.id == portalID }?.status, .running)
        XCTAssertEqual(state.evaluationItems.first { $0.id == "system.final-validation" }?.status, .pending)
        XCTAssertFalse(state.isButtonEnabled)
    }

    func testSummaryGroupAggregatesMembers() throws {
        var project = makeProject()
        let index = try XCTUnwrap(project.applicationGroups.firstIndex { $0.name == "Browsers" })
        project.applicationGroups[index].displayBehavior = .singleSummaryItem
        let edgeID = "app.microsoft-edge"
        let state = PreviewBuilder.makeState(project: project, scenario: .allComplete, overrides: [edgeID: .failed])
        let summary = try XCTUnwrap(state.displayItems.first { $0.isSummary })
        XCTAssertEqual(summary.title, "Browsers")
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.memberIDs.count, 2)
        XCTAssertFalse(state.displayItems.contains { $0.id == edgeID })
    }

    func testHiddenGroupStillCountsTowardUnlock() throws {
        var project = makeProject()
        let index = try XCTUnwrap(project.applicationGroups.firstIndex { $0.name == "Device Management" })
        project.applicationGroups[index].displayBehavior = .hidden
        let state = PreviewBuilder.makeState(project: project, scenario: .requiredFailure, overrides: [:])
        XCTAssertFalse(state.displayItems.contains { $0.id == "app.microsoft-company-portal" })
        XCTAssertFalse(state.isButtonEnabled, "The hidden required item failed, so the button stays locked")
    }

    func testDisabledApplicationsAreExcluded() throws {
        var project = makeProject()
        let index = try XCTUnwrap(project.applicationGroups.firstIndex { $0.name == "Browsers" })
        project.applicationGroups[index].applications[0].isEnabled = false
        let state = PreviewBuilder.makeState(project: project, scenario: .allComplete, overrides: [:])
        XCTAssertFalse(state.evaluationItems.contains { $0.id == "app.microsoft-edge" })
    }

    func testStatusTextUsesTaskMessages() {
        XCTAssertEqual(PreviewBuilder.statusText(.waiting, messages: .standard), "Waiting for Intune")
        XCTAssertEqual(PreviewBuilder.statusText(.complete, messages: .standard), "Installed")
        XCTAssertEqual(PreviewBuilder.statusText(.timedOut, messages: .standard), "Timed out")
    }
}
