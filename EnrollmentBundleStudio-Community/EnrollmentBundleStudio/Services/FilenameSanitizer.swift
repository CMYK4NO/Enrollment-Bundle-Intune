import Foundation

/// Produces safe, portable file names and identifiers from user-entered text.
enum FilenameSanitizer {
    /// Keeps ASCII letters and digits, maps runs of other characters to a single separator
    /// ("." "_" "-" are kept as-is, anything else becomes "-"), folds accents, trims separators
    /// from both ends and limits the length. Never returns "." or "..".
    static func sanitize(_ name: String, fallback: String = "item", maxLength: Int = 64) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var output = ""
        var lastWasSeparator = false
        for scalar in folded.unicodeScalars {
            if isASCIIAlphanumeric(scalar) {
                output.unicodeScalars.append(scalar)
                lastWasSeparator = false
                continue
            }
            guard !lastWasSeparator else { continue }
            if scalar == "." || scalar == "_" || scalar == "-" {
                output.unicodeScalars.append(scalar)
            } else {
                output.append("-")
            }
            lastWasSeparator = true
        }
        output = trimSeparators(output)
        if output.count > maxLength {
            output = trimSeparators(String(output.prefix(maxLength)))
        }
        return output.isEmpty ? fallback : output
    }

    /// Lowercase kebab-case slug for task identifiers, for example "microsoft-defender".
    static func slug(_ name: String, maxLength: Int = 48) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var output = ""
        var lastWasSeparator = false
        for scalar in folded.unicodeScalars {
            if isASCIIAlphanumeric(scalar) {
                output.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                output.append("-")
                lastWasSeparator = true
            }
        }
        output = trimSeparators(output)
        if output.count > maxLength {
            output = trimSeparators(String(output.prefix(maxLength)))
        }
        return output
    }

    /// Returns `base.ext`, or `base-2.ext`, `base-3.ext` and so on, avoiding names in `existing`.
    static func uniqueName(base: String, fileExtension: String, existing: Set<String>) -> String {
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        var candidate = "\(base)\(suffix)"
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(counter)\(suffix)"
            counter += 1
        }
        return candidate
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z") || (scalar >= "0" && scalar <= "9")
    }

    private static func trimSeparators(_ value: String) -> String {
        var result = Substring(value)
        while let first = result.first, first == "." || first == "_" || first == "-" {
            result = result.dropFirst()
        }
        while let last = result.last, last == "." || last == "_" || last == "-" {
            result = result.dropLast()
        }
        return String(result)
    }
}
