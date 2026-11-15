import Foundation
import Network

/// A one-shot HTTP listener on the loopback interface that receives the browser's sign-in redirect
/// (http://localhost:<port>/?code=...). It accepts connections from this Mac only and stops after the first
/// request that carries a code or an error.
final class LoopbackRedirectServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "EnrollmentBundleStudio.loopback")
    // All mutable state below is touched only on `queue`.
    private var result: Result<AuthorizationResponse, Error>?
    private var continuation: CheckedContinuation<AuthorizationResponse, Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }

    /// Starts listening and returns the port the system assigned.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    if let port = self.listener.port?.rawValue, port != 0 {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: IntuneError.signInFailed("The local sign-in listener has no port."))
                    }
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: IntuneError.signInFailed("The local sign-in listener failed: \(error.localizedDescription)"))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// Waits for the redirect, up to `timeout` seconds.
    func waitForResponse(timeout: TimeInterval) async throws -> AuthorizationResponse {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthorizationResponse, Error>) in
            queue.async {
                if let result = self.result {
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(IntuneError.signInTimedOut))
                }
            }
        }
    }

    /// Ends a pending wait, for example when the administrator cancels.
    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    func stop() {
        listener.cancel()
    }

    private func finish(_ outcome: Result<AuthorizationResponse, Error>) {
        guard result == nil else { return }
        result = outcome
        continuation?.resume(with: outcome)
        continuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = RedirectParser.parse(requestHead: head)
            let status = response == nil ? "404 Not Found" : "200 OK"
            let page = response == nil
                ? "Not found."
                : "<html><body style=\"font-family:-apple-system,sans-serif;margin:3em\"><h2>You can close this window</h2><p>Return to Enrollment Bundle Studio to continue.</p></body></html>"
            let body = Data(page.utf8)
            var reply = Data("HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            reply.append(body)
            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            if let response, let self {
                self.finish(.success(response))
            }
        }
    }
}
