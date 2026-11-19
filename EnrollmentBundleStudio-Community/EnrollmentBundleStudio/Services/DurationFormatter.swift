import Foundation

enum DurationFormatter {
    /// Compact duration such as "45 s", "15 min" or "2 h 30 min".
    static func format(seconds: Int) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 {
            return "\(clamped) s"
        }
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let remainingSeconds = clamped % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) h") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if remainingSeconds > 0 && hours == 0 { parts.append("\(remainingSeconds) s") }
        return parts.joined(separator: " ")
    }
}
