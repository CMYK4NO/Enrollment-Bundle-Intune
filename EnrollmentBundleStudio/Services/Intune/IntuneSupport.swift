import CryptoKit
import Foundation

/// Errors from signing in to Microsoft Entra and uploading to Intune. Messages never contain tokens.
enum IntuneError: Error, LocalizedError, Equatable {
    case signInFailed(String)
    case signInTimedOut
    case http(status: Int, message: String)
    case unexpectedResponse(String)
    case fileProblem(String)
    case tooLarge
    case stateFailed(String)
    case timedOut(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Microsoft Entra is not configured. Enter your tenant ID and client ID in Settings first."
        case .signInFailed(let text): return "Sign-in failed: \(text)"
        case .signInTimedOut: return "Sign-in timed out. No sign-in was completed in the browser within 3 minutes."
        case .http(let status, let message): return "Microsoft returned HTTP \(status): \(message)"
        case .unexpectedResponse(let text): return "Unexpected response from Microsoft: \(text)"
        case .fileProblem(let text): return text
        case .tooLarge: return "The package is larger than 2 GB, the limit for macOS apps in Intune."
        case .stateFailed(let text): return "Intune reported a failure: \(text)"
        case .timedOut(let text): return "Timed out waiting for Intune: \(text)"
        }
    }
}

/// The Microsoft Entra app registration used to sign in. A public client has no secret, and the tenant ID and
/// application (client) ID are identifiers, not credentials. Each administrator enters their own in Settings;
/// nothing is built in. Both empty means "not configured": uploading is unavailable, everything else works.
struct IntuneConnection: Codable, Equatable {
    var tenantID: String = ""
    var clientID: String = ""

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nothing entered yet.
    var isEmpty: Bool { Self.trimmed(tenantID).isEmpty && Self.trimmed(clientID).isEmpty }

    /// Both IDs are valid GUIDs, so a sign-in can be attempted.
    var isComplete: Bool { Self.idIssue(tenantID) == nil && Self.idIssue(clientID) == nil }

    /// Settings can be saved when both IDs are valid, or when both are empty to clear them.
    var isSavable: Bool { isEmpty || isComplete }

    /// The same values trimmed and lowercased, which is how they are stored and compared.
    var normalized: IntuneConnection {
        IntuneConnection(tenantID: Self.trimmed(tenantID).lowercased(), clientID: Self.trimmed(clientID).lowercased())
    }

    static func idIssue(_ value: String) -> String? {
        let text = trimmed(value)
        if text.isEmpty { return "Required." }
        if UUID(uuidString: text) == nil { return "Must be a GUID, for example 00000000-0000-0000-0000-000000000000." }
        return nil
    }
}

/// Keeps the Entra IDs in the user's preferences on this Mac. They are not part of a project, a configuration
/// export or a package.
struct IntuneConnectionStore: @unchecked Sendable {
    static let shared = IntuneConnectionStore()
    static let storageKey = "intuneConnection.v1"

    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    /// The saved connection, or an empty one when nothing valid has been saved.
    func load() -> IntuneConnection {
        guard let data = preferences.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode(IntuneConnection.self, from: data),
              saved.isComplete
        else {
            return IntuneConnection()
        }
        return saved.normalized
    }

    /// Saves a complete connection, or forgets it when both IDs are empty. Throws for anything in between.
    func save(_ connection: IntuneConnection) throws {
        if connection.isEmpty {
            preferences.removeObject(forKey: Self.storageKey)
        } else if connection.isComplete {
            preferences.set(try JSONEncoder().encode(connection.normalized), forKey: Self.storageKey)
        } else {
            throw IntuneError.notConfigured
        }
    }
}

/// The result of a sign-in. Kept in memory only for the running app; nothing is written to disk.
struct IntuneToken: Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    /// True while the access token is still good for at least two more minutes.
    func isValid(at date: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(date) > 120
    }
}

/// PKCE (RFC 7636) helpers for the browser sign-in.
enum PKCE {
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 32 random bytes from CryptoKit's secure generator, base64url encoded.
    static func randomToken() -> String {
        let key = SymmetricKey(size: .bits256)
        return base64URL(key.withUnsafeBytes { Data($0) })
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// The result of the browser redirect: either a code or an error, plus the state that was sent.
struct AuthorizationResponse: Equatable {
    var code: String?
    var state: String?
    var error: String?
    var errorDescription: String?
}

enum RedirectParser {
    /// Parses the request line of the browser's redirect, for example "GET /?code=abc&state=xyz HTTP/1.1".
    /// Returns nil for requests that carry no query, such as favicon requests.
    static func parse(requestHead: String) -> AuthorizationResponse? {
        guard let line = requestHead.components(separatedBy: "\r\n").first ?? requestHead.components(separatedBy: "\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let components = URLComponents(string: "http://localhost" + String(parts[1])),
              let items = components.queryItems, !items.isEmpty else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let response = AuthorizationResponse(code: value("code"), state: value("state"), error: value("error"), errorDescription: value("error_description"))
        return response.code == nil && response.error == nil ? nil : response
    }
}
