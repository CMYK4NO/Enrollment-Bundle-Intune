import Foundation

/// The swiftDialog command-file vocabulary. Mirrors lib/dialog.sh exactly, so the live preview in the app
/// exercises the same protocol the device uses.
enum DialogCommand {
    static func status(for status: TaskStatus) -> String {
        switch status {
        case .waiting, .running: return "wait"
        case .complete: return "success"
        case .completeWithWarnings: return "error"
        case .failed, .timedOut: return "fail"
        case .pending, .skipped: return "pending"
        }
    }

    /// Newlines and commas would split a command-file value, so they become spaces (one_line in dialog.sh).
    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: ",", with: " ")
    }

    static func listItem(index: Int, status: TaskStatus, text: String) -> String {
        "listitem: index: \(index), status: \(self.status(for: status)), statustext: \(oneLine(text))"
    }

    static func progress(_ value: Int) -> String {
        "progress: \(value)"
    }

    static func progressText(_ text: String) -> String {
        "progresstext: \(oneLine(text))"
    }

    /// Message text keeps line breaks as the two characters \n, which swiftDialog renders as new lines.
    static func message(_ text: String) -> String {
        "message: " + text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\\n")
    }

    static func buttonText(_ text: String) -> String {
        "button1text: \(oneLine(text))"
    }

    static let buttonEnable = "button1: enable"
    static let buttonDisable = "button1: disable"
    static let quit = "quit:"

    static func icon(_ value: String) -> String {
        "icon: \(value)"
    }
}
