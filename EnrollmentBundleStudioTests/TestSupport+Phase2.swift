import Foundation
@testable import EnrollmentBundleStudio

extension TestSupport {
    static let cleanScript = """
    #!/bin/bash
    set -u
    PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    if [ -d "/Applications/Example.app" ]; then
        echo "present"
        exit 0
    fi
    exit 1

    """

    /// A project with one imported script and its file.
    static func makeProjectWithScript(_ source: String = cleanScript, name: String = "CheckExample.sh") throws -> EnrollmentProjectDocument {
        var document = EnrollmentProjectDocument(project: makeProject())
        let data = Data(source.utf8)
        let made = try ScriptImporter.makeScriptItem(
            data: data,
            originalFilename: name,
            wasExecutable: true,
            project: document.project,
            existingAssetPaths: Set(document.assets.keys),
            now: Date(timeIntervalSince1970: 1_794_000_000)
        )
        try document.addImportedScript(made.item, data: data)
        return document
    }

    static func plannedTask(
        _ id: String,
        order: Int = 100,
        dependencies: [String] = [],
        enabled: Bool = true,
        required: Bool = true,
        group: String = "",
        type: TaskType = .shellScript
    ) -> PlannedTask {
        var options = TaskExecutionOptions()
        options.executionOrder = order
        options.dependencies = dependencies
        options.parallelGroup = group
        options.isRequired = required
        return PlannedTask(
            taskIdentifier: id,
            displayName: id,
            type: type,
            source: .script(UUID()),
            isEnabled: enabled,
            isRequired: required,
            execution: options,
            implicitDependencies: []
        )
    }
}

/// Records calls and returns a canned result. No process is ever started.
final class MockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let standardInput: Data?
    }

    var result: CommandResult
    /// Optional per-call behavior; receives the executable path and arguments.
    var handler: ((String, [String]) throws -> CommandResult)?
    private(set) var calls: [Call] = []

    init(result: CommandResult = CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data(), timedOut: false),
         handler: ((String, [String]) throws -> CommandResult)? = nil) {
        self.result = result
        self.handler = handler
    }

    func run(executable: URL, arguments: [String], standardInput: Data?, timeout: TimeInterval) async throws -> CommandResult {
        calls.append(Call(executable: executable.path, arguments: arguments, standardInput: standardInput))
        if let handler {
            return try handler(executable.path, arguments)
        }
        return result
    }
}
