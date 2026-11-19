import Foundation

/// An sRGB colour stored in project.json as a readable "#RRGGBB" string.
struct HexColor: Codable, Equatable {
    var hex: String

    init(hex: String) {
        self.hex = hex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        hex = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// Channel values from 0 to 1, or nil when the string is not a valid #RRGGBB value.
    var components: (red: Double, green: Double, blue: Double)? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6,
              value.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let number = UInt32(value, radix: 16) else {
            return nil
        }
        return (
            Double((number >> 16) & 0xFF) / 255.0,
            Double((number >> 8) & 0xFF) / 255.0,
            Double(number & 0xFF) / 255.0
        )
    }

    var isValid: Bool { components != nil }

    static func from(red: Double, green: Double, blue: Double) -> HexColor {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return HexColor(hex: String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue)))
    }
}
