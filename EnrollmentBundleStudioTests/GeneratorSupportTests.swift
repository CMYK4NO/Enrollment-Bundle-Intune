import XCTest
@testable import EnrollmentBundleStudio

final class ShellQuotingTests: XCTestCase {
    private let nasty = [
        "", "plain", "it's", "''", "$(rm -rf /)", "`id`", "${HOME}", "a\nb", "back\\slash", "semi; colon && pipe | x",
        "unicode ✓ é 日本", "trailing '", "' leading", "\"double\""
    ]

    func testRoundTripsEveryValue() throws {
        for value in nasty {
            let literal = ShellQuoting.singleQuoted(value)
            XCTAssertTrue(literal.hasPrefix("'") && literal.hasSuffix("'"), literal)
            XCTAssertEqual(try ShellLiteralReader.decodeSingleQuoted(literal), value, literal)
        }
    }

    func testEmbeddedQuoteForm() {
        XCTAssertEqual(ShellQuoting.singleQuoted("it's"), "'it'\\''s'")
        XCTAssertEqual(ShellQuoting.singleQuoted("a\u{0}b"), "'ab'", "NUL cannot exist in shell strings")
    }

    func testAssignments() {
        XCTAssertEqual(ShellQuoting.assignment("NAME", "x y"), "NAME='x y'")
        XCTAssertEqual(ShellQuoting.assignment("COUNT", 3), "COUNT=3")
        XCTAssertEqual(ShellQuoting.assignment("FLAG", true), "FLAG=1")
        XCTAssertEqual(ShellQuoting.assignment("FLAG", false), "FLAG=0")
    }

    func testDataOnlyParserRejectsCode() {
        XCTAssertThrowsError(try ShellLiteralReader.assignments(in: "TASK_ID='a'\necho pwned\n"))
        XCTAssertThrowsError(try ShellLiteralReader.assignments(in: "TASK_ID=$(id)\n"))
        XCTAssertThrowsError(try ShellLiteralReader.assignments(in: "TASK_ID='a'; rm -rf /\n"))
        XCTAssertEqual(try ShellLiteralReader.assignments(in: "# c\nA='x'\\''y'\nB=-1\n"), ["A": "x'y", "B": "-1"])
    }
}

final class VersionComparisonTests: XCTestCase {
    func testComparisons() {
        XCTAssertTrue(VersionComparison.isAtLeast("2.5.2.4777", "2.5.0"))
        XCTAssertTrue(VersionComparison.isAtLeast("2.5", "2.5.0"))
        XCTAssertFalse(VersionComparison.isAtLeast("2.4.9", "2.5.0"))
        XCTAssertTrue(VersionComparison.isAtLeast("10.0", "9.9.9"))
        XCTAssertFalse(VersionComparison.isAtLeast("2.5.0", "9.0"))
        XCTAssertTrue(VersionComparison.isAtLeast("2.5.0b3", "2.5.0"))
    }
}

final class DialogCommandTests: XCTestCase {
    func testStatusMappingMatchesFramework() {
        // Same table as dialog_status_for in lib/dialog.sh.
        let expected: [TaskStatus: String] = [
            .pending: "pending", .waiting: "wait", .running: "wait", .complete: "success",
            .completeWithWarnings: "error", .skipped: "pending", .failed: "fail", .timedOut: "fail"
        ]
        for status in TaskStatus.allCases {
            XCTAssertEqual(DialogCommand.status(for: status), expected[status], status.rawValue)
        }
        XCTAssertTrue(FrameworkTemplates.libraryDialog.contains("completeWithWarnings) printf 'error'"))
    }

    func testCommandFormats() {
        XCTAssertEqual(DialogCommand.listItem(index: 2, status: .failed, text: "Failed, sorry\nreally"),
                       "listitem: index: 2, status: fail, statustext: Failed  sorry really")
        XCTAssertEqual(DialogCommand.message("Line 1\nLine 2"), "message: Line 1\\nLine 2")
        XCTAssertEqual(DialogCommand.progress(3), "progress: 3")
        XCTAssertEqual(DialogCommand.buttonEnable, "button1: enable")
        XCTAssertEqual(DialogCommand.quit, "quit:")
    }

    func testPlaceholderNormalization() {
        XCTAssertEqual(PlaceholderResolver.normalizingTokens("Hi {UserFullName} at {COMPANYNAME} {unknown}"),
                       "Hi {userfullname} at {companyname} {unknown}")
    }
}

final class FrameworkTemplateTests: XCTestCase {
    func testAllLibrariesAreEmbedded() {
        let paths = Set(FrameworkTemplates.staticFiles.map { $0.path })
        for library in ["common", "logging", "state", "user", "network", "dialog", "validation", "task-runner"] {
            XCTAssertTrue(paths.contains("lib/\(library).sh"), library)
        }
        XCTAssertTrue(paths.contains("enrollment.sh"))
        XCTAssertTrue(paths.contains("uninstall.sh"))
        XCTAssertEqual(FrameworkTemplates.staticFiles.filter { $0.isExecutable }.map { $0.path }.sorted(), ["enrollment.sh", "uninstall.sh"])
    }

    func testEnrollmentFollowsLoggingStandard() {
        let common = FrameworkTemplates.libraryLogging
        XCTAssertTrue(common.contains(#"logandmetadir="/Library/Logs/Microsoft/IntuneScripts/$appname""#))
        XCTAssertTrue(common.contains("log_keep=10"))
        XCTAssertTrue(common.contains(#"logfile="$logandmetadir/${appname}_$(date +%Y%m%d-%H%M%S).log""#))
        let enrollment = FrameworkTemplates.enrollmentScript
        XCTAssertTrue(enrollment.hasPrefix("#!/bin/bash"))
        for mode in ["--dry-run", "--preview", "--force", "--help"] {
            XCTAssertTrue(enrollment.contains(mode), mode)
        }
        XCTAssertTrue(enrollment.contains("set -u"))
        XCTAssertFalse(enrollment.contains("set -e"))
    }

    func testTemplatesHaveNoBash4ConstructsOrEval() {
        let all = FrameworkTemplates.staticFiles.map { ($0.path, $0.contents) }
            + [("preinstall", FrameworkTemplates.preinstallScript), ("postinstall", FrameworkTemplates.postinstallScript)]
        for (path, contents) in all {
            let source = contents.hasPrefix("#!") ? contents : "#!/bin/bash\n" + contents
            let findings = ScriptInspector.inspect(Data(source.utf8)).findings
            XCTAssertFalse(findings.contains { $0.rule.hasPrefix("bash") }, "\(path): \(findings)")
            XCTAssertFalse(findings.contains { $0.severity == .error }, "\(path): \(findings)")
            XCTAssertFalse(findings.contains { $0.rule == "eval" }, "\(path) uses eval")
            let unexpected = findings.filter { !($0.rule == "sudo" && path == "lib/user.sh") }
            XCTAssertTrue(unexpected.isEmpty, "\(path): \(unexpected)")
        }
    }
}
