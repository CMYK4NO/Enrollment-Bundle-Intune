import XCTest
@testable import EnrollmentBundleStudio

final class FrameworkGeneratorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func generate() throws -> (EnrollmentProjectDocument, GeneratedFramework) {
        let document = try TestSupport.makeGeneratorProject(packageURL: try TestSupport.makeFakePackage(in: directory))
        let framework = try FrameworkGenerator.generate(
            project: document.project,
            assets: document.assets,
            installerSources: document.installerSources,
            now: Date(timeIntervalSince1970: 1_794_000_000)
        )
        return (document, framework)
    }

    private func taskFiles(_ framework: GeneratedFramework) -> [GeneratedFile] {
        framework.files.filter { $0.path.hasPrefix("framework/tasks/") }
    }

    func testLayout() throws {
        let (_, framework) = try generate()
        let paths = Set(framework.allPaths)
        for expected in [
            "framework/enrollment.sh", "framework/uninstall.sh", "framework/VERSION",
            "framework/config/enrollment.conf", "framework/config/dialog.json", "framework/config/tasks.json",
            "framework/lib/common.sh", "framework/lib/task-runner.sh", "framework/lib/dialog.sh",
            "framework/icons/branding-CompanyLogo.png", "framework/scripts/CheckExample.sh",
            "framework/installers/Example-Tool.pkg", "launchd/com.contoso.enrollment.plist",
            "package-scripts/preinstall", "package-scripts/postinstall", "README.txt"
        ] {
            XCTAssertTrue(paths.contains(expected), "Missing \(expected)")
        }
        XCTAssertEqual(framework.rootName, "Enrollment-Bundle-1.0.0-framework")
    }

    func testExecutableBits() throws {
        let (_, framework) = try generate()
        let executables = Set(framework.files.filter { $0.isExecutable }.map { $0.path })
        XCTAssertEqual(executables, ["framework/enrollment.sh", "framework/uninstall.sh", "framework/scripts/CheckExample.sh",
                                     "package-scripts/preinstall", "package-scripts/postinstall"])
    }

    func testTaskFilesAreDataOnlyAndOrdered() throws {
        let (document, framework) = try generate()
        let files = taskFiles(framework)
        XCTAssertEqual(files.count, framework.taskCount)
        XCTAssertEqual(files.count, TaskPlanner.plan(document.project).filter { $0.isEnabled }.count)
        for file in files {
            let text = String(decoding: file.contents, as: UTF8.self)
            XCTAssertTrue(text.hasPrefix("#!/bin/bash\n"), file.path)
            let values = try ShellLiteralReader.assignments(in: text)
            XCTAssertNotNil(values["TASK_ID"], file.path)
            XCTAssertNotNil(values["TASK_TYPE"], file.path)
            XCTAssertTrue(file.path.hasSuffix("-\(values["TASK_ID"] ?? "").sh"), file.path)
        }
        let names = files.map { ($0.path as NSString).lastPathComponent }
        XCTAssertEqual(names, names.sorted())
        XCTAssertTrue(names.first?.hasPrefix("010-") ?? false)
        XCTAssertTrue(names.last?.hasSuffix("-system.final-validation.sh") ?? false, "Final validation runs last")
    }

    private func task(_ framework: GeneratedFramework, _ id: String) throws -> [String: String] {
        let file = try XCTUnwrap(taskFiles(framework).first { $0.path.hasSuffix("-\(id).sh") }, id)
        return try ShellLiteralReader.assignments(in: String(decoding: file.contents, as: UTF8.self))
    }

    func testTaskValues() throws {
        let (_, framework) = try generate()
        let portal = try task(framework, "app.microsoft-company-portal")
        XCTAssertEqual(portal["TASK_TYPE"], "applicationDetection")
        XCTAssertEqual(portal["TASK_STRATEGY"], "waitForIntune")
        XCTAssertEqual(portal["TASK_REQUIRED"], "1")
        XCTAssertEqual(portal["TASK_APP_PATH"], "/Applications/Company Portal.app")
        XCTAssertEqual(portal["TASK_DETECTION"], "bundleIdentifier")
        XCTAssertEqual(portal["TASK_LIST_INDEX"], "0")

        let tool = try task(framework, "app.example-tool")
        XCTAssertEqual(tool["TASK_TYPE"], "packageInstallation")
        XCTAssertEqual(tool["TASK_INSTALLER"], "installers/Example-Tool.pkg")
        XCTAssertEqual(tool["TASK_NAME"], "Tool $(touch /tmp/pwned) 'quoted'", "Quoted literally, never expanded")

        let script = try task(framework, "script.checkexample")
        XCTAssertEqual(script["TASK_TYPE"], "shellScript")
        XCTAssertEqual(script["TASK_SCRIPT"], "scripts/CheckExample.sh")
        XCTAssertEqual(script["TASK_SUCCESS_CODES"], "0")

        let wait = try task(framework, "system.wait-condition")
        XCTAssertEqual(wait["TASK_TYPE"], "waitCondition")
        XCTAssertEqual(wait["TASK_VALIDATION_VALUE"], "/usr/bin/test -f \"/var/db/.AppleSetupDone\"")
        XCTAssertNotEqual(wait["TASK_LIST_INDEX"], "-1", "New system tasks are visible in the list by default")
        XCTAssertEqual(wait["TASK_VISIBLE"], "1")
    }

    func testSummaryGroupAndParallelBatch() throws {
        let (_, framework) = try generate()
        let word = try task(framework, "app.microsoft-365-and-office")
        let excel = try task(framework, "app.m365-companion")
        XCTAssertEqual(word["TASK_LIST_SUMMARY"], "1")
        XCTAssertEqual(word["TASK_LIST_INDEX"], excel["TASK_LIST_INDEX"], "One summary row")
        XCTAssertEqual(word["TASK_BATCH"], excel["TASK_BATCH"], "Same parallel group, no dependency: one batch")
        XCTAssertEqual(word["TASK_PARALLEL_GROUP"], "m365")
    }

    func testFinalValidationDependsOnRequiredTasks() throws {
        let (_, framework) = try generate()
        let final = try task(framework, "system.final-validation")
        let dependencies = Set((final["TASK_DEPENDS"] ?? "").split(separator: " ").map(String.init))
        XCTAssertTrue(dependencies.contains("app.microsoft-company-portal"))
        XCTAssertFalse(dependencies.contains("app.microsoft-365-and-office"), "Optional apps are not prerequisites")
        XCTAssertEqual(final["TASK_REQUIRED"], "1")
    }

    func testConfigurationFile() throws {
        let (document, framework) = try generate()
        let text = try XCTUnwrap(framework.text(at: "framework/config/enrollment.conf"))
        let values = try ShellLiteralReader.assignments(in: text)
        XCTAssertEqual(values["appname"], "onBoarding")
        XCTAssertEqual(values["organization_name"], "Contoso & \"Partners\" it's")
        XCTAssertEqual(values["install_dir"], "/Library/Application Support/Contoso/Enrollment")
        XCTAssertEqual(values["project_id"], document.project.id.uuidString)
        XCTAssertEqual(values["bundle_version"], document.project.projectVersion)
        XCTAssertEqual(values["lock_button"], "1")
        XCTAssertEqual(values["dialog_min_version"], "2.5.0")
        XCTAssertEqual(values["completion_icon"], "SF=checkmark.seal.fill")
        XCTAssertEqual(values["launchd_label"], "com.contoso.enrollment")
    }

    func testDialogConfiguration() throws {
        let (document, framework) = try generate()
        let data = try XCTUnwrap(framework.file(at: "framework/config/dialog.json")?.contents)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Welcome to {companyname}", "Tokens normalized for the device")
        XCTAssertEqual(json["icon"] as? String, "__INSTALL_DIR__/icons/branding-CompanyLogo.png",
                       "Resolved on the device to the folder the framework runs from")
        XCTAssertTrue(FrameworkTemplates.libraryDialog.contains(#"replace_all "$json" "__INSTALL_DIR__""#))
        let list = try XCTUnwrap(json["listitem"] as? [[String: Any]])
        let state = PreviewBuilder.makeState(project: document.project, scenario: .initial, overrides: [:])
        XCTAssertEqual(list.count, state.displayItems.count)
        XCTAssertEqual(list.first?["icon"] as? String, "/Applications/Company Portal.app")
        XCTAssertEqual(json["progress"] as? String, String(framework.taskCount))
    }

    func testLaunchDaemonAndPackageScripts() throws {
        let (_, framework) = try generate()
        let plistData = try XCTUnwrap(framework.file(at: "launchd/com.contoso.enrollment.plist")?.contents)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, "com.contoso.enrollment")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/bin/bash", "/Library/Application Support/Contoso/Enrollment/enrollment.sh"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)

        let postinstall = try XCTUnwrap(framework.text(at: "package-scripts/postinstall"))
        XCTAssertFalse(postinstall.contains("__"), "All tokens replaced")
        XCTAssertTrue(postinstall.contains("label='com.contoso.enrollment'"))
        XCTAssertTrue(postinstall.contains("install_dir='/Library/Application Support/Contoso/Enrollment'"))
        XCTAssertFalse(try XCTUnwrap(framework.text(at: "package-scripts/preinstall")).contains("__"))
    }

    func testEveryShellFilePassesInspection() throws {
        let (_, framework) = try generate()
        let shellFiles = framework.files.filter { file in
            file.path.hasSuffix(".sh") || file.path.hasPrefix("package-scripts/")
        }
        for file in shellFiles where !file.path.hasPrefix("framework/scripts/") {
            var text = String(decoding: file.contents, as: UTF8.self)
            if !text.hasPrefix("#!") { text = "#!/bin/bash\n" + text }
            let findings = ScriptInspector.inspect(Data(text.utf8)).findings
            XCTAssertFalse(findings.contains { $0.severity == .error || $0.rule.hasPrefix("bash") }, "\(file.path): \(findings)")
        }
    }

    func testGeneratedShellParsesWithBash() async throws {
        let bash = "/bin/bash"
        guard FileManager.default.isExecutableFile(atPath: bash) else { throw XCTSkip("bash not available") }
        let (_, framework) = try generate()
        let runner = ProcessCommandRunner(allowedExecutables: [bash])
        for file in framework.files where file.path.hasSuffix(".sh") || file.path.hasPrefix("package-scripts/") {
            // -n parses only; nothing is executed.
            let result = try await runner.run(executable: URL(fileURLWithPath: bash), arguments: ["-n"], standardInput: file.contents, timeout: 10)
            XCTAssertEqual(result.exitCode, 0, "\(file.path): \(result.standardErrorText)")
        }
    }

    func testMissingFilesAreReported() throws {
        var (document, _) = try generate()
        document.project.branding.logoPath = "Branding/Missing.png"
        XCTAssertThrowsError(try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)) { error in
            XCTAssertEqual(error as? FrameworkGeneratorError, .missingAsset("Branding/Missing.png"))
        }
        let (fresh, _) = try generate()
        XCTAssertThrowsError(try FrameworkGenerator.generate(project: fresh.project, assets: fresh.assets, installerSources: [:])) { error in
            XCTAssertEqual(error as? FrameworkGeneratorError, .missingInstaller("Installers/Example-Tool.pkg"))
        }
    }

    func testTaskIdentifierValidation() {
        XCTAssertTrue(FrameworkGenerator.isValidTaskIdentifier("app.microsoft-edge"))
        XCTAssertTrue(FrameworkGenerator.isValidTaskIdentifier("system.final-validation"))
        XCTAssertFalse(FrameworkGenerator.isValidTaskIdentifier("App.Edge"))
        XCTAssertFalse(FrameworkGenerator.isValidTaskIdentifier("app/../x"))
        XCTAssertFalse(FrameworkGenerator.isValidTaskIdentifier("-app"))
        XCTAssertFalse(FrameworkGenerator.isValidTaskIdentifier("app;rm"))
        XCTAssertFalse(FrameworkGenerator.isValidTaskIdentifier(""))
    }

    func testIconPaths() {
        XCTAssertEqual(FrameworkGenerator.iconRelativePath(for: "Branding/Banner.png"), "icons/branding-Banner.png")
        XCTAssertEqual(FrameworkGenerator.iconRelativePath(for: "Icons/Edge.png"), "icons/Edge.png")
        XCTAssertEqual(FrameworkGenerator.trimmedDirectory("/Library/X//"), "/Library/X")
    }
}

