import Foundation

struct CommandResult: Equatable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
    let timedOut: Bool

    var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }
    var standardErrorText: String { String(decoding: standardError, as: UTF8.self) }
}

/// The only way the application starts another program. Implementations take an executable URL and a
/// separate arguments array, never a shell command string. Tests substitute a mock.
protocol CommandRunning {
    func run(executable: URL, arguments: [String], standardInput: Data?, timeout: TimeInterval) async throws -> CommandResult
}

enum CommandRunnerError: LocalizedError, Equatable {
    case executableNotAllowed(String)
    case executableMissing(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotAllowed(let path):
            return "\(path) is not on the list of tools this application may run."
        case .executableMissing(let path):
            return "\(path) was not found or is not executable."
        case .launchFailed(let detail):
            return "The tool could not be started: \(detail)"
        }
    }
}

/// Runs allowlisted executables with Process. No /bin/sh -c, a fixed minimal PATH, and a hard timeout.
struct ProcessCommandRunner: CommandRunning {
    let allowedExecutables: Set<String>

    /// Without this, writing to a tool that already exited would deliver SIGPIPE and terminate the app.
    private static let ignoreBrokenPipe: Void = {
        _ = signal(SIGPIPE, SIG_IGN)
    }()

    init(allowedExecutables: Set<String>) {
        self.allowedExecutables = Set(allowedExecutables.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        _ = Self.ignoreBrokenPipe
    }

    func run(executable: URL, arguments: [String], standardInput: Data?, timeout: TimeInterval) async throws -> CommandResult {
        let path = executable.standardizedFileURL.path
        guard allowedExecutables.contains(path) else { throw CommandRunnerError.executableNotAllowed(path) }
        guard FileManager.default.isExecutableFile(atPath: path) else { throw CommandRunnerError.executableMissing(path) }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runSynchronously(executable: URL(fileURLWithPath: path), arguments: arguments,
                                                           standardInput: standardInput, timeout: timeout)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private final class Collector {
        private let lock = NSLock()
        private var output = Data()
        private var error = Data()
        private var didTimeOut = false

        func setOutput(_ data: Data) { lock.lock(); output = data; lock.unlock() }
        func setError(_ data: Data) { lock.lock(); error = data; lock.unlock() }
        func markTimedOut() { lock.lock(); didTimeOut = true; lock.unlock() }
        func snapshot() -> (Data, Data, Bool) { lock.lock(); defer { lock.unlock() }; return (output, error, didTimeOut) }
    }

    private static func runSynchronously(executable: URL, arguments: [String], standardInput: Data?, timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if standardInput == nil {
            process.standardInput = FileHandle.nullDevice
        } else {
            process.standardInput = inputPipe
        }

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed(error.localizedDescription)
        }

        let collector = Collector()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.setOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.setError(errorPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        let timer = DispatchWorkItem {
            if process.isRunning {
                collector.markTimedOut()
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)

        if let standardInput {
            // write(contentsOf:) throws instead of raising an Objective-C exception if the tool exits early.
            try? inputPipe.fileHandleForWriting.write(contentsOf: standardInput)
            try? inputPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        timer.cancel()
        readers.wait()
        let (output, errorOutput, timedOut) = collector.snapshot()
        return CommandResult(exitCode: process.terminationStatus, standardOutput: output, standardError: errorOutput, timedOut: timedOut)
    }
}
