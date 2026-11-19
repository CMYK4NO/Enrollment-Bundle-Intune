import AppKit
import Foundation

/// The signed-in administrator for this run of the app. The token lives in memory only and is never written to disk.
/// Nothing signs in until an upload needs a token, and only when the Entra IDs have been entered in Settings.
@MainActor
final class AuthSession {
    static let shared = AuthSession()

    private var token: IntuneToken?
    /// The connection the token was issued for, so a token is never reused after the IDs are changed in Settings.
    private var tokenConnection: IntuneConnection?

    /// An access token for Microsoft Graph: the current one, a renewed one, or, when neither works, a new browser sign-in.
    /// `onBrowserSignIn` is called just before the browser opens, so the caller can say why.
    func validToken(onBrowserSignIn: () -> Void = {}) async throws -> String {
        let connection = IntuneConnectionStore.shared.load()
        guard connection.isComplete else { throw IntuneError.notConfigured }
        if tokenConnection != connection { token = nil }

        let authenticator = IntuneAuthenticator(connection: connection)
        if let token, token.isValid() { return token.accessToken }
        if let refreshToken = token?.refreshToken, let renewed = try? await authenticator.refresh(refreshToken) {
            token = renewed
            return renewed.accessToken
        }
        onBrowserSignIn()
        let signedIn = try await authenticator.signIn()
        token = signedIn
        tokenConnection = connection
        // The browser is in front after the sign-in; bring the app back so its window is where the administrator looks.
        NSApp.activate(ignoringOtherApps: true)
        return signedIn.accessToken
    }
}
