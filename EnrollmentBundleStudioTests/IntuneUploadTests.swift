import CommonCrypto
import CryptoKit
import XCTest
@testable import EnrollmentBundleStudio

final class IntuneUploadTests: XCTestCase {
    func testPKCEChallengeMatchesTheRFCExample() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let token = PKCE.randomToken()
        XCTAssertEqual(token.count, 43)
        XCTAssertFalse(token.contains("+") || token.contains("/") || token.contains("="))
        XCTAssertNotEqual(token, PKCE.randomToken())
    }

    func testRedirectParsing() {
        let ok = RedirectParser.parse(requestHead: "GET /?code=abc123&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(ok?.code, "abc123")
        XCTAssertEqual(ok?.state, "xyz")
        let failure = RedirectParser.parse(requestHead: "GET /?error=access_denied&error_description=No%20way&state=xyz HTTP/1.1\r\n\r\n")
        XCTAssertEqual(failure?.error, "access_denied")
        XCTAssertEqual(failure?.errorDescription, "No way")
        XCTAssertNil(RedirectParser.parse(requestHead: "GET /favicon.ico HTTP/1.1\r\n\r\n"))
        XCTAssertNil(RedirectParser.parse(requestHead: "POST /?code=abc HTTP/1.1\r\n\r\n"))
        XCTAssertNil(RedirectParser.parse(requestHead: ""))
    }

    func testConnectionSettingsValidation() {
        XCTAssertTrue(IntuneConnectionSettings(tenantID: "contoso.onmicrosoft.com", clientID: UUID().uuidString).isValid)
        XCTAssertTrue(IntuneConnectionSettings(tenantID: UUID().uuidString, clientID: UUID().uuidString).isValid)
        XCTAssertNotNil(IntuneConnectionSettings(tenantID: "", clientID: UUID().uuidString).tenantIssue)
        XCTAssertNotNil(IntuneConnectionSettings(tenantID: "bad tenant/..", clientID: UUID().uuidString).tenantIssue)
        XCTAssertNotNil(IntuneConnectionSettings(tenantID: "contoso.com", clientID: "not-a-guid").clientIssue)
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(IntuneAuthenticator.formEncoded([("a", "x y&z=1"), ("b", "https://x")]), "a=x%20y%26z%3D1&b=https%3A%2F%2Fx")
    }

    func testEncryptedFileCanBeVerifiedAndDecrypted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntuneUploadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plain = Data((0..<100_003).map { UInt8($0 % 251) })
        let source = directory.appendingPathComponent("plain.pkg")
        let destination = directory.appendingPathComponent("encrypted.bin")
        try plain.write(to: source)

        let keys = IntuneFileEncryptor.Keys(encryptionKey: Data((0..<32).map { UInt8($0) }),
                                            macKey: Data((100..<132).map { UInt8($0) }),
                                            initializationVector: Data((200..<216).map { UInt8($0) }))
        let result = try IntuneFileEncryptor.encrypt(source: source, destination: destination, chunkSize: 4096, keys: keys)
        let file = try Data(contentsOf: destination)

        XCTAssertEqual(result.plainSize, Int64(plain.count))
        XCTAssertEqual(result.encryptedSize, Int64(file.count))
        let paddedLength = (plain.count / 16 + 1) * 16
        XCTAssertEqual(file.count, 32 + 16 + paddedLength)

        let mac = file.prefix(32)
        let body = file.dropFirst(32)
        XCTAssertEqual(Data(HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: keys.macKey))), Data(mac))
        XCTAssertEqual(result.info.mac, Data(mac).base64EncodedString())
        XCTAssertEqual(Data(body.prefix(16)), keys.initializationVector)
        XCTAssertEqual(result.info.fileDigest, Data(SHA256.hash(data: plain)).base64EncodedString())

        let cipher = Data(body.dropFirst(16))
        var decrypted = Data(count: cipher.count + 16)
        var moved = 0
        let capacity = decrypted.count
        let status = decrypted.withUnsafeMutableBytes { out in
            cipher.withUnsafeBytes { input in
                keys.encryptionKey.withUnsafeBytes { key in
                    keys.initializationVector.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, key.count, iv.baseAddress, input.baseAddress, cipher.count,
                                out.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        XCTAssertEqual(status, Int32(kCCSuccess))
        XCTAssertEqual(decrypted.prefix(moved), plain)

        XCTAssertEqual(result.info.json["profileIdentifier"] as? String, "ProfileVersion1")
        XCTAssertEqual(result.info.json["fileDigestAlgorithm"] as? String, "SHA256")
    }

    func testAppBodyDescribesAnUnmanagedPkgApp() throws {
        let request = IntuneUploadRequest(packageURL: URL(fileURLWithPath: "/tmp/Enrollment-1.0.0.pkg"), displayName: "Enrollment",
                                          description: "d", publisher: "Contoso", bundleIdentifier: "com.contoso.enrollment.bundle",
                                          bundleVersion: "1.0.0", minimumMacOS: "27.0")
        let body = IntunePackageUploader.appBody(request)
        XCTAssertEqual(body["@odata.type"] as? String, "#microsoft.graph.macOSPkgApp")
        XCTAssertEqual(body["fileName"] as? String, "Enrollment-1.0.0.pkg")
        XCTAssertEqual(body["primaryBundleId"] as? String, "com.contoso.enrollment.bundle")
        XCTAssertEqual(body["ignoreVersionDetection"] as? Bool, true)
        let included = try XCTUnwrap(body["includedApps"] as? [[String: Any]])
        XCTAssertEqual(included.first?["bundleVersion"] as? String, "1.0.0")
        let minimum = try XCTUnwrap(body["minimumSupportedOperatingSystem"] as? [String: Any])
        let trueKeys = minimum.filter { ($0.value as? Bool) == true }.map { $0.key }
        XCTAssertEqual(trueKeys, ["v26_0"], "Exactly one minimum version is true; 27 maps to the newest known value")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testMinimumOSKeys() {
        XCTAssertEqual(IntunePackageUploader.minimumOSKey(for: "26.0"), "v26_0")
        XCTAssertEqual(IntunePackageUploader.minimumOSKey(for: "27.0"), "v26_0")
        XCTAssertEqual(IntunePackageUploader.minimumOSKey(for: "14.0"), "v14_0")
    }

    func testBlockIdentifiersAndList() {
        XCTAssertEqual(IntunePackageUploader.blockID(0), Data("block-0000".utf8).base64EncodedString())
        XCTAssertEqual(IntunePackageUploader.blockID(12).count, IntunePackageUploader.blockID(0).count, "Block ids have equal length")
        XCTAssertEqual(IntunePackageUploader.percentEncoded("a+b/c="), "a%2Bb%2Fc%3D")
        XCTAssertEqual(IntunePackageUploader.blockListXML(["QQ==", "Qg=="]),
                       "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList><Latest>QQ==</Latest><Latest>Qg==</Latest></BlockList>")
    }

    func testGraphErrorMessageIsExtracted() {
        let data = Data(#"{"error":{"code":"Forbidden","message":"Insufficient privileges"}}"#.utf8)
        XCTAssertEqual(IntuneGraphClient.errorMessage(from: data), "Insufficient privileges")
    }
}

/// A transport that records requests and replies from a script, so the upload flow runs without a network.
private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    var requests: [(method: String, url: String)] = []
    var bodies: [Data?] = []
    var fileStates = ["azureStorageUriRequestPending", "azureStorageUriRequestSuccess", "commitFilePending", "commitFileSuccess"]

    func send(_ request: URLRequest, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let url = request.url?.absoluteString ?? ""
        requests.append((request.httpMethod ?? "GET", url))
        bodies.append(body)
        func reply(_ status: Int, _ json: String) -> (Data, HTTPURLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        if url.hasPrefix("https://storage.example/") { return reply(201, "") }
        let method = request.httpMethod ?? "GET"
        if method == "POST", url.hasSuffix("/mobileApps") { return reply(201, #"{"id":"app-1"}"#) }
        if method == "POST", url.hasSuffix("/contentVersions") { return reply(201, #"{"id":"1"}"#) }
        if method == "POST", url.hasSuffix("/files") { return reply(201, #"{"id":"file-1"}"#) }
        if method == "POST", url.hasSuffix("/commit") { return reply(200, "") }
        if method == "GET", url.hasSuffix("/files/file-1") {
            let state = fileStates.isEmpty ? "commitFileSuccess" : fileStates.removeFirst()
            return reply(200, #"{"id":"file-1","uploadState":"\#(state)","azureStorageUri":"https://storage.example/blob?sig=abc"}"#)
        }
        if method == "PATCH" { return reply(204, "") }
        return reply(404, #"{"error":{"message":"unexpected \#(method) \#(url)"}}"#)
    }
}

final class IntuneUploadFlowTests: XCTestCase {
    func testUploadRunsTheExpectedStepsWithoutTheNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntuneFlowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = directory.appendingPathComponent("Enrollment-1.0.0.pkg")
        try Data(repeating: 7, count: 5000).write(to: package)

        let transport = ScriptedTransport()
        var uploader = IntunePackageUploader(transport: transport)
        uploader.chunkSize = 2048
        uploader.sleep = { _ in }
        let request = IntuneUploadRequest(packageURL: package, displayName: "Enrollment", description: "d", publisher: "Contoso",
                                          bundleIdentifier: "com.contoso.enrollment.bundle", bundleVersion: "1.0.0", minimumMacOS: "26.0")
        let result = try await uploader.upload(request: request, token: "test-token") { _, _ in }

        XCTAssertEqual(result.appID, "app-1")
        let steps = transport.requests.map { "\($0.method) \($0.url.replacingOccurrences(of: "https://graph.microsoft.com/beta", with: ""))" }
        XCTAssertEqual(steps.first, "POST /deviceAppManagement/mobileApps")
        XCTAssertTrue(steps.contains("POST /deviceAppManagement/mobileApps/app-1/microsoft.graph.macOSPkgApp/contentVersions"))
        XCTAssertEqual(steps.filter { $0.hasPrefix("PUT https://storage.example/blob?sig=abc&comp=block&blockid=") }.count, 3, "5000 bytes plus 48 of header make three 2 KiB blocks")
        XCTAssertTrue(steps.contains("PUT https://storage.example/blob?sig=abc&comp=blocklist"))
        XCTAssertTrue(steps.contains { $0.hasSuffix("/commit") })
        XCTAssertEqual(steps.last, "PATCH /deviceAppManagement/mobileApps/app-1")
    }

    func testFailedStorageRequestDeletesTheHalfCreatedApp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntuneFlowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = directory.appendingPathComponent("p.pkg")
        try Data(repeating: 1, count: 100).write(to: package)

        let transport = ScriptedTransport()
        transport.fileStates = ["azureStorageUriRequestFailed"]
        var uploader = IntunePackageUploader(transport: transport)
        uploader.sleep = { _ in }
        let request = IntuneUploadRequest(packageURL: package, displayName: "x", description: "d", publisher: "p",
                                          bundleIdentifier: "com.x.y", bundleVersion: "1.0.0", minimumMacOS: "26.0")
        do {
            _ = try await uploader.upload(request: request, token: "t") { _, _ in }
            XCTFail("Expected a failure")
        } catch let error as IntuneError {
            XCTAssertEqual(error, .stateFailed("azureStorageUriRequestFailed"))
        }
        XCTAssertTrue(transport.requests.contains { $0.method == "DELETE" && $0.url.hasSuffix("/mobileApps/app-1") })
    }

    func testPackageLargerThanTheLimitIsRejectedBeforeAnyRequest() async {
        let transport = ScriptedTransport()
        let uploader = IntunePackageUploader(transport: transport)
        let request = IntuneUploadRequest(packageURL: URL(fileURLWithPath: "/nonexistent/missing.pkg"), displayName: "x", description: "d",
                                          publisher: "p", bundleIdentifier: "com.x.y", bundleVersion: "1.0.0", minimumMacOS: "26.0")
        do {
            _ = try await uploader.upload(request: request, token: "t") { _, _ in }
            XCTFail("Expected a failure")
        } catch {
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }
}
