import Foundation

/// One task in the flat enrollment plan derived from applications, scripts and system tasks.
/// The generated tasks.json (Phase 3) is produced from this plan.
struct PlannedTask: Identifiable, Equatable {
    enum Source: Equatable {
        case application(UUID)
        case script(UUID)
        case system(UUID)
    }

    let taskIdentifier: String
    let displayName: String
    let type: TaskType
    let source: Source
    let isEnabled: Bool
    /// Effective required state (a required group makes its applications required).
    let isRequired: Bool
    let execution: TaskExecutionOptions
    /// Dependencies added by the planner, for example final validation waiting for every required task.
    let implicitDependencies: [String]

    var id: String { taskIdentifier }

    var allDependencies: [String] {
        var result: [String] = []
        for dependency in execution.dependencies + implicitDependencies where !result.contains(dependency) {
            result.append(dependency)
        }
        return result
    }

    var sourceTitle: String {
        switch source {
        case .application: return "Application"
        case .script: return "Script"
        case .system: return "System"
        }
    }
}

enum TaskPlanner {
    static func plan(_ project: EnrollmentProject) -> [PlannedTask] {
        var tasks: [PlannedTask] = []
        for group in project.applicationGroups {
            for application in group.applications {
                tasks.append(PlannedTask(
                    taskIdentifier: application.taskIdentifier,
                    displayName: application.displayName,
                    type: taskType(for: application.installStrategy),
                    source: .application(application.id),
                    isEnabled: application.isEnabled,
                    isRequired: group.isRequired || application.execution.isRequired,
                    execution: application.execution,
                    implicitDependencies: linkedScriptDependencies(of: application)
                ))
            }
        }
        for script in project.scripts {
            tasks.append(PlannedTask(
                taskIdentifier: script.taskIdentifier,
                displayName: script.displayName,
                type: .shellScript,
                source: .script(script.id),
                isEnabled: true,
                isRequired: script.execution.isRequired,
                execution: script.execution,
                implicitDependencies: []
            ))
        }

        let requiredBeforeFinal = tasks.filter { $0.isEnabled && $0.isRequired }.map { $0.taskIdentifier }
        let nonFinalSystemRequired = project.systemTasks
            .filter { $0.type != .finalValidation && $0.execution.isRequired }
            .map { $0.taskIdentifier }

        for task in project.systemTasks {
            let implicit: [String]
            if task.type == .finalValidation {
                implicit = (requiredBeforeFinal + nonFinalSystemRequired).filter { $0 != task.taskIdentifier }
            } else {
                implicit = []
            }
            tasks.append(PlannedTask(
                taskIdentifier: task.taskIdentifier,
                displayName: task.displayName,
                type: task.type,
                source: .system(task.id),
                isEnabled: true,
                isRequired: task.execution.isRequired,
                execution: task.execution,
                implicitDependencies: implicit
            ))
        }
        return tasks
    }

    /// A "Run custom script" app waits for its linked script task.
    private static func linkedScriptDependencies(of application: ApplicationItem) -> [String] {
        guard application.installStrategy == .customScript,
              let script = application.customScriptTaskIdentifier, !script.isEmpty else { return [] }
        return [script]
    }

    static func taskType(for strategy: ApplicationInstallStrategy) -> TaskType {
        switch strategy {
        case .waitForIntune, .detectionOnly: return .applicationDetection
        case .bundledInstaller: return .packageInstallation
        case .customScript: return .shellScript
        }
    }
}
