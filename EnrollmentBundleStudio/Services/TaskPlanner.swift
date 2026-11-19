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
        let folded = foldedScripts(in: project)
        var tasks: [PlannedTask] = []
        for group in project.applicationGroups {
            for application in group.applications {
                let script = linkedScript(of: application, in: project)
                tasks.append(PlannedTask(
                    taskIdentifier: application.taskIdentifier,
                    displayName: application.displayName,
                    type: taskType(for: application.installStrategy, hasLinkedScript: script != nil),
                    source: .application(application.id),
                    isEnabled: application.isEnabled,
                    isRequired: group.isRequired || application.execution.isRequired,
                    execution: effectiveExecution(of: application, script: script, folded: folded),
                    implicitDependencies: linkedScriptDependencies(of: application, script: script)
                ))
            }
        }
        for script in project.scripts where folded[script.taskIdentifier] == nil {
            tasks.append(PlannedTask(
                taskIdentifier: script.taskIdentifier,
                displayName: script.displayName,
                type: .shellScript,
                source: .script(script.id),
                isEnabled: true,
                isRequired: script.execution.isRequired,
                execution: rewritten(script.execution, folded: folded, owner: script.taskIdentifier),
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
                execution: rewritten(task.execution, folded: folded, owner: task.taskIdentifier),
                implicitDependencies: implicit
            ))
        }
        return tasks
    }

    // MARK: Linked scripts

    /// The imported script an enabled "Run custom script" application runs, or nil when it has none
    /// (or the link points at a script that is no longer in the project).
    static func linkedScript(of application: ApplicationItem, in project: EnrollmentProject) -> ScriptItem? {
        guard application.installStrategy == .customScript,
              let identifier = application.customScriptTaskIdentifier, !identifier.isEmpty else { return nil }
        return project.scripts.first { $0.taskIdentifier == identifier }
    }

    /// Scripts that an enabled application runs as part of its own task, keyed by the script's task identifier.
    /// Such a script has no row of its own: the application row shows the whole result. When several enabled
    /// applications link the same script, the first one in group order owns it for display and dependency
    /// rewriting; each of them still runs it.
    static func foldedScripts(in project: EnrollmentProject) -> [String: String] {
        var owners: [String: String] = [:]
        for group in project.applicationGroups {
            for application in group.applications where application.isEnabled {
                guard let script = linkedScript(of: application, in: project),
                      owners[script.taskIdentifier] == nil else { continue }
                owners[script.taskIdentifier] = application.taskIdentifier
            }
        }
        return owners
    }

    /// Execution options of an application task. When it runs a linked script, the retry count is the larger
    /// of the two, the application runs in the user context if either asks for it, and the script's own
    /// dependencies are added. The timeout, order, required state and messages stay the application's.
    private static func effectiveExecution(of application: ApplicationItem, script: ScriptItem?, folded: [String: String]) -> TaskExecutionOptions {
        var execution = rewritten(application.execution, folded: folded, owner: application.taskIdentifier)
        guard let script else { return execution }
        execution.retryCount = max(execution.retryCount, script.execution.retryCount)
        if script.execution.context == .user {
            execution.context = .user
        }
        for dependency in rewritten(script.execution, folded: folded, owner: application.taskIdentifier).dependencies
        where !execution.dependencies.contains(dependency) {
            execution.dependencies.append(dependency)
        }
        return execution
    }

    /// Points dependencies on a folded script at the application that runs it, and drops self references.
    private static func rewritten(_ execution: TaskExecutionOptions, folded: [String: String], owner: String) -> TaskExecutionOptions {
        var result = execution
        var dependencies: [String] = []
        for dependency in execution.dependencies {
            let target = folded[dependency] ?? dependency
            if target != owner && !dependencies.contains(target) {
                dependencies.append(target)
            }
        }
        result.dependencies = dependencies
        return result
    }

    /// An application that links a script that is not in the project keeps waiting for that identifier, so
    /// validation reports the missing dependency. A script that exists is run by the application itself.
    private static func linkedScriptDependencies(of application: ApplicationItem, script: ScriptItem?) -> [String] {
        guard application.installStrategy == .customScript, script == nil,
              let identifier = application.customScriptTaskIdentifier, !identifier.isEmpty else { return [] }
        return [identifier]
    }

    static func taskType(for strategy: ApplicationInstallStrategy) -> TaskType {
        switch strategy {
        case .waitForIntune, .detectionOnly: return .applicationDetection
        case .bundledInstaller: return .packageInstallation
        case .customScript: return .shellScript
        }
    }

    /// An application that runs a script is shown as a script task; one with no script is only detected.
    static func taskType(for strategy: ApplicationInstallStrategy, hasLinkedScript: Bool) -> TaskType {
        if strategy == .customScript && !hasLinkedScript {
            return .applicationDetection
        }
        return taskType(for: strategy)
    }
}
