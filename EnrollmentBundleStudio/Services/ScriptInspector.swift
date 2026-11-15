import Foundation

enum ScriptShell: String, Equatable {
    case bash
    case zsh
    case posixSh
    case unsupported
    case missing

    var title: String {
        switch self {
        case .bash: return "Bash"
        case .zsh: return "zsh"
        case .posixSh: return "sh"
        case .unsupported: return "Unsupported"
        case .missing: return "No shebang"
        }
    }

    /// macOS /bin/sh is Bash 3.2 in POSIX mode, so it gets the same compatibility checks.
    var receivesBashChecks: Bool { self == .bash || self == .posixSh }
}

struct ScriptFinding: Identifiable, Equatable {
    let rule: String
    let severity: ValidationSeverity
    /// 1-based line number, or 0 for findings about the whole file.
    let line: Int
    let message: String

    var id: String { "\(rule):\(line)" }
}

struct ScriptInspection: Equatable {
    var shebang: String?
    var interpreter: String?
    var shell: ScriptShell
    var lineCount: Int
    var findings: [ScriptFinding]

    var hasErrors: Bool { findings.contains { $0.severity == .error } }

    /// True when the interpreter is one the generated framework can run on a standard Mac.
    var isSupportedInterpreter: Bool {
        !findings.contains { $0.rule.hasPrefix("interpreter-") && $0.severity == .error }
    }

    func count(_ severity: ValidationSeverity) -> Int {
        findings.filter { $0.severity == severity }.count
    }
}

/// Heuristic, line-based checks for imported scripts. It reads text only and never executes anything.
/// These checks catch common Bash 3.2 incompatibilities and risky patterns; they do not replace ShellCheck.
enum ScriptInspector {
    static let largeScriptBytes = 512 * 1024
    static let systemInterpreters: Set<String> = ["/bin/bash", "/bin/zsh", "/bin/sh"]

    private struct Rule {
        let id: String
        let regex: NSRegularExpression
        let severity: ValidationSeverity
        let message: String
        let bashOnly: Bool