final class FrameworkExporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFramework() throws -> GeneratedFramework {
        let document = try TestSupport.makeGeneratorProject(packageURL: try TestSupport.makeFakePackage(in: directory))
        return try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)
    }

    private func permissions(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func testWritesFilesWithPermissions() throws {
        let framework = try makeFramework()
        let output = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let destination = FrameworkExporter.destination(for: framework, in: output)
        let result = try FrameworkExporter.write(framework, to: destination, replacingExisting: false)

        XCTAssertEqual(result.fileCount, framework.allPaths.count)
        XCTAssertEqual(try permissions(destination.appendingPathComponent("framework/enrollment.sh")), 0o755)
        XCTAssertEqual(try permissions(destination.appendingPathComponent("framework/scripts/CheckExample.sh")), 0o755)
        XCTAssertEqual(try permissions(destination.appendingPathComponent("framework/config/enrollment.conf")), 0o644)
        XCTAssertEqual(try permissions(destination.appendingPathComponent("framework/installers/Example-Tool.pkg")), 0o644)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.contains(".partial-") }
        XCTAssertTrue(leftovers.isEmpty, "No staging folder remains")
    }

    func testReplacingNeedsConfirmation() throws {
        let framework = try makeFramework()
        let destination = directory.appendingPathComponent(framework.rootName, isDirectory: true)
        _ = try FrameworkExporter.write(framework, to: destination, replacingExisting: false)
        XCTAssertThrowsError(try FrameworkExporter.write(framework, to: destination, replacingExisting: false)) { error in
            XCTAssertEqual(error as? FrameworkExportError, .destinationExists(destination.path))
        }
        var removed: [URL] = []
        _ = try FrameworkExporter.write(framework, to: destination, replacingExisting: true, removeExisting: { url in
            removed.append(url)
            try FileManager.default.removeItem(at: url)
        })
        XCTAssertEqual(removed, [destination])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("framework/enrollment.sh").path))
    }

    func testInstallerHashIsVerifiedAfterCopy() throws {
        let packageURL = try TestSupport.makeFakePackage(in: directory, name: "Changing.pkg")
        let document = try TestSupport.makeGeneratorProject(packageURL: packageURL)
        let framework = try FrameworkGenerator.generate(project: document.project, assets: document.assets, installerSources: document.installerSources)
        try Data("xar!tampered after attaching".utf8).write(to: packageURL)
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        XCTAssertThrowsError(try FrameworkExporter.write(framework, to: destination, replacingExisting: false)) { error in
            XCTAssertEqual(error as? FrameworkExportError, .installerHashMismatch("framework/installers/Changing.pkg"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "A failed export leaves nothing behind")
    }
}

final class SimulationTimelineTests: XCTestCase {
    private func project() -> EnrollmentProject {
        var project = TestSupport.makeProject()
        let entries = ["microsoft-edge", "google-chrome"].compactMap(ApplicationCatalog.entry(id:))
        project.addCatalogEntries(entries, target: .categoryGroups)
        return project
    }

    func testTimelineAdvancesEveryTaskAndEndsAtScenario() {
        let project = project()
        let steps = SimulationTimeline.make(project: project, scenario: .completeWithWarnings, stepDuration: 0.1)
        let regular = TaskPlanner.plan(project).filter { $0.type != .finalValidation }.map { $0.taskIdentifier }
        XCTAssertEqual(steps.count, 1 + regular.count * 2)
        XCTAssertEqual(Set(steps.first.map { Array($0.overrides.values) } ?? []), [TaskStatus.pending])
        XCTAssertFalse(steps.contains { $0.overrides["system.final-validation"] != nil }, "Final validation is derived, not simulated")

        let expected = PreviewBuilder.makeState(project: project, scenario: .completeWithWarnings, overrides: [:])
        for item in expected.evaluationItems where regular.contains(item.id) {
            XCTAssertEqual(steps.last?.overrides[item.id], item.status, item.id)
        }
        let finalState = PreviewBuilder.makeState(project: project, scenario: .initial, overrides: steps.last?.overrides ?? [:])
        XCTAssertEqual(finalState.outcome, .successWithWarnings)
    }

    func testSimulationOfSnapshotScenariosRunsToCompletion() {
        let project = project()
        for scenario in [PreviewScenario.initial, .inProgress] {
            let steps = SimulationTimeline.make(project: project, scenario: scenario, stepDuration: 0.1)
            let finalState = PreviewBuilder.makeState(project: project, scenario: scenario, overrides: steps.last?.overrides ?? [:])
            XCTAssertEqual(finalState.outcome, .success, scenario.title)
            XCTAssertTrue(finalState.isButtonEnabled, scenario.title)
            XCTAssertEqual(finalState.finishedCount, finalState.totalCount, scenario.title)
        }
    }

    func testWaitingVersusRunning() throws {
        let document = try TestSupport.makeProjectWithScript()
        let steps = SimulationTimeline.make(project: document.project, scenario: .allComplete)
        XCTAssertTrue(steps.contains { $0.overrides["app.microsoft-company-portal"] == .waiting }, "Intune apps wait")
        XCTAssertTrue(steps.contains { $0.overrides["script.checkexample"] == .running }, "Scripts run")
    }
}
