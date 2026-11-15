import SwiftUI

/// Form sections for the execution options every task shares. Place inside a Form.
struct TaskOptionsEditor: View {
    @Binding var options: TaskExecutionOptions
    /// Tasks this task may depend on (the task itself is excluded by the caller).
    let candidates: [PlannedTask]
    /// True when a required group forces the task to be required.
    var requiredLocked = false

    var body: some View {
        Section("Behavior") {
            Toggle("Required", isOn: $options.isRequired)
                .disabled(requiredLocked)
            if requiredLocked {
                Text("The group is required, so this task is always required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Show in the enrollment list", isOn: $options.isVisible)
            Picker("Runs as", selection: $options.context) {
                ForEach(ExecutionContext.allCases) { context in
                    Text(context.title).tag(context)
                }
            }
            if options.context == .user {
                Text("Console-user tasks wait for a logged-in GUI session and run with launchctl asuser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Allow Skipped as an acceptable result", isOn: $options.allowSkip)
            Toggle("Run again on later runs after completing", isOn: $options.allowRerun)
        }

        Section("Timing") {
            Stepper(value: $options.timeoutSeconds, in: ProjectSettings.taskTimeoutRange, step: 30) {
                LabeledContent("Timeout", value: DurationFormatter.format(seconds: options.timeoutSeconds))
            }
            Stepper(value: $options.retryCount, in: 0...5) {
                LabeledContent("Retries", value: "\(options.retryCount)")
            }
        }

        Section("Order") {
            Stepper(value: $options.executionOrder, in: 0...10_000, step: 10) {
                LabeledContent("Execution order", value: "\(options.executionOrder)")
            }
            TextField("Parallel group", text: $options.parallelGroup, prompt: Text("Empty runs sequentially"))
            Text("Lower numbers run first. Consecutive tasks with the same parallel group name may run at the same time. Dependencies always win.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Depends on") {
            if candidates.isEmpty {
                Text("There are no other tasks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { candidate in
                Toggle(isOn: dependencyBinding(candidate.taskIdentifier)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.displayName.isEmpty ? candidate.taskIdentifier : candidate.displayName)
                        Text("\(candidate.taskIdentifier)  \(candidate.sourceTitle)\(candidate.isEnabled ? "" : ", disabled")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            let unknown = options.dependencies.filter { id in !candidates.contains { $0.taskIdentifier == id } }
            ForEach(unknown, id: \.self) { id in
                HStack {
                    FieldIssueLabel(message: "Depends on missing task \(id)", severity: .error)
                    Spacer()
                    Button("Remove") {
                        options.dependencies.removeAll { $0 == id }
                    }
                }
            }
        }

        Section("Status messages") {
            TextField("Waiting", text: $options.messages.waiting)
            TextField("In progress", text: $options.messages.progress)
            TextField("Success", text: $options.messages.success)
            TextField("Warning", text: $options.messages.warning)
            TextField("Failure", text: $options.messages.failure)
        }
    }

    private func dependencyBinding(_ taskIdentifier: String) -> Binding<Bool> {
        Binding(
            get: { options.dependencies.contains(taskIdentifier) },
            set: { isOn in
                if isOn {
                    if !options.dependencies.contains(taskIdentifier) {
                        options.dependencies.append(taskIdentifier)
                    }
                } else {
                    options.dependencies.removeAll { $0 == taskIdentifier }
                }
            }
        )
    }
}
