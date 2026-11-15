import CryptoKit
import Foundation

enum Hashing {
    /// Lowercase hexadecimal SHA-256, the same format `shasum -a 256` prints.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
