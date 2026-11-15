import SwiftUI

struct TaskEditContext: Identifiable {
    let id = UUID()
    let taskIdentifier: String
}

/// The edited value returned by TaskEditorSheet.
enum TaskDraft {
    case application(ApplicationItem)
    case script(ScriptItem)
    case system(EnrollmentTask)
}

extension EnrollmentProject {
    func taskDraft(for taskIdentifier: String) -> TaskDraft? {
        if let application = allApplications.first(where: { $0.taskIdentifier == taskIdentifier }) {
            return .application(application)
        }
        if let script = scripts.first(where: { $0.taskIdentifier == taskIdentifier }) {
            return .script(script)
        }
        if let task = systemTasks.first(where: { $0.taskIdentifier == taskIdentifier }) {
            return .system(task)
        }
        return nil
    }

    mutating func apply(_ draft: TaskDraft) {
        switch draft {
        case .application(let application): updateApplication(application)
        case .script(let script): updateScript(script)
        case .system(let task): updateSystemTask(task)
        }
    }
}

/// Edits execution settings of any task, plus the name and type-specific fields of scripts and system tasks.
/// Applications keep their detection settings in the Applications editor.
struct TaskEditorSheet: View {
    let context: TaskEditContext
    let project: EnrollmentProject
    let onSave: (TaskDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var options: TaskExecutionOptions
    @State private var exitCodesText: String
    @State private var validationCommand: String
    private let original: TaskDraft?

    init(context: TaskEditContext, project: EnrollmentProject, onSave: @escaping (TaskDraft) -> Void) {
        self.context = context
        self.project = project
        self.onSave = onSave
        let draft = project.taskDraft(for: context.taskIdentifier)
        self.original = draft
        switch draft {
        case .application(let application)?:
            _displayName = State(initialValue: application.displayName)
            _options = State(initialValue: application.execution)
            _exitCodesText = State(initialValue: "")
            _validationCommand = State(initialValue: "")
        case .script(let script)?:
            _displayName = State(initialValue: script.displayName)
            _options = State(initialValue: script.execution)
            _exitCodesText = State(initialValue: script.successExitCodes.map(String.init).joined(separator: ", "))
            _validationCommand = State(initialValue: "")
        case .system(let task)?:
            _displayName = State(initialValue: task.displayName)
            _options = State(initialValue: task.execution)
            _exitCodesText = State(initialValue: "")
            _validationCommand = State(initialValue: task.validation?.value ?? "")
        case nil:
            _displayName = State(initialValue: "")
            _options = State(initialValue: TaskExecutionOptions())
            _exitCodesText = State(initialValue: "")
            _validationCommand = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if original == nil {
                Text("This task no longer exists.")
                    .padding(40)
            } else {
                Form {
                    identitySection
                    TaskOptionsEditor(options: $options, candidates: candidates, requiredLocked: requiredLocked)
                }
                .formStyle(.grouped)
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(issues, id: \.self) { issue in
                        FieldIssueLabel(message: issue, severity: .error)
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let draft = makeDraft() {
                        onSave(draft)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(original == nil || !issues.isEmpty)
            }
            .padding(14)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 560, idealHeight: 720)
    }

    @ViewBuilder
    private var identitySection: some View {
        Section("Task") {
            switch original {
            case .application?:
                LabeledContent("Application", value: displayName)
                Text("Detection and delivery settings are edited in Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .script(let script)?:
                TextField("Display name", text: $displayName)
                LabeledContent("File", value: script.relativePath)
                TextField("Success exit codes", text: $exitCodesText, prompt: Text("0"))
                Text("Comma-separated, 0 to 255. The task succeeds when the script exits with one of these codes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .system(let task)?:
                TextField("Display name", text: $displayName)
                LabeledContent("Type", value: task.type.title)
                if task.type == .waitCondition || task.type == .configurationValidation {
                    TextField("Validation command", text: $validationCommand, prompt: Text("/usr/bin/profiles status -type enrollment"))
                        .font(.body.monospaced())
                    Text("Runs as root on the device. The task is complete when the command exits with 0. It never runs on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if task.type == .finalValidation {
                    Text("Waits for every required task automatically, in addition to any dependencies chosen below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case nil:
                EmptyView()
            }
            LabeledContent("Task identifier") {
                Text(context.taskIdentifier)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private var candidates: [PlannedTask] {
        TaskPlanner.plan(project).filter { $0.taskIdentifier != context.taskIdentifier }
    }

    private var requiredLocked: Bool {
        guard case .application(let application)? = original else { return false }
        return project.applicationGroups.first { group in group.applications.contains { $0.id == application.id } }?.isRequired ?? false
    }

    private var issues: [String] {
        var result: [String] = []
        switch original {
        case .script?:
            if displayName.trimmingCharacters(in: .whitespaces).isEmpty { result.append("Enter a display name.") }
            if ExitCodeParser.parse(exitCodesText) == nil { result.append("Enter success exit codes between 0 and 255, separated by commas.") }
        case .system?:
            if displayName.trimmingCharacters(in: .whitespaces).isEmpty { result.append("Enter a display name.") }
        case .application?, nil:
            break
        }
        return result
    }

    private func makeDraft() -> TaskDraft? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch original {
        case .application(var application)?:
            application.execution = options
            return .application(application)
        case .script(var script)?:
            script.displayName = name
            script.successExitCodes = ExitCodeParser.parse(exitCodesText) ?? [0]
            script.execution = options
            return .script(script)
        case .system(var task)?:
            task.displayName = name
            task.execution = options
            if task.type == .waitCondition || task.type == .configurationValidation {
                task.validation = TaskCheck(method: .customCommand, value: validationCommand.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .system(task)
        case nil:
            return nil
        }
    }
}
