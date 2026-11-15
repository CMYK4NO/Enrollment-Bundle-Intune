import Foundation

/// Produces shell literals that Bash reads back as exactly the original text, with no expansion.
enum ShellQuoting {
    /// Wraps text in single quotes. Inside single quotes Bash expands nothing, so `$(...)`, backticks and
    /// variables stay literal; an embedded single quote is written as '\''. NUL characters cannot exist in
    /// shell strings and are removed.
    static func singleQuoted(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\u{0}", with: "")
        return "'" + cleaned.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `NAME='value'` for a task or configuration file.
    static func assignment(_ name: String, _ value: String) -> String {
        "\(name)=\(singleQuoted(value))"
    }

    /// `NAME=123` for numeric values.
    static func assignment(_ name: String, _ value: Int) -> String {
        "\(name)=\(value)"
    }

    static func assignment(_ name: String, _ value: Bool) -> String {
        "\(name)=\(value ? 1 : 0)"
    }
}

/// Dotted numeric version comparison, the same rules as version_ge in the framework.
enum VersionComparison {
    static func components(_ version: String) -> [Int] {
        version.split(separator: ".", omittingEmptySubsequences: false).prefix(4).map { part in
            Int(part.prefix { $0.isASCII && $0.isNumber }) ?? 0
        }
    }

    /// True when `version` >= `minimum`, comparing up to four numeric components.
    static func isAtLeast(_ version: String, _ minimum: String) -> Bool {
        let lhs = components(version)
        let rhs = components(minimum)
        for index in 0..<4 {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return true
    }
}
