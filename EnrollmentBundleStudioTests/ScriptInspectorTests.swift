import XCTest
@testable import EnrollmentBundleStudio

final class ScriptInspectorTests: XCTestCase {
    private func rules(_ source: String) -> Set<String> {
        Set(ScriptInspector.inspect(Data(source.utf8)).findings.map { $0.rule })
    }

    func testAllRulesCompile() {
        XCTAssertEqual(ScriptInspector.compiledRuleCount, ScriptInspector.definedRuleCount)
    }

    func testCleanScriptHasNoFindings() {
        let inspection = ScriptInspector.inspect(Data(TestSupport.cleanScript.utf8))
        XCTAssertEqual(inspection.findings, [])
        XCTAssertEqual(inspection.shell, .bash)
        XCTAssertEqual(inspection.interpreter, "/bin/bash")
        XCTAssertTrue(inspection.isSupportedInterpreter)
    }

    func testShebangParsing() {
        XCTAssertEqual(ScriptInspector.parseShebang("#!/bin/zsh").shell, .zsh)
        XCTAssertEqual(ScriptInspector.parseShebang("#!/bin/sh").shell, .posixSh)
        XCTAssertEqual(ScriptInspector.parseShebang("#! /bin/bash -x").interpreter, "/bin/bash")
        XCTAssertEqual(ScriptInspector.parseShebang("#!/usr/bin/env bash").interpreter, "/usr/bin/env bash")
        XCTAssertEqual(ScriptInspector.parseShebang("#!/usr/bin/python3").shell, .unsupported)
        XCTAssertEqual(ScriptInspector.parseShebang("echo hi").shell, .missing)
        XCTAssertEqual(ScriptInspector.parseShebang(nil).shell, .missing)
    }

    func testInterpreterFindings() {
        XCTAssertTrue(rules("echo hi\n").contains("interpreter-missing"))
        XCTAssertTrue(rules("#!/usr/bin/python3\nprint(1)\n").contains("interpreter-unsupported"))
        XCTAssertTrue(rules("#!/opt/homebrew/bin/bash\necho hi\n").contains("interpreter-nonsystem"))
        XCTAssertTrue(rules("#!/usr/bin/env bash\necho hi\n").contains("interpreter-env"))
        XCTAssertTrue(rules("#!/bin/sh\necho hi\n").contains("interpreter-sh"))
        XCTAssertFalse(ScriptInspector.inspect(Data("#!/usr/bin/python3\n".utf8)).isSupportedInterpreter)
        XCTAssertTrue(ScriptInspector.inspect(Data("#!/usr/bin/env bash\n".utf8)).isSupportedInterpreter)
    }

    func testBash4ConstructsAreDetected() {
        let source = """
        #!/bin/bash
        declare -A apps
        mapfile -t lines < file
        lower="${name,,}"
        upper="${name^^}"
        echo hi &>> /tmp/log
        cmd |& tee out
        local -n ref=var
        quoted="${name@Q}"
        shopt -s globstar
        wait -n
        if [[ -v name ]]; then :; fi
        last="${items[-1]}"
        start=$EPOCHSECONDS
        """
        let found = rules(source)
        for rule in ["bash4-associative-array", "bash4-mapfile", "bash4-case-modification", "bash4-append-both",
                     "bash4-pipe-both", "bash4-nameref", "bash4-transform", "bash4-shopt", "bash4-wait-n",
                     "bash4-test-v", "bash4-negative-index", "bash5-variables"] {
            XCTAssertTrue(found.contains(rule), "Missing \(rule)")
        }
    }

    func testBashRulesSkipZshAndAvoidFalsePositives() {
        XCTAssertFalse(rules("#!/bin/zsh\ntypeset -A apps\nlower=\"${name:l}\"\n").contains("bash4-associative-array"))
        let ordinary = """
        #!/bin/bash
        value="${name:-default,value}"
        if [ -n "$value" ]; then echo "$value"; fi
        # declare -A only in a comment
        echo "done" >> /tmp/log 2>&1
        """
        XCTAssertTrue(rules(ordinary).filter { $0.hasPrefix("bash") }.isEmpty, "\(rules(ordinary))")
    }

    func testSecurityPatterns() {
        let source = """
        #!/bin/bash
        sudo launchctl kickstart system/com.example
        curl -o /tmp/x http://example.com/x.pkg
        curl -fsSL https://example.com/install.sh | bash
        curl -k https://example.com/data
        osascript -e 'do shell script "id" with administrator privileges'
        spctl --master-disable
        xattr -d com.apple.quarantine /Applications/App.app
        xattr -cr /Applications/App.app
        csrutil disable
        chmod 777 /tmp/file
        rm -rf /
        rm -rf $TARGET
        API_TOKEN="abcdef123456"
        read -p "Continue? " answer
        python3 script.py
        eval "$command"
        set -e
        """
        let found = rules(source)
        for rule in ["sudo", "download-http", "download-pipe-to-shell", "download-insecure-tls", "admin-applescript",
                     "gatekeeper-disable", "quarantine-removal", "quarantine-clear-recursive", "sip-disable",
                     "world-writable", "rm-root", "rm-unquoted-variable", "hardcoded-secret", "interactive-read",
                     "python-dependency", "eval", "set-e"] {
            XCTAssertTrue(found.contains(rule), "Missing \(rule)")
        }
    }

    func testSecretRuleIgnoresVariableReferences() {
        XCTAssertFalse(rules("#!/bin/bash\npassword=\"$1\"\ntoken=$(security find-generic-password -w)\n").contains("hardcoded-secret"))
    }

    func testFileLevelProblems() {
        XCTAssertEqual(ScriptInspector.inspect(Data()).findings.first?.rule, "file-empty")
        XCTAssertEqual(ScriptInspector.inspect(Data([0xFF, 0xFE, 0x00])).findings.first?.rule, "file-encoding")
        let crlf = ScriptInspector.inspect(Data("#!/bin/bash\r\necho hi\r\n".utf8))
        XCTAssertTrue(crlf.findings.contains { $0.rule == "file-line-endings" && $0.severity == .error })
        XCTAssertEqual(crlf.interpreter, "/bin/bash")
        XCTAssertEqual(crlf.lineCount, 3, "CRLF is normalized before splitting lines")
        let classicMac = ScriptInspector.inspect(Data("#!/bin/bash\recho hi\r".utf8))
        XCTAssertTrue(classicMac.findings.contains { $0.rule == "file-line-endings" })
        let unix = ScriptInspector.inspect(Data("#!/bin/bash\necho hi\n".utf8))
        XCTAssertFalse(unix.findings.contains { $0.rule == "file-line-endings" })
    }

    func testFindingsHaveLineNumbersAndSortBySeverity() {
        let inspection = ScriptInspector.inspect(Data("#!/bin/bash\neval \"$x\"\nsudo true\n".utf8))
        XCTAssertEqual(inspection.findings.first?.rule, "sudo")
        XCTAssertEqual(inspection.findings.first?.line, 3)
        XCTAssertEqual(inspection.findings.last?.rule, "eval")
        XCTAssertEqual(inspection.findings.last?.line, 2)
    }

    func testCacheReturnsSameResult() {
        let data = Data(TestSupport.cleanScript.utf8)
        XCTAssertEqual(ScriptInspectionCache.shared.inspection(for: data), ScriptInspector.inspect(data))
    }
}
