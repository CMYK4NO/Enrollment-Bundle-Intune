import SwiftUI

private struct ExecutionRow: Identifiable {
    let task: PlannedTask
    let step: Int?
    let batchSize: Int
    let state: RowState

    enum RowState {
        case ready
        case disabled
        case blocked
        case inCycle
    }

    var id: String { task.taskIdentifier }
}

/// Resolved run order of every task, with order, parallel groups and dependencies.
struct ExecutionView: View {
    @Binding var document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel
    @State private var selection: Set<String> = []
    @State private var editContext: TaskEditContext?
    @State private var pendingRemoval: EnrollmentTask?

    var body: some View {
        let plan = TaskPlanner.plan(document.project)
        let analysis = DependencyGraph.analyze(plan)
        let rows = makeRows(plan: plan, analysis: analysis)
        VStack(spacing: 0) {
            actionBar
            if analysis.hasCriticalIssues {
                NoticeBanner(
                    symbolName: "xmark.octagon.fill",
                    message: "There are dependency errors. Building is blocked until they are fixed. See Validation for details.",
                    tint: .red
                )
            }
            Divider()
            Table(rows, selection: $selection) {
                TableColumn("Step") { row in
                    Text(row.step.map { String($0) } ?? "–")
                        .monospacedDigit()
                }
                .width(min: 36, ideal: 44, max: 60)
                TableColumn("Task") { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.task.displayName.isEmpty ? row.task.taskIdentifier : row.task.displayName)
                        Text(row.task.taskIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 180, ideal: 240)
                TableColumn("Type") { row in
                    Text(row.task.type.title)
                }
                .width(min: 110, ideal: 150)
                TableColumn("Required") { row in
                    Text(row.task.isRequired ? "Required" : "Optional")
                        .foregroundStyle(row.task.isRequired ? Color.primary : Color.secondary)
                }
                .width(min: 64, ideal: 72)
                TableColumn("Runs as") { row in
                    Text(row.task.execution.context == .user ? "User" : "Root")
                }
                .width(min: 44, ideal: 52)
                TableColumn("Order") { row in
                    Text("\(row.task.execution.executionOrder)")
                        .monospacedDigit()
                }
                .width(min: 44, ideal: 52)
                TableColumn("Parallel") { row in
                    Text(parallelText(row))
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 110)
                TableColumn("Depends on") { row in
                    Text(dependencyText(row.task))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 120, ideal: 200)
                TableColumn("State") { row in
                    stateLabel(row.state)
                }
                .width(min: 80, ideal: 100)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first {
                    Button("Edit…") { editContext = TaskEditContext(taskIdentifier: id) }
                    if let task = document.project.systemTasks.first(where: { $0.taskIdentifier == id }) {
                        Divider()
                        Button("Remove System Task…", role: .destructive) { pendingRemoval = task }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first {
                    editContext = TaskEditContext(taskIdentifier: id)
                }
            }
            Divider()
            Text("Steps follow dependencies first, then execution order. Tasks in a batch (same parallel group, no dependency between them) may run at the same time. Final validation always waits for every required task. Double-click a row to edit it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editContext) { context in
            TaskEditorSheet(context: context, project: document.project) { draft in
                document.project.apply(draft)
            }
        }
        .confirmationDialog(
            "Remove \"\(pendingRemoval?.displayName ?? "")\"?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { task in
            Button("Remove", role: .destructive) {
                document.project.removeSystemTask(id: task.id)
                selection.remove(task.taskIdentifier)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Other tasks stop depending on it. You can undo this with Edit > Undo.")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Intune Synchronization") { addSystemTask(.intuneSync) }
                Button("Wait Condition") { addSystemTask(.waitCondition) }
                Button("Configuration Validation") { addSystemTask(.configurationValidation) }
                if !document.project.systemTasks.contains(where: { $0.type == .finalValidation }) {
                    Button("Final Validation") { addSystemTask(.finalValidation) }
                }
            } label: {
                Label("Add System Task", systemImage: "plus")
            }
            .fixedSize()
            Button {
                if let id = selection.first {
                    editContext = TaskEditContext(taskIdentifier: id)
                }
            } label: {
                Label("Edit…", systemImage: "pencil")
            }
            .disabled(selection.count != 1)
            Spacer()
            Text("Applications are added in Applications and scripts in Scripts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: Helpers

    private func addSystemTask(_ type: TaskType) {
        let id = document.project.addSystemTask(type: type)
        if let task = document.project.systemTask(id: id) {
            selection = [task.taskIdentifier]
            editContext = TaskEditContext(taskIdentifier: task.taskIdentifier)
        }
    }

    private func makeRows(plan: [PlannedTask], analysis: DependencyAnalysis) -> [ExecutionRow] {
        var byID: [String: PlannedTask] = [:]
        for task in plan where byID[task.taskIdentifier] == nil {
            byID[task.taskIdentifier] = task
        }
        var batchSize: [String: Int] = [:]
        for batch in analysis.batches {
            for id in batch { batchSize[id] = batch.count }
        }
        var rows: [ExecutionRow] = []
        for (index, id) in analysis.orderedTaskIDs.enumerated() {
            guard let task = byID[id] else { continue }
            let state: ExecutionRow.RowState
            if analysis.tasksInCycles.contains(id) {
                state = .inCycle
            } else if analysis.blockedTaskIDs.contains(id) {
                state = .blocked
            } else {
                state = .ready
            }
            rows.append(ExecutionRow(task: task, step: index + 1, batchSize: batchSize[id] ?? 1, state: state))
        }
        let listed = Set(rows.map { $0.id })
        for task in plan where !listed.contains(task.taskIdentifier) && !task.isEnabled {
            rows.append(ExecutionRow(task: task, step: nil, batchSize: 1, state: .disabled))
        }
        return rows
    }

    private func parallelText(_ row: ExecutionRow) -> String {
        let group = row.task.execution.parallelGroup
        if group.isEmpty { return "Sequential" }
        return row.batchSize > 1 ? "\(group) (\(row.batchSize) together)" : group
    }

    private func dependencyText(_ task: PlannedTask) -> String {
        if task.type == .finalValidation {
            let explicit = task.execution.dependencies
            return explicit.isEmpty ? "All required tasks" : "All required tasks, " + explicit.joined(separator: ", ")
        }
        return task.execution.dependencies.isEmpty ? "–" : task.execution.dependencies.joined(separator: ", ")
    }

    @ViewBuilder
    private func stateLabel(_ state: ExecutionRow.RowState) -> some View {
        switch state {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .disabled:
            Label("Disabled", systemImage: "pause.circle").foregroundStyle(.secondary)
        case .blocked:
            Label("Blocked", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        case .inCycle:
            Label("Cycle", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.red)
        }
    }
}
