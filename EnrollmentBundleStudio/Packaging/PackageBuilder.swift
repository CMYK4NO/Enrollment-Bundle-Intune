import Foundation

enum PackageBuildError: LocalizedError, Equatable {
    case blockedByValidation(Int)
    case packageExists(String)
    case pkgbuildFailed(String)
    case verificationFailed([String])

    var errorDescription: String? {
        switch self {
        case .blockedByValidation(let count):
            return "\(count) validation error(s) must be fixed before building."
        case .packageExists(let path):
            return "\(path) already exists."
        case .pkgbuildFailed(let detail):
            return "pkgbuild failed: \(detail)"
        case .verificationFailed(let failures):
            return "The built package did not pass verification: \(failures.joined(separator: "; "))"
        }
    }
}

struct PackageBuildResult: Equatable {
    let packageURL: URL
    let reportURL: URL
    let verification: PackageVerification
    let record: BuildRecord
}

/// Builds an unsigned flat component package from a project, then verifies it and writes the build report.
///
/// 1. Generate the framework and write it to a staging folder (package hashes verified on copy).
/// 2. Arrange the payload (framework at the install location, LaunchDaemon in /Library/LaunchDaemons)
///    and the install scripts.
/// 3. Run /usr/bin/pkgbuild into the staging folder; no administrator rights are needed.
/// 4. Verify the package with /usr/sbin/pkgutil, then move it into the output folder (an existing package
///    is replaced only when confirmed, and goes to the Trash) and write the report next to it.
/// The staging folder is removed afterwards, also on failure.
struct PackageBuilder {
    let runner: CommandRunning
    var removeExisting: (URL) throws -> Void = FrameworkExporter.moveToTrash
    var now: () -> Date = { Date() }

    static func live() -> PackageBuilder {
        PackageBuilder(runner: ProcessCommandRunner(allowedExecutables: PackagePlan.allowedTools))
    }

    func build(
        project: EnrollmentProject,
        assets: [String: Data],
        installerSources: [String: InstallerSource],
        validation: ValidationReport,
        outputDirectory: URL,
        replaceExisting: Bool,
        progress: @escaping (String) -> Void = { _ in }
    ) async throws -> PackageBuildResult {
        guard !validation.blocksBuild else { throw PackageBuildError.blockedByValidation(validation.errorCount) }
        let fileManager = FileManager.default
        let plan = PackagePlan(project: project, outputDirectory: outputDirectory)
        if !replaceExisting && (fileManager.fileExists(atPath: plan.packageURL.path) || fileManager.fileExists(atPath: plan.reportURL.path)) {
            throw PackageBuildError.packageExists(plan.packageURL.path)
        }

        progress("Generating the framework…")
        let framework = try FrameworkGenerator.generate(project: project, assets: assets, installerSources: installerSources, now: now())

        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: outputDirectory, create: true)
        defer { try? fileManager.removeItem(at: staging) }

        let export = staging.appendingPathComponent("export", isDirectory: true)
        _ = try FrameworkExporter.write(framework, to: export, replacingExisting: false)

        progress("Arranging the payload…")
        let payload = staging.appendingPathComponent("payload", isDirectory: true)
        let scripts = staging.appendingPathComponent("scripts", isDirectory: true)
        let frameworkTarget = plan.payloadFrameworkDirectory(in: payload)
        try fileManager.createDirectory(at: frameworkTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: export.appendingPathComponent(FrameworkGenerator.frameworkDirectory), to: frameworkTarget)
        let daemonTarget = plan.payloadLaunchDaemon(in: payload)
        try fileManager.createDirectory(at: daemonTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: export.appendingPathComponent("launchd/\(plan.launchDaemonLabel).plist"), to: daemonTarget)
        try fileManager.moveItem(at: export.appendingPathComponent("package-scripts"), to: scripts)

        progress("Running pkgbuild…")
        let builtPackage = staging.appendingPathComponent("built.pkg")
        let result = try await runner.run(
            executable: URL(fileURLWithPath: PackagePlan.pkgbuild),
            arguments: plan.pkgbuildArguments(payload: payload, scripts: scripts, output: builtPackage),
            standardInput: nil,
            timeout: 900
        )
        guard result.exitCode == 0, !result.timedOut, fileManager.fileExists(atPath: builtPackage.path) else {
            let detail = result.timedOut ? "timed out" : result.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PackageBuildError.pkgbuildFailed(detail.isEmpty ? "exit code \(result.exitCode)" : detail)
        }

        progress("Verifying the package…")
        let staged = try await PackageVerifier.verify(packageURL: builtPackage, plan: plan, runner: runner)
        guard staged.passed else {
            throw PackageBuildError.verificationFailed(staged.checks.filter { !$0.passed }.map { "\($0.title): \($0.detail)" })
        }

        progress("Writing the package and report…")
        for existing in [plan.packageURL, plan.reportURL] where fileManager.fileExists(atPath: existing.path) {
            try removeExisting(existing)
        }
        try fileManager.moveItem(at: builtPackage, to: plan.packageURL)
        let verification = PackageVerification(
            packagePath: plan.packageURL.path,
            sizeBytes: staged.sizeBytes,
            sha256: staged.sha256,
            identifier: staged.identifier,
            version: staged.version,
            signatureStatus: staged.signatureStatus,
            payloadFileCount: staged.payloadFileCount,
            checks: staged.checks
        )
        let builtAt = now()
        let report = BuildReport.text(project: project, verification: verification, validation: validation, framework: framework, builtAt: builtAt)
        try Data(report.utf8).write(to: plan.reportURL, options: .atomic)

        let record = BuildRecord(
            id: UUID(),
            builtAt: ProjectCoding.wholeSeconds(builtAt),
            packagePath: plan.packageURL.path,
            reportPath: plan.reportURL.path,
            sha256: verification.sha256,
            sizeBytes: verification.sizeBytes,
            packageIdentifier: plan.packageIdentifier,
            packageVersion: plan.packageVersion,
            bundleVersion: project.settings.packageVersion,
            verificationPassed: verification.passed,
            warningCount: validation.warningCount,
            applicationVersion: AppInfo.version
        )
        return PackageBuildResult(packageURL: plan.packageURL, reportURL: plan.reportURL, verification: verification, record: record)
    }
}
