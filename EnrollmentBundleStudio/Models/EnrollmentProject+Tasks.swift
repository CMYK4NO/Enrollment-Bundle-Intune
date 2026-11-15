import Foundation

/// Script, system-task and execution-option editing.
extension EnrollmentProject {
    var nextExecutionOrder: Int {
        let orders = allApplications.map { $0.execution.executionOrder }
            + scripts.map { $0.execution.executionOrder }
            + systemTasks.filter { $0.type != .finalValidation }.map { $0.execution.executionOrder }
        return ((orders.max() ?? 90) / 10 + 1) * 10
    }

    func script(id: UUID) -> ScriptItem? {
        scripts.first { $0.id == id }
    }

    func systemTask(id: UUID) -> EnrollmentTask? {
        systemTasks.first { $0.id == id }
    }

    // MARK: Execution options by task identifier

    func executionOptions(forTask taskIdentifier: String) -> TaskExecutionOptions? {
        if let application = allApplications.first(where: { $0.taskIdentifier == taskIdentifier }) {
            return application.execution
        }
        if let script = scripts.first(where: { $0.taskIdentifier == taskIdentifier }) {
            return script.execution
        }
        return systemTasks.first { $0.taskIdentifier == taskIdentifier }?.execution
    }

    mutating func setExecutionOptions(_ options: TaskExecutionOptions, forTask taskIdentifier: String) {
        for groupIndex in applicationGroups.indices {
            if let itemIndex = applicationGroups[groupIndex].applications.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) {
                applicationGroups[groupIndex].applications[itemIndex].execution = options
                return
            }
        }
        if let index = scripts.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) {
            scripts[index].execution = options
            return
        }
        if let index = systemTasks.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) {
            systemTasks[index].execution = options
        }
    }

    /// Removes the given identifiers from every task's dependency list.
    mutating func removeDependencyReferences(to taskIdentifiers: Set<String>) {
        guard !taskIdentifiers.isEmpty else { return }
        for groupIndex in applicationGroups.indices {
            for itemIndex in applicationGroups[groupIndex].applications.indices {
                applicationGroups[groupIndex].applications[itemIndex].execution.dependencies.removeAll { taskIdentifiers.contains($0) }
            }
        }
        for index in scripts.indices {
            scripts[index].execution.dependencies.removeAll { taskIdentifiers.contains($0) }
        }
        for index in systemTasks.indices {
            systemTasks[index].execution.dependencies.removeAll { taskIdentifiers.contains($0) }
        }
    }

    /// Task identifiers that depend (directly) on the given task.
    func dependents(of taskIdentifier: String) -> [String] {
        TaskPlanner.plan(self)
            .filter { $0.execution.dependencies.contains(taskIdentifier) }
            .map { $0.taskIdentifier }
    }

    // MARK: Scripts

    mutating func addScript(_ script: ScriptItem) {
        scripts.append(script)
    }

    @discardableResult
    mutating func updateScript(_ script: ScriptItem) -> ScriptItem? {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return nil }
        let previous = scripts[index]
        scripts[index] = script
        return previous
    }

    @discardableResult
    mutating func removeScript(id: UUID) -> ScriptItem? {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = scripts.remove(at: index)
        removeDependencyReferences(to: [removed.taskIdentifier])
        return removed
    }

    // MARK: System tasks

    @discardableResult
    mutating func addSystemTask(type: TaskType) -> UUID {
        var execution = TaskExecutionOptions()
        execution.messages = .system
        execution.executionOrder = nextExecutionOrder
        let displayName: String
        let symbol: String
        var validation: TaskCheck?
        switch type {
        case .intuneSync:
            displayName = "Intune synchronization"
            symbol = "arrow.triangle.2.circlepath"
            execution.isRequired = false
            execution.timeoutSeconds = 300
        case .waitCondition:
            displayName = "Wait condition"
            symbol = "hourglass"
            validation = TaskCheck(method: .customCommand, value: "")
        case .configurationValidation:
            displayName = "Configuration validation"
            symbol = "checklist"
            validation = TaskCheck(method: .customCommand, value: "")
        case .finalValidation:
            let task = EnrollmentTask.makeFinalValidation(taskIdentifier: uniqueTaskIdentifier(for: "final validation", prefix: "system"))
            systemTasks.append(task)
            return task.id
        case .applicationDetection, .packageInstallation, .shellScript:
            displayName = type.title
            symbol = "gearshape"
        }
        let task = EnrollmentTask(
            id: UUID(),
            taskIdentifier: uniqueTaskIdentifier(for: displayName, prefix: "system"),
            displayName: displayName,
            type: type,
            icon: IconSource(kind: .sfSymbol, value: symbol),
            detection: nil,
            validation: validation,
            execution: execution
        )
        systemTasks.append(task)
        return task.id
    }

    @discardableResult
    mutating func updateSystemTask(_ task: EnrollmentTask) -> EnrollmentTask? {
        guard let index = systemTasks.firstIndex(where: { $0.id == task.id }) else { return nil }
        let previous = systemTasks[index]
        systemTasks[index] = task
        return previous
    }

    @discardableResult
    mutating func removeSystemTask(id: UUID) -> EnrollmentTask? {
        guard let index = systemTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = systemTasks.remove(at: index)
        removeDependencyReferences(to: [removed.taskIdentifier])
        return removed
    }
}
