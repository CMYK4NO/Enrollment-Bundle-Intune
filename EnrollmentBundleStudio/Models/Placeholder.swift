import Foundation

/// Tokens that the generated enrollment framework replaces on the device at run time.
enum Placeholder: String, CaseIterable, Identifiable, Codable {
    case companyName = "companyname"
    case userName = "username"
    case userFullName = "userfullname"
    case computerName = "computername"
    case computerModel = "computermodel"
    case serialNumber = "serialnumber"
    case osVersion = "osversion"
    case osName = "osname"

    var id: String { rawValue }

    var token: String { "{\(rawValue)}" }

    var displayName: String {
        switch self {
        case .companyName: return "Company name"
        case .userName: return "User name"
        case .userFullName: return "User full name"
        case .computerName: return "Computer name"
        case .computerModel: return "Computer model"
        case .serialNumber: return "Serial number"
        case .osVersion: return "macOS version"
        case .osName: return "macOS name"
        }
    }

    var explanation: String {
        switch self {
        case .companyName: return "Organization name from the project."
        case .userName: return "Short name of the console user."
        case .userFullName: return "Full name of the console user."
        case .computerName: return "Computer name from Sharing settings."
        case .computerModel: return "Hardware model identifier."
        case .serialNumber: return "Hardware serial number."
        case .osVersion: return "Version number, for example 15.1."
        case .osName: return "Marketing name, for example Sequoia."
        }
    }
}

/// Finds and replaces placeholder tokens. Matching is case-insensitive, unknown tokens are left
/// unchanged, and replacement is single-pass so a value containing "{token}" is never expanded again.
enum PlaceholderResolver {
    struct BraceToken: Equatable {
        let range: Range<String.Index>
        let name: String
    }

    static func resolve(_ text: String, values: [Placeholder: String]) -> String {
        var result = ""
        var cursor = text.startIndex
        for token in braceTokens(in: text) {
            guard let placeholder = Placeholder(rawValue: token.name.lowercased()),
                  let value = values[placeholder] else {
                continue
            }
            result.append(contentsOf: text[cursor..<token.range.lowerBound])
            result.append(contentsOf: value)
            cursor = token.range.upperBound
        }
        result.append(contentsOf: text[cursor...])
        return result
    }

    /// Rewrites recognized tokens in their canonical lowercase form ({UserName} becomes {username}), so the
    /// framework on the device can replace them with a simple literal match. Unknown tokens are untouched.
    static func normalizingTokens(_ text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        for token in braceTokens(in: text) {
            guard let placeholder = Placeholder(rawValue: token.name.lowercased()) else { continue }
            result.append(contentsOf: text[cursor..<token.range.lowerBound])
            result.append(contentsOf: placeholder.token)
            cursor = token.range.upperBound
        }
        result.append(contentsOf: text[cursor...])
        return result
    }

    /// Recognized placeholders in order of first appearance.
    static func placeholders(in text: String) -> [Placeholder] {
        var found: [Placeholder] = []
        for token in braceTokens(in: text) {
            if let placeholder = Placeholder(rawValue: token.name.lowercased()), !found.contains(placeholder) {
                found.append(placeholder)
            }
        }
        return found
    }

    /// Brace tokens such as "{usrname}" that look like placeholders but are not recognized.
    static func unknownTokens(in text: String) -> [String] {
        var unknown: [String] = []
        for token in braceTokens(in: text) where Placeholder(rawValue: token.name.lowercased()) == nil {
            let literal = "{\(token.name)}"
            if !unknown.contains(literal) {
                unknown.append(literal)
            }
        }
        return unknown
    }

    /// Every "{identifier}" sequence where identifier is ASCII letters, digits or underscore.
    static func braceTokens(in text: String) -> [BraceToken] {
        var tokens: [BraceToken] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "{" else {
                index = text.index(after: index)
                continue
            }
            let nameStart = text.index(after: index)
            var cursor = nameStart
            while cursor < text.endIndex, isIdentifierCharacter(text[cursor]) {
                cursor = text.index(after: cursor)
            }
            if cursor < text.endIndex, text[cursor] == "}", cursor > nameStart {
                let end = text.index(after: cursor)
                tokens.append(BraceToken(range: index..<end, name: String(text[nameStart..<cursor])))
                index = end
            } else {
                index = nameStart
            }
        }
        return tokens
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }
}
