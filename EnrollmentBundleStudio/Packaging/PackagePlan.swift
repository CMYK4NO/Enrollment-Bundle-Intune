import Foundation

/// Where a package build puts things, and the exact pkgbuild invocation. Pure, so tests check every argument.
struct PackagePlan: Equatable {
    static let pkgbuild = "/usr/bin/pkgbuild"
    static let pkgutil = "/usr/sbin/pkgutil"
    static let allowedTools: Set<String> = [pkgbuild, pkgutil]

    let packageIdentifier: String
    let packageVersion: String
    let installLocation: String
    let launchDaemonLabel: String
    /// Final package location in the output folder.
    let packageURL: URL
    /// The build report written next to the package.
    let reportURL: URL

    init(project: EnrollmentProject, outputDirectory: URL) {
        let settings = project.settings
        packageIdentifier = settings.packageIdentifier
        packageVersion = settings.packageVersion
        installLocation = FrameworkGenerator.trimmedDirectory(settings.installLocation)
        launchDaemonLabel = settings.bundleIdentifier
        let baseName = "\(FilenameSanitizer.sanitize(settings.packageDisplayName, fallback: "EnrollmentBundle"))-\(settings.packageVersion)"
        packageURL = outputDirectory.appendingPathComponent("\(baseName).pkg")
        reportURL = outputDirectory.appendingPathComponent("\(baseName)-build-report.txt")
    }

    /// Payload folder inside the staging area: mirrors the target volume, so the install location is the
    /// install location without its leading slash.
    func payloadFrameworkDirectory(in payload: URL) -> URL {
        payload.appendingPathComponent(String(installLocation.drop { $0 == "/" }), isDirectory: true)
    }

    func payloadLaunchDaemon(in payload: URL) -> URL {
        payload.appendingPathComponent("Library/LaunchDaemons/\(launchDaemonLabel).plist")
    }

    /// pkgbuild creates a flat component package. --ownership recommended records root:wheel in the
    /// payload, so the build itself never needs administrator rights.
    func pkgbuildArguments(payload: URL, scripts: URL, output: URL) -> [String] {
        [
            "--root", payload.path,
            "--scripts", scripts.path,
            "--identifier", packageIdentifier,
            "--version", packageVersion,
            "--install-location", "/",
            "--ownership", "recommended",
            output.path
        ]
    }

    /// Payload paths the verifier expects, in pkgutil --payload-files form (./relative/path).
    var expectedPayloadPaths: [String] {
        let framework = "./" + String(installLocation.drop { $0 == "/" })
        return [
            "\(framework)/enrollment.sh",
            "\(framework)/uninstall.sh",
            "\(framework)/config/enrollment.conf",
            "\(framework)/lib/task-runner.sh",
            "./Library/LaunchDaemons/\(launchDaemonLabel).plist"
        ]
    }
}
