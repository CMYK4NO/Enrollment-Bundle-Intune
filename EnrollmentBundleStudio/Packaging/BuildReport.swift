import Foundation

/// Plain-text build report written next to every package. Contains only build metadata: no secrets,
/// no script contents and no script output.
enum BuildReport {
    static func text(
        project: EnrollmentProject,
        verification: PackageVerification,
        validation: ValidationReport,
        framework: GeneratedFramework,
        builtAt: Date
    ) -> String {
        let settings = project.settings
        let plan = TaskPlanner.plan(project).filter { $0.isEnabled }
        let required = plan.filter { $0.isRequired }
        let optional = plan.filter { !$0.isRequired }
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        func section(_ title: String) {
            lines.append("")
            lines.append(title)
            lines.append(String(repeating: "-", count: title.count))
        }
        func field(_ name: String, _ value: String) {
            lines.append("\(name.padding(toLength: 26, withPad: " ", startingAt: 0))\(value)")
        }

        lines.append("Enrollment Bundle Studio build report")
        lines.append(String(repeating: "=", count: 37))
        section("Build")
        field("Project name", settings.projectName)
        field("Project ID", project.id.uuidString)
        field("Organization", settings.organizationName)
        field("Build date", formatter.string(from: builtAt))
        field("Application version", AppInfo.version)
        field("Enrollment bundle version", settings.packageVersion)
        field("Package version", settings.packageVersion)
        field("Package identifier", settings.packageIdentifier)
        field("Install location", FrameworkGenerator.trimmedDirectory(settings.installLocation))
        field("LaunchDaemon", "/Library/LaunchDaemons/\(settings.bundleIdentifier).plist")
        if settings.onboardingFlagPath.isEmpty {
            field("Onboarding guard", "Off")
        } else {
            field("Onboarding flag", settings.onboardingFlagPath)
            field("Enrollment window", "\(settings.enrollmentWindowHours) hours since MDM enrollment")
        }

        section("Package")
        field("Output path", verification.packagePath)
        field("Size", "\(ByteCountFormatter.string(fromByteCount: verification.sizeBytes, countStyle: .file)) (\(verification.sizeBytes) bytes)")
        field("SHA-256", verification.sha256)
        field("Format", "Flat component package (pkgbuild)")
        field("Signature", verification.signatureStatus)
        field("Payload files", "\(verification.payloadFileCount)")
        field("Verification", verification.passed ? "Passed" : "FAILED")
        for check in verification.checks {
            lines.append("  [\(check.passed ? "ok" : "!!")] \(check.title): \(check.detail)")
        }

        section("Validation")
        field("Errors", "\(validation.errorCount)")
        field("Warnings", "\(validation.warningCount)")
        field("Information", "\(validation.informationCount)")
        for issue in validation.issues where issue.severity != .information {
            lines.append("  [\(issue.severity.title)] \(issue.component): \(issue.message)")
        }

        section("Applications")
        let applications = project.applicationGroups.flatMap { group in
            group.applications.filter { $0.isEnabled }.map { (group, $0) }
        }
        if applications.isEmpty { lines.append("  None") }
        for (group, application) in applications {
            let requiredText = (group.isRequired || application.execution.isRequired) ? "required" : "optional"
            var detail = "\(application.installStrategy.title), \(requiredText), group \(group.name)"
            if let installer = application.installer, application.installStrategy == .bundledInstaller {
                detail += ", package \(installer.originalFilename) (SHA-256 \(installer.sha256))"
            }
            lines.append("  \(application.displayName) [\(application.taskIdentifier)]: \(detail)")
        }

        section("Scripts")
        if project.scripts.isEmpty { lines.append("  None") }
        for script in project.scripts {
            let requiredText = script.execution.isRequired ? "required" : "optional"
            lines.append("  \(script.displayName) [\(script.taskIdentifier)]: \(script.relativePath), \(script.interpreter), runs as \(script.execution.context.rawValue), \(requiredText), SHA-256 \(script.sha256)")
        }

        section("Tasks")
        lines.append("  Required (\(required.count)): " + (required.isEmpty ? "none" : required.map { $0.taskIdentifier }.joined(separator: ", ")))
        lines.append("  Optional (\(optional.count)): " + (optional.isEmpty ? "none" : optional.map { $0.taskIdentifier }.joined(separator: ", ")))

        section("Generated file inventory")
        for path in framework.allPaths {
            lines.append("  \(path)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
