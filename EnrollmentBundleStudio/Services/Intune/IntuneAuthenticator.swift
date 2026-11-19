import AppKit
import Foundation

/// Sends HTTP requests. A protocol so tests never touch the network.
protocol HTTPTransport {
    /// Sends the request, with `body` as the upload body when given.
    func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        if let body {
            (data, response) = try await session.upload(for: request, from: body)
        } else {
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw IntuneError.unexpectedResponse("No HTTP response.")
        }
        return (data, http)
    }
}

/// Signs the administrator in with the system's default browser (authorization code flow with PKCE,
/// loopback redirect). The access token is returned to the caller and kept in memory only; nothing is stored.
struct IntuneAuthenticator {
    /// `offline_access` lets the running app renew the access token without opening the browser again.
    static let scope = "https://graph.microsoft.com/DeviceManagementApps.ReadWrite.All offline_access"

    /// The tenant and app registration to sign in to. Both are validated GUIDs by the time they get here.
    let connection: IntuneConnection

    var authority: String { "https://login.microsoftonline.com/\(connection.tenantID)/oauth2/v2.0" }

    var transport: HTTPTransport = URLSessionTransport()
    /// Opens a URL in the default browser. Replaced in tests.
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    func signIn() async throws -> IntuneToken {
        let verifier = PKCE.randomToken()
        let state = PKCE.randomToken()
        let server = try LoopbackRedirectServer(expectedState: state)
        defer { server.stop() }
        let port = try await server.start()
        let redirectURI = "http://localhost:\(port)"

        guard var components = URLComponents(string: "\(authority)/authorize") else {
            throw IntuneError.signInFailed("The sign-in address could not be built.")
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: connection.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authorizeURL = components.url else { throw IntuneError.signInFailed("The sign-in address could not be built.") }
        guard openURL(authorizeURL) else { throw IntuneError.signInFailed("The default browser could not be opened.") }

        let response = try await withTaskCancellationHandler {
            try await server.waitForResponse(timeout: 180)
        } onCancel: {
            server.cancel()
        }
        if let error = response.error {
            throw IntuneError.signInFailed(response.errorDescription ?? error)
        }
        guard response.state == state else { throw IntuneError.signInFailed("The sign-in response did not match the request.") }
        guard let code = response.code else { throw IntuneError.signInFailed("No authorization code was returned.") }

        return try await requestToken([
            ("client_id", connection.clientID),
            ("scope", Self.scope),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier)
        ])
    }

    /// Gets a new access token from a refresh token, without opening the browser.
    func refresh(_ refreshToken: String) async throws -> IntuneToken {
        try await requestToken([
            ("client_id", connection.clientID),
            ("scope", Self.scope),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token")
        ])
    }

    private func requestToken(_ pairs: [(String, String)]) async throws -> IntuneToken {
        guard let url = URL(string: "\(authority)/token") else {
            throw IntuneError.signInFailed("The sign-in address could not be built.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, http) = try await transport.send(request, body: Data(Self.formEncoded(pairs).utf8))
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode), let token = object?["access_token"] as? String, !token.isEmpty else {
            let description = (object?["error_description"] as? String) ?? (object?["error"] as? String) ?? "HTTP \(http.statusCode)"
            throw IntuneError.signInFailed(String(description.prefix(300)))
        }
        let lifetime = (object?["expires_in"] as? Double) ?? Double(object?["expires_in"] as? String ?? "") ?? 3600
        return IntuneToken(
            accessToken: token,
            refreshToken: object?["refresh_token"] as? String,
            expiresAt: Date().addingTimeInterval(lifetime)
        )
    }

    static func formEncoded(_ pairs: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        return pairs.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }
}
