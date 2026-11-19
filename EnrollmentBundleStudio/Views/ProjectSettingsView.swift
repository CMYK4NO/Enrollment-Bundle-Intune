import SwiftUI

/// Editor for the runtime settings of the generated enrollment framework.
struct ProjectSettingsView: View {
    @Binding var values: RuntimeSettingsDefaults

    private var settings: RuntimeSettingsDefaults { values }

    var body: some View {
        Form {
            Section("Dialog window") {
                Stepper(value: $values.windowWidth, in: ProjectSettings.windowWidthRange, step: 20) {
                    LabeledContent("Width", value: "\(settings.windowWidth) pt")
                }
                Stepper(value: $values.windowHeight, in: ProjectSettings.windowHeightRange, step: 20) {
                    LabeledContent("Height", value: "\(settings.windowHeight) pt")
                }
                Toggle("Lock completion button until required tasks finish", isOn: $values.lockCompletionButtonUntilRequiredComplete)
                Text("Required tasks must reach Complete or Complete with warnings, or Skipped where a task explicitly allows it. Hidden tasks count too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Timing") {
                Stepper(value: $values.defaultTaskTimeoutSeconds, in: ProjectSettings.taskTimeoutRange, step: 60) {
                    LabeledContent("Default task timeout", value: DurationFormatter.format(seconds: settings.defaultTaskTimeoutSeconds))
                }
                Stepper(value: $values.maximumEnrollmentDurationSeconds, in: ProjectSettings.enrollmentDurationRange, step: 300) {
                    LabeledContent("Maximum enrollment duration", value: DurationFormatter.format(seconds: settings.maximumEnrollmentDurationSeconds))
                }
                if settings.maximumEnrollmentDurationSeconds < settings.defaultTaskTimeoutSeconds {
                    FieldIssueLabel(message: "The maximum duration is shorter than a single task timeout.", severity: .warning)
                }
            }

            Section("Applications") {
                Picker("Default strategy for new apps", selection: $values.applicationInstallStrategy.deferringWrites()) {
                    ForEach(ApplicationInstallStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                ForEach(ApplicationInstallStrategy.allCases) { strategy in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strategy.title).font(.callout.weight(.semibold))
                        Text(strategy.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Scripts") {
                Picker("Script execution", selection: $values.scriptExecutionStrategy.deferringWrites()) {
                    ForEach(ScriptExecutionStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                Text(settings.scriptExecutionStrategy.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("swiftDialog") {
                ValidatedTextField(
                    title: "Binary path",
                    text: $values.swiftDialogPath,
                    issue: FieldValidator.absolutePathIssue(settings.swiftDialogPath)
                )
                ValidatedTextField(
                    title: "Minimum version",
                    text: $values.swiftDialogMinimumVersion,
                    prompt: "2.5.0",
                    issue: FieldValidator.versionIssue(settings.swiftDialogMinimumVersion)
                )
                Text("If swiftDialog is missing or too old on the device, the dialog is skipped and logged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Onboarding guard") {
                ValidatedTextField(
                    title: "Onboarding flag",
                    text: $values.onboardingFlagPath,
                    prompt: ProjectSettings.defaultOnboardingFlagPath,
                    issue: settings.onboardingFlagPath.isEmpty ? nil : FieldValidator.absolutePathIssue(settings.onboardingFlagPath)
                )
                Stepper(value: $values.enrollmentWindowHours, in: ProjectSettings.enrollmentWindowRange) {
                    LabeledContent("Enrollment window", value: "\(settings.enrollmentWindowHours) h")
                }
                Text("The framework writes this flag after a successful enrollment and skips if it already exists. A first run only starts when the Mac was MDM-enrolled within the enrollment window; later resumes are not affected, and --force overrides both checks. Leave the flag empty to turn the guard off (the window is then not checked).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.onboardingFlagPath != ProjectSettings.defaultOnboardingFlagPath {
                    Button("Use the default location") {
                        values.onboardingFlagPath = ProjectSettings.defaultOnboardingFlagPath
                    }
                }
            }

            Section("Device locations") {
                ValidatedTextField(
                    title: "Install location",
                    text: $values.installLocation,
                    issue: FieldValidator.deviceDirectoryIssue(settings.installLocation)
                )
                ValidatedTextField(
                    title: "State directory",
                    text: $values.stateDirectory,
                    issue: FieldValidator.deviceDirectoryIssue(settings.stateDirectory)
                )
                ValidatedTextField(
                    title: "Detection app folder",
                    text: Binding(
                        get: { values.detectionAppDirectory ?? "" },
                        set: { values.detectionAppDirectory = $0.isEmpty ? nil : $0 }
                    ),
                    prompt: "Empty = the install location",
                    issue: FieldValidator.detectionDirectoryIssue(settings.detectionAppDirectory ?? "")
                )
                Text("The package installs a small placeholder app here. Its bundle identifier and version are the package's, so Intune can detect that the package is installed. If Intune does not detect it in the install location, try /Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Debug logging", isOn: $values.debugLogging)
                Text("Logs are written to /Library/Logs/Microsoft/IntuneScripts/onBoarding/ on the device. The newest 10 logs are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
