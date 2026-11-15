import Foundation

enum ExitCodeParser {
    /// Parses "0, 2" into [0, 2]. Returns nil for empty input or any value outside 0...255.
    static func parse(_ text: String) -> [Int]? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var codes: [Int] = []
        for part in parts {
            guard let code = Int(part), (0...255).contains(code) else { return nil }
            if !codes.contains(code) {
                codes.append(code)
            }
        }
        return codes.isEmpty ? nil : codes
    }
}
