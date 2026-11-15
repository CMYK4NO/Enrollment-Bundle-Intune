import XCTest
@testable import EnrollmentBundleStudio

final class CompletionLogicTests: XCTestCase {
    private func task(_ status: TaskStatus, required: Bool = true, allowSkip: Bool = false) -> TaskStateInput {
        TaskStateInput(isRequired: required, allowSkip: allowSkip, status: status)
    }

    func testAcceptableStatesForRequiredTasks() {
        XCTAssertTrue(TaskStatus.complete.isAcceptableForRequiredTask(allowSkip: false))
        XCTAssertTrue(TaskStatus.completeWithWarnings.isAcceptableForRequiredTask(allowSkip: false))
        XCTAssertFalse(TaskStatus.skipped.isAcceptableForRequiredTask(allowSkip: false))
        XCTAssertTrue(TaskStatus.skipped.isAcceptableForRequiredTask(allowSkip: true))
        for status in [TaskStatus.pending, .waiting, .running, .failed, .timedOut] {
            XCTAssertFalse(status.isAcceptableForRequiredTask(allowSkip: true), status.rawValue)
        }
    }

    func testUnlockRequiresEveryRequiredTask() {
        XCTAssertTrue(CompletionEvaluator.canUnlock([task(.complete), task(.completeWithWarnings)]))
        XCTAssertFalse(CompletionEvaluator.canUnlock([task(.complete), task(.running)]))
        XCTAssertFalse(CompletionEvaluator.canUnlock([task(.complete), task(.timedOut)]))
        XCTAssertFalse(CompletionEvaluator.canUnlock([task(.skipped)]))
        XCTAssertTrue(CompletionEvaluator.canUnlock([task(.skipped, allowSkip: true)]))
    }

    func testOptionalTasksNeverBlockUnlock() {
        XCTAssertTrue(CompletionEvaluator.canUnlock([task(.complete), task(.failed, required: false), task(.pending, required: false)]))
        XCTAssertTrue(CompletionEvaluator.canUnlock([]))
    }

    func testOutcome() {
        XCTAssertEqual(CompletionEvaluator.outcome([task(.complete), task(.running, required: false)]), .inProgress)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.complete), task(.complete, required: false)]), .success)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.complete), task(.failed, required: false)]), .successWithWarnings)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.completeWithWarnings)]), .successWithWarnings)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.failed), task(.pending)]), .failed)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.timedOut)]), .failed)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.skipped)]), .failed)
        XCTAssertEqual(CompletionEvaluator.outcome([task(.skipped, allowSkip: true)]), .success)
    }

    func testStatusAggregation() {
        XCTAssertEqual(StatusAggregator.aggregate([]), .complete)
        XCTAssertEqual(StatusAggregator.aggregate([.complete, .failed, .running]), .failed)
        XCTAssertEqual(StatusAggregator.aggregate([.complete, .timedOut]), .timedOut)
        XCTAssertEqual(StatusAggregator.aggregate([.complete, .pending]), .running)
        XCTAssertEqual(StatusAggregator.aggregate([.pending, .pending]), .pending)
        XCTAssertEqual(StatusAggregator.aggregate([.pending, .waiting]), .waiting)
        XCTAssertEqual(StatusAggregator.aggregate([.complete, .completeWithWarnings]), .completeWithWarnings)
        XCTAssertEqual(StatusAggregator.aggregate([.skipped, .skipped]), .skipped)
        XCTAssertEqual(StatusAggregator.aggregate([.complete, .skipped]), .complete)
    }
}
