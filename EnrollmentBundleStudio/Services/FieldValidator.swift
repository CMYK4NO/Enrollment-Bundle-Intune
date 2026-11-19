import Foundation

/// Validation for individual settings fields. Each `...Issue` function returns nil when valid.
enum FieldValidator {
    /// Reverse-DNS identifier such as com.company.enrollment.bundle:
    /// at least two dot-separated labels, each 1-63 ASCII letters, digits or hyphens,
    /// not starting or ending with a hyphen; the first label starts with a letter.
    static func isValidReverseDNS(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255 else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for (index, label) in labels.enumerated() {
            guard (1...63).contains(label.count),
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  label.first != "-", label.last != "-" else {
                return false
            }
            if index == 0, let first = label.first, !first.isLetter {
                return false
            }
        }
        return true
    }

    static func reverseDNSIssue(_ value: String) -> String? {
        if value.isEmpty {
            return "Required."
        }
        return isValidReverseDNS(value) ? nil : "Use reverse-DNS format, for example com.company.enrollment.bundle."
    }

    /// Dotted numeric version with 1-4 components, each up to 9 digits, for example 1.0.0.
    static func isValidVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(components.count) else { return false }
        return components.allSatisfy { component in
            (1...9).contains(component.count) && component.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    static func versionIssue(_ value: String) -> String? {
        if value.isEmpty {
            return "Required."
        }
        return isValidVersion(value) ? nil : "Use numbers separated by dots, for example 1.0.0."
    }

    /// An optional http or https URL with a host.
    static func urlIssue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty else {
            return "Enter a full URL starting with https://."
        }
        return nil
    }

    static func requiredTextIssue(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Required." : nil
    }

    /// Absolute device path, used for install and state locations.
    static func absolutePathIssue(_ value: String) -> String? {
        guard value.hasPrefix("/") else { return "Use an absolute path starting with /." }
        guard !value.split(separator: "/").contains("..") else { return "The path must not contain \"..\"." }
        return nil
    }

    /// Device folder that the generated package changes recursively (install location, state directory).
    /// Stricter than `absolutePathIssue`: a system folder such as /Library or /Users would have its ownership and
    /// permissions rewritten on every Mac, so at least three path components are required and "//" and control
    /// characters are refused. The generated postinstall script and state_init apply the same rule on the device.
    static func deviceDirectoryIssue(_ value: String) -> String? {
        if let issue = absolutePathIssue(value) { return issue }
        guard !value.contains("//"), !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return "The path must not contain \"//\" or control characters."
        }
        let trimmed = value.hasSuffix("/") ? String(value.dropLast()) : value
        guard trimmed.split(separator: "/").count >= 3 else {
            return "Use a dedicated folder at least three levels deep, for example /Library/Application Support/Company/Enrollment."
        }
        return nil
    }

    /// Folder that holds the detection placeholder app. Empty means "the install location". Only one app bundle is
    /// placed there and nothing in it is changed recursively, so a folder such as /Applications is fine; system
    /// locations and the root are not.
    static func detectionDirectoryIssue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let issue = absolutePathIssue(trimmed) { return issue }
        guard !trimmed.contains("//"), !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return "The path must not contain \"//\" or control characters."
        }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let blocked = ["", "/System", "/usr", "/bin", "/sbin", "/private", "/var", "/Library", "/Users", "/Library/LaunchDaemons"]
        if blocked.contains(normalized) || normalized.hasPrefix("/System/") || normalized.hasPrefix("/usr/")
            || normalized.hasPrefix("/bin/") || normalized.hasPrefix("/sbin/") {
            return "Choose a folder such as /Applications or /Library/Application Support/Company; system folders are not allowed."
        }
        if normalized.hasSuffix(".app") {
            return "Enter the folder that will contain the app, not the app itself."
        }
        return nil
    }
}