        init?(_ id: String, _ pattern: String, _ severity: ValidationSeverity, _ message: String, bashOnly: Bool = false) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            self.id = id
            self.regex = regex
            self.severity = severity
            self.message = message
            self.bashOnly = bashOnly
        }
    }

    private static let ruleDefinitions: [Rule?] = [
        // Bash 4+ constructs that fail on macOS Bash 3.2.
        Rule("bash4-associative-array", #"\b(declare|typeset|local)\s+-[a-zA-Z]*A"#, .warning,
             "Associative arrays need Bash 4; macOS ships Bash 3.2.", bashOnly: true),
        Rule("bash4-mapfile", #"(^|[;&|(\s])(mapfile|readarray)\b"#, .warning,
             "mapfile and readarray need Bash 4. Use a while read loop.", bashOnly: true),
        Rule("bash4-case-modification", #"\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?(\^\^|,,|\^|,)\}"#, .warning,
             "Case modification such as ${var,,} needs Bash 4. Use tr '[:upper:]' '[:lower:]'.", bashOnly: true),
        Rule("bash4-append-both", #"&>>"#, .warning,
             "&>> needs Bash 4. Use >>file 2>&1.", bashOnly: true),
        Rule("bash4-pipe-both", #"\|&"#, .warning,
             "|& needs Bash 4. Use 2>&1 |.", bashOnly: true),
        Rule("bash4-coproc", #"(^|[;&|\s])coproc\b"#, .warning,
             "coproc needs Bash 4.", bashOnly: true),
        Rule("bash4-nameref", #"\b(declare|typeset|local)\s+-[a-zA-Z]*n[a-zA-Z]*\s"#, .warning,
             "Name references (declare -n) need Bash 4.3.", bashOnly: true),
        Rule("bash4-transform", #"\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?@[QEPAKaUuL]\}"#, .warning,
             "Parameter transformations such as ${var@Q} need Bash 4.4.", bashOnly: true),
        Rule("bash4-shopt", #"\bshopt\s+-s\s+(globstar|lastpipe|autocd|checkjobs|direxpand)\b"#, .warning,
             "This shopt option does not exist in Bash 3.2.", bashOnly: true),
        Rule("bash4-wait-n", #"\bwait\s+-n\b"#, .warning,
             "wait -n needs Bash 4.3. Poll child PIDs with kill -0.", bashOnly: true),
        Rule("bash4-test-v", #"\[\[\s+-v\s"#, .warning,
             "[[ -v name ]] needs Bash 4.2. Use [ -n \"${name+x}\" ].", bashOnly: true),
        Rule("bash4-negative-index", #"\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}"#, .warning,
             "Negative array indexes need Bash 4.3.", bashOnly: true),
        Rule("bash4-case-fallthrough", #";;&"#, .warning,
             ";;& in case statements needs Bash 4.", bashOnly: true),
        Rule("bash5-variables", #"\$\{?(EPOCHSECONDS|EPOCHREALTIME|BASHPID)\b"#, .warning,
             "This variable does not exist in Bash 3.2.", bashOnly: true),

        // Security and compatibility, all shells.
        Rule("sudo", #"(^|[;&|(\s])sudo\s"#, .warning,
             "Uses sudo. Intune already runs scripts as root; for user actions set the task context to Console user."),
        Rule("download-http", #"\b(curl|wget)\b.*\bhttp://"#, .warning,
             "Downloads over unencrypted HTTP. Use HTTPS and verify the file before use."),
        Rule("download-pipe-to-shell", #"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(/bin/)?(ba|z)?sh\b"#, .warning,
             "Pipes a download straight into a shell. Download to a file, verify it, then run it."),
        Rule("download-insecure-tls", #"\bcurl\b.*\s(-[a-zA-Z]*k[a-zA-Z]*|--insecure)(\s|$)"#, .warning,
             "Disables TLS certificate checks (curl -k or --insecure)."),
        Rule("admin-applescript", #"with administrator privileges"#, .warning,
             "Requests administrator privileges through AppleScript, which prompts the user."),
        Rule("gatekeeper-disable", #"\bspctl\s+(--master-disable|--global-disable|--disable)\b"#, .warning,
             "Disables Gatekeeper."),
        Rule("quarantine-removal", #"\bxattr\b.*com\.apple\.quarantine"#, .warning,
             "Removes the quarantine attribute, bypassing Gatekeeper checks."),
        Rule("quarantine-clear-recursive", #"\bxattr\s+-(cr|rc)\b"#, .warning,
             "Clears all extended attributes recursively, including quarantine."),
        Rule("sip-disable", #"\bcsrutil\s+disable\b"#, .warning,
             "Attempts to disable System Integrity Protection."),
        Rule("world-writable", #"\bchmod\s+(-R\s+)?0?777\b"#, .warning,
             "Makes files world-writable (chmod 777)."),
        Rule("rm-root", #"\brm\s+-[a-zA-Z]*r[a-zA-Z]*\s+(/|~|/\*)(\s|$)"#, .warning,
             "Recursive delete of / or the home folder."),
        Rule("rm-unquoted-variable", #"\brm\s+-[a-zA-Z]*r[a-zA-Z]*\s+\$"#, .warning,
             "Recursive delete of an unquoted variable. If it is empty the wrong path is removed; quote it and check it first."),
        Rule("hardcoded-secret", #"(?i)\b[a-z_]*(password|passwd|secret|api_?key|token)[a-z_]*\s*=\s*["']?[^\s"'$]{6,}"#, .warning,
             "Looks like a hard-coded secret. Anyone with the package can read it."),
        Rule("interactive-read", #"(^|[;&|\s])read\s+(-[a-zA-Z]+\s+)*-[a-zA-Z]*p"#, .warning,
             "Prompts for input. Intune runs scripts without a terminal, so this waits until timeout."),
        Rule("python-dependency", #"(^|[;&|\s])(/usr/bin/)?python[23]?\s"#, .warning,
             "Calls Python, which is not installed on a standard Mac."),
        Rule("eval", #"(^|[;&|\s])eval\s"#, .information,
             "Uses eval. Make sure no untrusted input reaches it."),
        Rule("set-e", #"^\s*set\s+-[a-zA-Z]*e"#, .information,
             "Uses set -e, which can end the script silently. Prefer explicit exit-code checks.")
    ]

    private static let rules: [Rule] = ruleDefinitions.compactMap { $0 }

    /// Number of defined and successfully compiled rules (tests check they are equal).
    static var definedRuleCount: Int { ruleDefinitions.count }
    static var compiledRuleCount: Int { rules.count }

    static func inspect(_ data: Data) -> ScriptInspection {
        guard !data.isEmpty else {
            return ScriptInspection(shebang: nil, interpreter: nil, shell: .missing, lineCount: 0, findings: [
                ScriptFinding(rule: "file-empty", severity: .error, line: 0, message: "The script is empty.")
            ])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ScriptInspection(shebang: nil, interpreter: nil, shell: .missing, lineCount: 0, findings: [
                ScriptFinding(rule: "file-encoding", severity: .error, line: 0, message: "The script is not valid UTF-8 text.")
            ])
        }

        var findings: [ScriptFinding] = []
        // Check bytes, not Characters: in Swift "\r\n" is a single grapheme cluster, so a Character-based
        // search for "\r" can miss Windows line endings entirely. 0x0D is carriage return.
        if data.contains(0x0D) {
            findings.append(ScriptFinding(rule: "file-line-endings", severity: .error, line: 0,
                                          message: "Uses Windows (CRLF) line endings, which break the shebang and commands. Convert to LF."))
        }
        if data.count > largeScriptBytes {
            findings.append(ScriptFinding(rule: "file-large", severity: .warning, line: 0,
                                          message: "The script is larger than 512 KB. Large scripts slow down Intune deployments."))
        }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let parsed = parseShebang(lines.first)
        findings.append(contentsOf: interpreterFindings(shebang: parsed.shebang, interpreter: parsed.interpreter, shell: parsed.shell))

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for rule in rules where !rule.bashOnly || parsed.shell.receivesBashChecks {
                if rule.regex.firstMatch(in: line, options: [], range: range) != nil {
                    findings.append(ScriptFinding(rule: rule.id, severity: rule.severity, line: index + 1, message: rule.message))
                }
            }
        }

        let sorted = findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.rule < rhs.rule
        }
        return ScriptInspection(shebang: parsed.shebang, interpreter: parsed.interpreter, shell: parsed.shell,
                                lineCount: lines.count, findings: sorted)
    }

    static func parseShebang(_ firstLine: String?) -> (shebang: String?, interpreter: String?, shell: ScriptShell) {
        guard let line = firstLine?.trimmingCharacters(in: .whitespaces), line.hasPrefix("#!") else {
            return (nil, nil, .missing)
        }
        let body = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = parts.first else {
            return (line, nil, .unsupported)
        }
        var program = first
        var interpreter = first
        if first == "/usr/bin/env" {
            guard let target = parts.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
                return (line, first, .unsupported)
            }
            program = target
            interpreter = "/usr/bin/env \(target)"
        }
        let name = (program as NSString).lastPathComponent
        let shell: ScriptShell
        switch name {
        case "bash": shell = .bash
        case "zsh": shell = .zsh
        case "sh": shell = .posixSh
        default: shell = .unsupported
        }
        return (line, interpreter, shell)
    }

    private static func interpreterFindings(shebang: String?, interpreter: String?, shell: ScriptShell) -> [ScriptFinding] {
        guard shebang != nil else {
            return [ScriptFinding(rule: "interpreter-missing", severity: .error, line: 1,
                                  message: "No shebang line. Start the script with #!/bin/bash or #!/bin/zsh.")]
        }
        guard let interpreter, shell != .unsupported else {
            return [ScriptFinding(rule: "interpreter-unsupported", severity: .error, line: 1,
                                  message: "Unsupported interpreter \(interpreter ?? "(empty)"). Use /bin/bash or /bin/zsh.")]
        }
        if interpreter.hasPrefix("/usr/bin/env ") {
            return [ScriptFinding(rule: "interpreter-env", severity: .warning, line: 1,
                                  message: "\(interpreter) depends on PATH and may find a non-system shell. Use an absolute path such as /bin/bash.")]
        }
        guard systemInterpreters.contains(interpreter) else {
            return [ScriptFinding(rule: "interpreter-nonsystem", severity: .error, line: 1,
                                  message: "\(interpreter) is not present on a standard Mac. Use /bin/bash or /bin/zsh.")]
        }
        switch shell {
        case .posixSh:
            return [ScriptFinding(rule: "interpreter-sh", severity: .information, line: 1,
                                  message: "/bin/sh runs Bash 3.2 in POSIX mode. #!/bin/bash is clearer.")]
        case .zsh, .bash, .unsupported, .missing:
            return []
        }
    }
}

/// Inspection is pure, so results are cached by file content. Validation runs on every edit.
final class ScriptInspectionCache {
    static let shared = ScriptInspectionCache()

    private var storage: [Data: ScriptInspection] = [:]
    private let lock = NSLock()

    func inspection(for data: Data) -> ScriptInspection {
        lock.lock()
        if let cached = storage[data] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let result = ScriptInspector.inspect(data)
        lock.lock()
        if storage.count > 200 {
            storage.removeAll()
        }
        storage[data] = result
        lock.unlock()
        return result
    }
}
