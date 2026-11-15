import Foundation

struct ShellCheckComment: Decodable, Equatable, Identifiable {
    let line: Int
    let column: Int
    let level: String
    let code: Int
    let message: String

    var id: String { "\(line):\(column):\(code)" }

    var severity: ValidationSeverity {
        switch level {
        case "error": return .error
        case "warning": return .warning
        default: return .information
        }
    }
}

enum ShellCheckError: LocalizedError, Equatable {
    case unsupportedShell
    case failed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedShell: return "ShellCheck supports bash and sh scripts, not zsh."
        case .failed(let detail): return "ShellCheck failed: \(detail)"
        case .timedOut: return "ShellCheck did not finish within 30 seconds."
        }
    }
}

/// Optional integration with a locally installed ShellCheck. The script is passed on standard input,
/// so no temporary copy is written. ShellCheck analyses the text; it does not run the script.
enum ShellCheckService {
    static let candidatePaths = ["/opt/homebrew/bin/shellcheck", "/usr/local/bin/shellcheck"]

    static func locate(isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        candidatePaths.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    static func arguments(for shell: ScriptShell) -> [String]? {
        switch shell {
        case .bash, .missing, .unsupported: return ["--format=json1", "--shell=bash", "--severity=style", "-"]
        case .posixSh: return ["--format=json1", "--shell=sh", "--severity=style", "-"]
        case .zsh: return nil
        }
    }

    private struct Output: Decodable {
        let comments: [ShellCheckComment]
    }

    static func parse(_ data: Data) throws -> [ShellCheckComment] {
        try JSONDecoder().decode(Output.self, from: data).comments
    }

    static func run(script: Data, shell: ScriptShell, executable: URL, runner: CommandRunning) async throws -> [ShellCheckComment] {
        guard let arguments = arguments(for: shell) else { throw ShellCheckError.unsupportedShell }
        let result = try await runner.run(executable: executable, arguments: arguments, standardInput: script, timeout: 30)
        if result.timedOut { throw ShellCheckError.timedOut }
        // Exit code 0 means no comments, 1 means comments were found; anything else is a ShellCheck failure.
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw ShellCheckError.failed(result.standardErrorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            return try parse(result.standardOutput)
        } catch {
            throw ShellCheckError.failed("Unexpected output format.")
        }
    }
}
