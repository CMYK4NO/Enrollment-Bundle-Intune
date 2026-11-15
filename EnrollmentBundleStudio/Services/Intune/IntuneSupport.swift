import CryptoKit
import Foundation

/// Errors from signing in to Microsoft Entra and uploading to Intune. Messages never contain tokens.
enum IntuneError: Error, LocalizedError, Equatable {
    case invalidSettings(String)
    case signInFailed(String)
    case signInTimedOut
    case http(status: Int, message: String)
    case unexpectedResponse(String)
    case fileProblem(String)
    case tooLarge
    case stateFailed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .invalidSettings(let text): return text
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

/// The Microsoft Entra application used to sign in. A public client has no secret, so nothing here is confidential.
/// These values live in the app's preferences, never in a project file.
struct IntuneConnectionSettings: Equatable {
    var tenantID: String
    var clientID: String

    var trimmedTenant: String { tenantID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedClient: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A GUID or a domain name such as contoso.onmicrosoft.com.
    var tenantIssue: String? {
        let tenant = trimmedTenant
        if tenant.isEmpty { return "Enter the directory (tenant) ID." }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        if tenant.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use the tenant GUID or a domain name such as contoso.onmicrosoft.com."
        }
        return nil
    }

    var clientIssue: String? {
        let client = trimmedClient
        if client.isEmpty { return "Enter the application (client) ID." }
        return UUID(uuidString: client) == nil ? "The application (client) ID is a GUID." : nil
    }

    var isValid: Bool { tenantIssue == nil && clientIssue == nil }
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
