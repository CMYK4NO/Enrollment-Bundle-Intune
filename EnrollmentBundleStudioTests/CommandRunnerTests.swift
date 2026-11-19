import XCTest
@testable import EnrollmentBundleStudio

final class CommandRunnerTests: XCTestCase {
    func testAllowlistRejectsBeforeLaunching() async {
        let runner = ProcessCommandRunner(allowedExecutables: ["/usr/bin/pkgbuild"])
        do {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo nope"], standardInput: nil, timeout: 5)
            XCTFail("A non-allowlisted executable must not run")
        } catch {
            XCTAssertEqual(error as? CommandRunnerError, .executableNotAllowed("/bin/sh"))
        }
    }

    func testMissingAllowedExecutableIsReported() async {
        let path = "/nonexistent/tool-\(UUID().uuidString)"
        let runner = ProcessCommandRunner(allowedExecutables: [path])
        do {
            _ = try await runner.run(executable: URL(fileURLWithPath: path), arguments: [], standardInput: nil, timeout: 5)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? CommandRunnerError, .executableMissing(path))
        }
    }

    func testShellCheckArgumentsAndInvocation() async throws {
        XCTAssertEqual(ShellCheckService.arguments(for: .bash), ["--format=json1", "--shell=bash", "--severity=style", "-"])
        XCTAssertEqual(ShellCheckService.arguments(for: .posixSh)?[1], "--shell=sh")
        XCTAssertNil(ShellCheckService.arguments(for: .zsh))

        let output = Data(#"{"comments":[{"file":"-","line":3,"endLine":3,"column":6,"endColumn":10,"level":"warning","code":2086,"message":"Double quote to prevent globbing and word splitting.","fix":null}]}"#.utf8)
        let mock = MockCommandRunner(result: CommandResult(exitCode: 1, standardOutput: output, standardError: Data(), timedOut: false))
        let script = Data(TestSupport.cleanScript.utf8)
        let comments = try await ShellCheckService.run(script: script, shell: .bash,
                                                       executable: URL(fileURLWithPath: "/opt/homebrew/bin/shellcheck"), runner: mock)
        XCTAssertEqual(comments.first?.code, 2086)
        XCTAssertEqual(comments.first?.severity, .warning)
        XCTAssertEqual(mock.calls.first?.executable, "/opt/homebrew/bin/shellcheck")
        XCTAssertEqual(mock.calls.first?.standardInput, script, "The script is passed on standard input, not executed")
    }

    func testShellCheckFailuresAreReported() async {
        let failing = MockCommandRunner(result: CommandResult(exitCode: 4, standardOutput: Data(), standardError: Data("bad flag".utf8), timedOut: false))
        do {
            _ = try await ShellCheckService.run(script: Data(), shell: .bash, executable: URL(fileURLWithPath: "/x"), runner: failing)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? ShellCheckError, .failed("bad flag"))
        }
        let slow = MockCommandRunner(result: CommandResult(exitCode: 15, standardOutput: Data(), standardError: Data(), timedOut: true))
        do {
            _ = try await ShellCheckService.run(script: Data(), shell: .bash, executable: URL(fileURLWithPath: "/x"), runner: slow)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? ShellCheckError, .timedOut)
        }
        do {
            _ = try await ShellCheckService.run(script: Data(), shell: .zsh, executable: URL(fileURLWithPath: "/x"), runner: slow)
            XCTFail("Expected unsupported shell")
        } catch {
            XCTAssertEqual(error as? ShellCheckError, .unsupportedShell)
        }
    }

    func testLocateUsesCandidatePaths() {
        XCTAssertEqual(ShellCheckService.locate(isExecutable: { $0 == "/usr/local/bin/shellcheck" })?.path, "/usr/local/bin/shellcheck")
        XCTAssertNil(ShellCheckService.locate(isExecutable: { _ in false }))
    }
}
