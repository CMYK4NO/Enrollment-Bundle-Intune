import Foundation

/// One moment in a simulated enrollment: the simulated status of every regular task after this step.
struct SimulationStep: Equatable {
    /// Seconds to wait before applying this step.
    let delay: Double
    let overrides: [String: TaskStatus]
    let label: String
}

/// Builds a simulated run for a scenario. Tasks advance in real run order (dependencies, then execution
/// order): pending, then waiting (Intune detection) or running (installers, scripts, checks), then the
/// scenario's final status. Final validation is left to the preview logic, which completes it only when
/// every other task is acceptable, exactly as on the device. Nothing is executed.
enum SimulationTimeline {
    static func make(project: EnrollmentProject, scenario: PreviewScenario, stepDuration: Double = 0.8) -> [SimulationStep] {
        let plan = TaskPlanner.plan(project)
        let analysis = DependencyGraph.analyze(plan)
        var byID: [String: PlannedTask] = [:]
        for task in plan where byID[task.taskIdentifier] == nil {
            byID[task.taskIdentifier] = task
        }
        let ordered = analysis.orderedTaskIDs.compactMap { byID[$0] }.filter { $0.type != .finalValidation }

        let finalState = PreviewBuilder.makeState(project: project, scenario: finishingScenario(scenario), overrides: [:])
        var finalStatus: [String: TaskStatus] = [:]
        for item in finalState.evaluationItems {
            finalStatus[item.id] = item.status
        }

        var current: [String: TaskStatus] = [:]
        for task in ordered {
            current[task.taskIdentifier] = .pending
        }
        var steps = [SimulationStep(delay: 0, overrides: current, label: "Enrollment starts")]
        for task in ordered {
            let active: TaskStatus = isWaitingTask(task, project: project) ? .waiting : .running
            current[task.taskIdentifier] = active
            steps.append(SimulationStep(delay: stepDuration, overrides: current, label: "\(task.displayName): \(active.title)"))
            let result = finalStatus[task.taskIdentifier] ?? .complete
            current[task.taskIdentifier] = result
            steps.append(SimulationStep(delay: stepDuration, overrides: current, label: "\(task.displayName): \(result.title)"))
        }
        return steps
    }

    /// A simulated run always finishes. "Just started" and "In progress" describe a moment in time, so
    /// their simulation runs through to successful completion; the other scenarios end as they describe.
    static func finishingScenario(_ scenario: PreviewScenario) -> PreviewScenario {
        switch scenario {
        case .initial, .inProgress: return .allComplete
        default: return scenario
        }
    }

    /// Applications without a package wait for Intune; everything else actively runs.
    static func isWaitingTask(_ task: PlannedTask, project: EnrollmentProject) -> Bool {
        guard case .application(let id) = task.source, let application = project.application(id: id) else { return false }
        if TaskPlanner.linkedScript(of: application, in: project) != nil { return false }
        return !(application.installStrategy == .bundledInstaller && application.installer != nil)
    }
}

/// Plays a timeline by handing each step's overrides to a callback. The callback runs on the main actor,
/// outside view updates.
@MainActor
final class SimulationPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentLabel = ""
    private var playback: Task<Void, Never>?

    func play(_ steps: [SimulationStep], apply: @escaping ([String: TaskStatus]) -> Void) {
        stop()
        isPlaying = true
        playback = Task { [weak self] in
            for step in steps {
                if step.delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
                }
                if Task.isCancelled { return }
                apply(step.overrides)
                self?.currentLabel = step.label
            }
            self?.isPlaying = false
        }
    }

    func stop() {
        playback?.cancel()
        playback = nil
        isPlaying = false
        currentLabel = ""
    }
}
