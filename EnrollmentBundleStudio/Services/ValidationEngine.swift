import Foundation

/// Facts about the administrator's Mac that validation needs. Injected so tests never touch the real system.
struct ValidationEnvironment {
    var fileExists: (String) -> Bool
    var isWritableDirectory: (String) -> Bool
    var isKnownSymbol: (String) -> Bool
    /// Path of a local ShellCheck, or nil when not installed.
    var shellCheckPath: String?

    /// Everything exists and works. Used by tests that are not about the environment.
    static let permissive = ValidationEnvironment(
        fileExists: { _ in true },
        isWritableDirectory: { _ in true },
        isKnownSymbol: { _ in true },
        shellCheckPath: "/opt/homebrew/bin/shellcheck"
    )
}

/// Checks a whole project. Errors block exporting the framework and building packages.
enum ValidationEngine {
    /// `installerPaths` are the installer packages available in the document (Installers/<name>.pkg).
    static func validate(project: EnrollmentProject, assets: [String: Data], environment: ValidationEnvironment,
                         installerPaths: Set<String> = []) -> ValidationReport {
        var issues: [ValidationIssue] = []
        func add(_ severity: ValidationSeverity, _ area: ValidationArea, _ component: String, _ message: String, _ remediation: String) {
            issues.append(ValidationIssue(severity: severity, area: area, component: component, message: message, remediation: remediation))
        }

        let plan = TaskPlanner.plan(project)
        let analysis = DependencyGraph.analyze(plan)
        let names = Dictionary(plan.map { ($0.taskIdentifier, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        func name(_ id: String) -> String { names[id].map { "\($0) (\(id))" } ?? id }

        checkProject(project, environment: environment, add: add)
        checkBranding(project, assets: assets, environment: environment, add: add)
        checkApplications(project, assets: assets, environment: environment, installerPaths: installerPaths, add: add)
        checkScripts(project, assets: assets, environment: environment, add: add)
        checkSystemTasks(project, add: add)
        checkDependencies(analysis, name: name, add: add)
        checkUnlock(project, plan: plan, analysis: analysis, assets: assets, installerPaths: installerPaths, name: name, add: add)
        checkEnvironment(project, assets: assets, environment: environment, add: add)

        return ValidationReport(issues: issues)
    }

    typealias Add = (ValidationSeverity, ValidationArea, String, String, String) -> Void

    // MARK: Project settings

    private static func checkProject(_ project: EnrollmentProject, environment: ValidationEnvironment, add: Add) {
        let settings = project.settings
        if settings.organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, .project, "Organization name", "The organization name is missing.", "Enter it in Overview or Branding.")
        }
        if settings.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, .project, "Project name", "The project name is missing.", "Enter a project name in Overview.")
        }
        if settings.packageDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, .project, "Package display name", "The package display name is missing.", "Enter a package display name in Overview.")
        }
        if !FieldValidator.isValidReverseDNS(settings.packageIdentifier) {
            add(.error, .project, "Package identifier", "\"\(settings.packageIdentifier)\" is not a valid reverse-DNS identifier.",
                "Use a format such as com.company.enrollment.bundle.")
        }
        if !FieldValidator.isValidReverseDNS(settings.bundleIdentifier) {
            add(.error, .project, "Bundle identifier", "\"\(settings.bundleIdentifier)\" is not a valid reverse-DNS identifier.",
                "Use a format such as com.company.enrollment.")
        }
        if settings.packageIdentifier.hasPrefix("com.example.") || settings.bundleIdentifier.hasPrefix("com.example.") {
            add(.warning, .project, "Identifiers", "The project still uses the com.example placeholder identifiers.",
                "Replace them with your organization's prefix in Overview before deploying.")
        }
        if !FieldValidator.isValidVersion(settings.packageVersion) {
            add(.error, .project, "Package version", "\"\(settings.packageVersion)\" is not a valid version.", "Use numbers separated by dots, for example 1.0.0.")
        }
        if !ProjectSettings.supportedMinimumMacOSVersions.contains(where: { $0.version == settings.minimumMacOSVersion }) {
            add(.error, .project, "Minimum macOS", "\"\(settings.minimumMacOSVersion)\" is not a supported minimum version.", "Choose a version in Overview.")
        }
        if !ProjectSettings.windowWidthRange.contains(settings.windowWidth) || !ProjectSettings.windowHeightRange.contains(settings.windowHeight) {
            add(.error, .project, "Dialog window", "The window size \(settings.windowWidth) × \(settings.windowHeight) is outside the supported range.",
                "Use 600 to 1600 points wide and 400 to 1200 points high in Settings.")
        }
        if !ProjectSettings.taskTimeoutRange.contains(settings.defaultTaskTimeoutSeconds) {
            add(.error, .project, "Default task timeout", "The default task timeout is outside 30 seconds to 4 hours.", "Adjust it in Settings.")
        }
        if !ProjectSettings.enrollmentDurationRange.contains(settings.maximumEnrollmentDurationSeconds) {
            add(.error, .project, "Maximum enrollment duration", "The maximum enrollment duration is outside 10 minutes to 12 hours.", "Adjust it in Settings.")
        }
        for (component, path) in [("Install location", settings.installLocation), ("State directory", settings.stateDirectory), ("swiftDialog path", settings.swiftDialogPath)] {
            if let issue = FieldValidator.absolutePathIssue(path) {
                add(.error, .project, component, issue, "Enter an absolute device path in Settings.")
            }
        }
        if !FieldValidator.isValidVersion(settings.swiftDialogMinimumVersion) {
            add(.error, .project, "swiftDialog minimum version", "\"\(settings.swiftDialogMinimumVersion)\" is not a valid version.", "Use a version such as 2.5.0.")
        }

        let flag = settings.onboardingFlagPath.trimmingCharacters(in: .whitespaces)
        if flag.isEmpty {
            add(.information, .project, "Onboarding flag", "No onboarding flag is set, so the package can enroll the same Mac again.",
                "Set the onboarding flag in Settings to block reinstalls.")
        } else if let issue = FieldValidator.absolutePathIssue(flag) {
            add(.error, .project, "Onboarding flag", issue, "Enter an absolute path in Settings.")
        } else {
            for (label, directory) in [("install location", settings.installLocation), ("state directory", settings.stateDirectory)] {
                let base = FrameworkGenerator.trimmedDirectory(directory)
                if flag == base || flag.hasPrefix(base + "/") {
                    add(.error, .project, "Onboarding flag", "The onboarding flag is inside the \(label), which uninstall.sh removes.",
                        "Keep the flag outside the framework, for example \(ProjectSettings.defaultOnboardingFlagPath).")
                }
            }
        }

        if !ProjectSettings.enrollmentWindowRange.contains(settings.enrollmentWindowHours) {
            add(.error, .project, "Enrollment window", "The enrollment window must be 1 to 720 hours.", "Adjust it in Settings.")
        }

        let output = settings.effectiveOutputDirectoryPath
        if !environment.isWritableDirectory(output) {
            add(.error, .project, "Output folder", "The output folder is unavailable or not writable: \(output)", "Choose another folder in Overview.")
        }
    }

    // MARK: Branding

    private static func checkBranding(_ project: EnrollmentProject, assets: [String: Data], environment: ValidationEnvironment, add: Add) {
        let branding = project.branding
        if branding.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, .branding, "Window title", "The window title is empty.", "Enter a title in Branding.")
        }
        if branding.buttonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, .branding, "Completion button", "The completion button text is empty.", "Enter button text in Branding.")
        }
        if !branding.accentColor.isValid {
            add(.error, .branding, "Accent color", "\"\(branding.accentColor.hex)\" is not a valid color.", "Choose a color in Branding.")
        }
        for (component, path) in [("Company logo", branding.logoPath), ("Banner", branding.bannerPath), ("Overlay icon", branding.overlayIconPath)] {
            guard let path else { continue }
            if assets[path] == nil {
                add(.error, .branding, component, "The image file \(path) is missing from the project.", "Choose the image again in Branding.")
            } else if let data = assets[path], (try? AssetImporter.validateImage(data)) == nil {
                add(.error, .branding, component, "\(path) is not a valid PNG, JPEG or ICNS image.", "Choose a different image in Branding.")
            }
        }
        if branding.logoPath == nil {
            add(.information, .branding, "Company logo", "No company logo is set; the dialog shows a generic icon.", "Add a logo in Branding.")
        }
        if !environment.isKnownSymbol(branding.completionSymbol) {
            add(.warning, .branding, "Completion icon", "\"\(branding.completionSymbol)\" is not a known SF Symbol.", "Enter a valid symbol name in Branding.")
        }
        if FieldValidator.urlIssue(branding.supportURL) != nil {
            add(.warning, .branding, "Support URL", "The support URL is not a valid http or https address.", "Correct it in Branding.")
        }
        let texts = [("Window title", branding.title), ("Welcome message", branding.welcomeMessage), ("Completion message", branding.completionMessage),
                     ("Warning message", branding.warningMessage), ("Failure message", branding.failureMessage), ("Information box", branding.infoboxTemplate)]
        for (component, text) in texts {
            let unknown = PlaceholderResolver.unknownTokens(in: text)
            if !unknown.isEmpty {
                add(.warning, .branding, component, "Unrecognized placeholder \(unknown.joined(separator: ", ")) will appear literally.",
                    "Use one of the placeholders listed in Branding.")
            }
        }
    }

    // MARK: Applications

    private static func checkApplications(_ project: EnrollmentProject, assets: [String: Data], environment: ValidationEnvironment,
                                          installerPaths: Set<String>, add: Add) {
        let maximum = project.settings.maximumEnrollmentDurationSeconds
        for group in project.applicationGroups {
            if group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.error, .applications, "Group", "A group has no name.", "Rename the group in Applications.")
            }
            for application in group.applications where application.isEnabled {
                let component = application.displayName.isEmpty ? "Application \(application.taskIdentifier)" : application.displayName
                let required = group.isRequired || application.execution.isRequired

                if application.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(.error, .applications, component, "The application has no display name.", "Edit the application in Applications.")
                }
                if !application.applicationPath.hasPrefix("/") {
                    add(.error, .applications, component, "The application path is not absolute.", "Enter a full path such as /Applications/Example.app.")
                } else if !environment.fileExists(application.applicationPath) {
                    add(.warning, .applications, component, "\(application.applicationPath) does not exist on this Mac.",
                        "This is expected if the app is not installed here; confirm the path on a test device.")
                }
                if let problem = successConditionProblem(application) {
                    add(.error, .applications, component, problem, "Edit the detection settings in Applications.")
                }
                if application.icon.kind == .projectAsset && assets[application.icon.value] == nil {
                    add(.error, .applications, component, "The icon file \(application.icon.value) is missing.", "Choose the icon again or switch to the installed app icon.")
                }
                if application.installStrategy == .waitForIntune && application.execution.timeoutSeconds < 300 {
                    add(.warning, .applications, component, "A \(DurationFormatter.format(seconds: application.execution.timeoutSeconds)) timeout may be too short for an Intune installation.",
                        "Allow at least 5 minutes; large apps such as Microsoft 365 often need 30 minutes or more.")
                } else if let catalogID = application.catalogID, let entry = ApplicationCatalog.entry(id: catalogID),
                          application.execution.timeoutSeconds < entry.defaultTimeoutSeconds / 2 {
                    add(.warning, .applications, component, "The timeout is less than half the suggested \(DurationFormatter.format(seconds: entry.defaultTimeoutSeconds)).",
                        "Consider a longer timeout for this app.")
                }
                if application.execution.timeoutSeconds > maximum {
                    add(.warning, .applications, component, "The timeout is longer than the maximum enrollment duration.", "Shorten the timeout or raise the maximum duration in Settings.")
                }
                if let problem = installerProblem(application, installerPaths: installerPaths) {
                    add(required ? .error : .warning, .applications, component, problem,
                        "Choose a package in the application editor, or switch the strategy to Wait for Intune.")
                } else if application.installStrategy != .bundledInstaller, let installer = application.installer {
                    add(.information, .applications, component, "\(installer.originalFilename) is attached but not used by \(application.installStrategy.title).",
                        "Switch to Run bundled installer, or remove the package in the application editor.")
                }
                if application.installStrategy == .customScript {
                    if let linked = application.customScriptTaskIdentifier, !linked.isEmpty {
                        if !project.scripts.contains(where: { $0.taskIdentifier == linked }) {
                            add(.error, .applications, component, "The linked script \(linked) is not in the project.",
                                "Choose another script in the application editor, or import it again in Scripts.")
                        }
                    } else {
                        add(required ? .warning : .information, .applications, component,
                            "Run custom script has no script selected, so the app is only detected, like Wait for Intune.",
                            "Choose a script in the application editor, or switch to Wait for Intune.")
                    }
                }
                if application.execution.context == .user {
                    add(.information, .applications, component, "Runs in the console user's context and waits for a logged-in user.",
                        "No action needed unless the app must be detected before login.")
                }
            }
        }
    }

    /// Why the bundled-installer strategy cannot work for this application, or nil.
    static func installerProblem(_ application: ApplicationItem, installerPaths: Set<String>) -> String? {
        guard application.installStrategy == .bundledInstaller else { return nil }
        guard let installer = application.installer else {
            return "Run bundled installer is selected but no installer package is attached."
        }
        guard installerPaths.contains(installer.relativePath) else {
            return "The installer package \(installer.relativePath) is missing from the project."
        }
        return nil
    }

    static func successConditionProblem(_ application: ApplicationItem) -> String? {
        switch application.detection.method {
        case .applicationPath:
            return application.applicationPath.hasPrefix("/") ? nil : "Path detection needs an absolute application path."
        case .bundleIdentifier:
            return FieldValidator.isValidReverseDNS(application.bundleIdentifier) ? nil : "Bundle identifier detection needs a valid bundle identifier."
        case .processRunning:
            return application.processName.trimmingCharacters(in: .whitespaces).isEmpty ? "Process detection needs a process name." : nil
        case .packageReceipt, .customCommand:
            return application.detection.value.trimmingCharacters(in: .whitespaces).isEmpty ? "The detection method has no value, so the task can never succeed." : nil
        }
    }

    // MARK: Scripts

    private static func checkScripts(_ project: EnrollmentProject, assets: [String: Data], environment: ValidationEnvironment, add: Add) {
        let maximum = project.settings.maximumEnrollmentDurationSeconds
        for script in project.scripts {
            let component = "Script \(script.displayName)"
            guard !script.relativePath.isEmpty, let data = assets[script.relativePath] else {
                add(.error, .scripts, component, "The script file \(script.relativePath.isEmpty ? "(none)" : script.relativePath) is missing from the project.",
                    "Replace the file or remove the script in Scripts.")
                continue
            }
            if Hashing.sha256Hex(data) != script.sha256 {
                add(.error, .scripts, component, "The file changed outside the app since it was imported (SHA-256 mismatch).",
                    "Review the file, then choose Accept Current File in Scripts.")
            }
            if script.successExitCodes.isEmpty {
                add(.error, .scripts, component, "No success exit codes are defined, so the script can never succeed.", "Enter at least one exit code, usually 0.")
            } else if script.successExitCodes.contains(where: { !(0...255).contains($0) }) {
                add(.error, .scripts, component, "Exit codes must be between 0 and 255.", "Correct the success exit codes in Scripts.")
            }
            if script.execution.timeoutSeconds > maximum {
                add(.warning, .scripts, component, "The timeout is longer than the maximum enrollment duration.", "Shorten the timeout or raise the maximum duration in Settings.")
            }
            if script.execution.context == .user {
                add(.information, .scripts, component, "Runs as the console user, so it waits for a logged-in GUI session.", "No action needed for user settings such as the Dock.")
            }

            let inspection = ScriptInspectionCache.shared.inspection(for: data)
            for finding in inspection.findings {
                let location = finding.line > 0 ? "Line \(finding.line): " : ""
                let remediation: String
                if finding.rule.hasPrefix("interpreter-") || finding.rule.hasPrefix("file-") {
                    remediation = "Fix the file, then use Replace File in Scripts."
                } else if finding.rule.hasPrefix("bash") {
                    remediation = "Rewrite the construct for Bash 3.2, or run ShellCheck for details."
                } else {
                    remediation = "Review the line. These checks are heuristic and do not replace ShellCheck."
                }
                add(finding.severity, .scripts, component, location + finding.message, remediation)
            }
        }
    }

    // MARK: System tasks

    private static func checkSystemTasks(_ project: EnrollmentProject, add: Add) {
        for task in project.systemTasks {
            let component = task.displayName.isEmpty ? task.taskIdentifier : task.displayName
            if task.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                add(.error, .execution, component, "The system task has no name.", "Edit it in Execution.")
            }
            switch task.type {
            case .waitCondition, .configurationValidation:
                if (task.validation?.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    add(.error, .execution, component, "No validation command is defined, so the task can never succeed.", "Enter a command in Execution.")
                }
            case .intuneSync, .finalValidation, .applicationDetection, .packageInstallation, .shellScript:
                break
            }
        }
        if !project.systemTasks.contains(where: { $0.type == .finalValidation }) {
            add(.information, .execution, "Final validation", "There is no final validation task.", "Add one in Execution to confirm readiness after all required tasks.")
        }
    }

    // MARK: Dependencies

    private static func checkDependencies(_ analysis: DependencyAnalysis, name: (String) -> String, add: Add) {
        for issue in analysis.issues {
            switch issue {
            case .emptyIdentifier(let displayName):
                add(.error, .execution, displayName, "The task has an empty identifier.", "Remove and re-add the item.")
            case .duplicateIdentifier(let id):
                add(.error, .execution, id, "More than one task uses the identifier \(id).", "Remove the duplicate or edit project.json so each identifier is unique.")
            case .selfDependency(let id):
                add(.error, .execution, name(id), "The task depends on itself.", "Remove the dependency in Execution.")
            case .missingDependency(let task, let dependency):
                add(.error, .execution, name(task), "Depends on \(dependency), which does not exist.", "Remove the dependency in Execution.")
            case .disabledDependency(let task, let dependency):
                add(.error, .execution, name(task), "Depends on \(name(dependency)), which is disabled.", "Enable that task or remove the dependency.")
            case .cycle(let ids):
                add(.error, .execution, "Dependency cycle", "Circular dependency: \((ids + [ids.first ?? ""]).joined(separator: " → ")).", "Remove one of the dependencies in the loop.")
            case .orderConflict(let task, let dependency):
                add(.error, .execution, name(task), "Runs before its dependency \(name(dependency)) by execution order.",
                    "Give the dependency a lower execution order than the task.")
            case .parallelGroupDependency(let task, let dependency, let group):
                add(.warning, .execution, name(task), "Shares parallel group \"\(group)\" with its dependency \(name(dependency)), so they will run one after the other.",
                    "Move one of them to another parallel group.")
            }
        }
    }

    // MARK: Completion button

    private static func checkUnlock(_ project: EnrollmentProject, plan: [PlannedTask], analysis: DependencyAnalysis,
                                    assets: [String: Data], installerPaths: Set<String>, name: (String) -> String, add: Add) {
        let required = plan.filter { $0.isEnabled && $0.isRequired }
        if required.isEmpty {
            add(.information, .execution, "Completion button", "No task is required, so the completion button is available immediately.",
                "Mark at least one task as required if users should wait.")
            return
        }
        if plan.filter({ $0.isEnabled && $0.execution.isVisible }).isEmpty {
            add(.information, .execution, "Enrollment list", "No task is visible; the dialog list is empty.", "Make at least one task visible.")
        }
        guard project.settings.lockCompletionButtonUntilRequiredComplete else { return }

        for task in required {
            var reason: String?
            if analysis.blockedTaskIDs.contains(task.taskIdentifier) {
                reason = "it depends on something that can never complete"
            } else if case .application(let id) = task.source, let application = project.application(id: id), successConditionProblem(application) != nil {
                reason = "it has no usable success condition"
            } else if case .application(let id) = task.source, let application = project.application(id: id),
                      installerProblem(application, installerPaths: installerPaths) != nil {
                reason = "its installer package is missing"
            } else if case .script(let id) = task.source, let script = project.script(id: id),
                      script.successExitCodes.isEmpty || assets[script.relativePath] == nil {
                reason = "it has no success exit code or its file is missing"
            } else if case .system(let id) = task.source, let system = project.systemTask(id: id),
                      system.type == .waitCondition || system.type == .configurationValidation,
                      (system.validation?.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                reason = "it has no validation command"
            }
            if let reason {
                add(.error, .execution, "Completion button", "The completion button can never unlock because the required task \(name(task.taskIdentifier)) can never complete: \(reason).",
                    "Fix that task, make it optional, or turn off the button lock in Settings.")
            }
        }
    }

    // MARK: Environment

    private static func checkEnvironment(_ project: EnrollmentProject, assets: [String: Data], environment: ValidationEnvironment, add: Add) {
        let shellCheckable = project.scripts.contains { script in
            guard let data = assets[script.relativePath] else { return false }
            let shell = ScriptInspectionCache.shared.inspection(for: data).shell
            return shell == .bash || shell == .posixSh
        }
        if shellCheckable && environment.shellCheckPath == nil {
            add(.warning, .environment, "ShellCheck", "ShellCheck is not installed, so only the built-in heuristic script checks ran.",
                "Optionally install ShellCheck for deeper analysis. The app works without it.")
        }
        if !environment.fileExists(project.settings.swiftDialogPath) {
            add(.warning, .environment, "swiftDialog", "swiftDialog is not installed at \(project.settings.swiftDialogPath) on this Mac, so live preview will be unavailable.",
                "Install swiftDialog on this Mac to use live preview. Devices need it regardless; deploy it with Intune.")
        }
    }
}
