import Foundation

/// Calls Microsoft Graph (beta, Intune app management) with a bearer token held in memory.
struct IntuneGraphClient {
    let transport: HTTPTransport
    let token: String
    var baseURL = "https://graph.microsoft.com/beta"

    @discardableResult
    func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else { throw IntuneError.unexpectedResponse("The request address is not valid.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var payload: Data?
        if let body {
            payload = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.send(request, body: payload)
        guard (200..<300).contains(response.statusCode) else {
            throw IntuneError.http(status: response.statusCode, message: Self.errorMessage(from: data))
        }
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntuneError.unexpectedResponse("The reply was not a JSON object.")
        }
        return object
    }

    static func errorMessage(from data: Data) -> String {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return String(message.prefix(300))
        }
        return String((String(data: data, encoding: .utf8) ?? "no details").prefix(300))
    }
}

struct IntuneUploadRequest: Equatable {
    var packageURL: URL
    var displayName: String
    var description: String
    var publisher: String
    /// Package identifier and version of the installer package.
    var bundleIdentifier: String
    var bundleVersion: String
    /// Minimum macOS version, for example "26.0".
    var minimumMacOS: String
}

struct IntuneUploadResult: Equatable {
    let appID: String
    let portalURL: URL
}

/// Uploads an unsigned flat package as an Intune "macOS app (PKG)" (the unmanaged PKG app type, which accepts
/// unsigned packages). Steps: create the app, create a content version and file entry, encrypt the package,
/// upload it to Azure Storage in blocks, commit it, then publish the content version.
struct IntunePackageUploader {
    var transport: HTTPTransport = URLSessionTransport()
    var chunkSize = 6 * 1024 * 1024
    var pollInterval: TimeInterval = 2
    var maximumPolls = 90
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }

    static let maximumPackageBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let knownMinimumOSKeys = ["v10_7", "v10_8", "v10_9", "v10_10", "v10_11", "v10_12", "v10_13", "v10_14", "v10_15",
                                     "v11_0", "v12_0", "v13_0", "v14_0", "v15_0", "v26_0"]

    typealias Progress = @Sendable (String, Double?) -> Void

    func upload(request: IntuneUploadRequest, token: String, progress: Progress) async throws -> IntuneUploadResult {
        let attributes = try? FileManager.default.attributesOfItem(atPath: request.packageURL.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value else {
            throw IntuneError.fileProblem("The package file cannot be read: \(request.packageURL.path)")
        }
        guard size <= Self.maximumPackageBytes else { throw IntuneError.tooLarge }

        let client = IntuneGraphClient(transport: transport, token: token)
        progress("Creating the app in Intune…", nil)
        let app = try await client.request("POST", "/deviceAppManagement/mobileApps", body: Self.appBody(request))
        guard let appID = app["id"] as? String else { throw IntuneError.unexpectedResponse("The new app has no id.") }

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("EnrollmentBundleStudio-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try await uploadContent(client: client, appID: appID, request: request, encryptedURL: temporary, progress: progress)
        } catch {
            // Do not leave an empty app behind. Best effort.
            _ = try? await client.request("DELETE", "/deviceAppManagement/mobileApps/\(appID)")
            throw error
        }
        let portal = URL(string: "https://intune.microsoft.com/#view/Microsoft_Intune_Apps/SettingsMenu/~/0/appId/\(appID)")
        return IntuneUploadResult(appID: appID, portalURL: portal ?? URL(string: "https://intune.microsoft.com")!)
    }

    private func uploadContent(client: IntuneGraphClient, appID: String, request: IntuneUploadRequest,
                               encryptedURL: URL, progress: Progress) async throws {
        let base = "/deviceAppManagement/mobileApps/\(appID)/microsoft.graph.macOSPkgApp/contentVersions"
        let version = try await client.request("POST", base, body: [:])
        guard let versionID = version["id"] as? String else { throw IntuneError.unexpectedResponse("The content version has no id.") }

        try Task.checkCancellation()
        progress("Encrypting the package…", nil)
        let encrypted = try IntuneFileEncryptor.encrypt(source: request.packageURL, destination: encryptedURL)

        let filesPath = "\(base)/\(versionID)/files"
        let file = try await client.request("POST", filesPath, body: [
            "@odata.type": "#microsoft.graph.mobileAppContentFile",
            "name": request.packageURL.lastPathComponent,
            "size": encrypted.plainSize,
            "sizeEncrypted": encrypted.encryptedSize,
            "manifest": NSNull(),
            "isDependency": false
        ])
        guard let fileID = file["id"] as? String else { throw IntuneError.unexpectedResponse("The file entry has no id.") }
        let filePath = "\(filesPath)/\(fileID)"

        progress("Waiting for Intune to prepare storage…", nil)
        let ready = try await waitForState(client: client, path: filePath, success: "azureStorageUriRequestSuccess", what: "the storage address")
        guard let storageURI = ready["azureStorageUri"] as? String else {
            throw IntuneError.unexpectedResponse("Intune returned no storage address.")
        }

        try await uploadBlocks(to: storageURI, file: encryptedURL, totalBytes: encrypted.encryptedSize, progress: progress)

        progress("Committing the file…", nil)
        try await client.request("POST", "\(filePath)/commit", body: ["fileEncryptionInfo": encrypted.info.json])
        _ = try await waitForState(client: client, path: filePath, success: "commitFileSuccess", what: "the file commit")

        progress("Publishing the app…", nil)
        try await client.request("PATCH", "/deviceAppManagement/mobileApps/\(appID)", body: [
            "@odata.type": "#microsoft.graph.macOSPkgApp",
            "committedContentVersion": versionID
        ])
    }

    private func waitForState(client: IntuneGraphClient, path: String, success: String, what: String) async throws -> [String: Any] {
        for _ in 0..<maximumPolls {
            try Task.checkCancellation()
            let file = try await client.request("GET", path)
            let state = (file["uploadState"] as? String) ?? ""
            if state == success { return file }
            let lowered = state.lowercased()
            if lowered.contains("failed") || lowered.contains("timedout") { throw IntuneError.stateFailed(state) }
            try await sleep(pollInterval)
        }
        throw IntuneError.timedOut(what)
    }

    private func uploadBlocks(to storageURI: String, file: URL, totalBytes: Int64, progress: Progress) async throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var ids: [String] = []
        var sent: Int64 = 0
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            let id = Self.blockID(ids.count)
            ids.append(id)
            try await putBlob(storageURI + "&comp=block&blockid=" + Self.percentEncoded(id), body: chunk, blockBlob: true)
            sent += Int64(chunk.count)
            progress("Uploading the package…", totalBytes > 0 ? Double(sent) / Double(totalBytes) : nil)
        }
        try await putBlob(storageURI + "&comp=blocklist", body: Data(Self.blockListXML(ids).utf8), blockBlob: false)
    }

    private func putBlob(_ address: String, body: Data, blockBlob: Bool) async throws {
        guard let url = URL(string: address) else { throw IntuneError.unexpectedResponse("The storage address is not valid.") }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if blockBlob { request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type") }
        let (data, response) = try await transport.send(request, body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw IntuneError.http(status: response.statusCode, message: String((String(data: data, encoding: .utf8) ?? "storage error").prefix(200)))
        }
    }

    // MARK: Pure helpers (unit tested)

    static func blockID(_ index: Int) -> String {
        Data(String(format: "block-%04d", index).utf8).base64EncodedString()
    }

    static func percentEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    static func blockListXML(_ ids: [String]) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList>" + ids.map { "<Latest>\($0)</Latest>" }.joined() + "</BlockList>"
    }

    /// Graph lists macOS versions only up to 26.0, so macOS 27 maps to the newest known value.
    static func minimumOSKey(for version: String) -> String {
        let major = Int(version.split(separator: ".").first ?? "") ?? 26
        return major >= 26 ? "v26_0" : "v\(major)_0"
    }

    static func minimumOperatingSystem(for version: String) -> [String: Any] {
        let key = minimumOSKey(for: version)
        var object: [String: Any] = ["@odata.type": "microsoft.graph.macOSMinimumOperatingSystem"]
        for name in knownMinimumOSKeys { object[name] = (name == key) }
        return object
    }

    static func appBody(_ request: IntuneUploadRequest) -> [String: Any] {
        [
            "@odata.type": "#microsoft.graph.macOSPkgApp",
            "displayName": request.displayName,
            "description": request.description,
            "publisher": request.publisher,
            "isFeatured": false,
            "fileName": request.packageURL.lastPathComponent,
            "primaryBundleId": request.bundleIdentifier,
            "primaryBundleVersion": request.bundleVersion,
            "includedApps": [[
                "@odata.type": "#microsoft.graph.macOSIncludedApp",
                "bundleId": request.bundleIdentifier,
                "bundleVersion": request.bundleVersion
            ]],
            "ignoreVersionDetection": true,
            "minimumSupportedOperatingSystem": minimumOperatingSystem(for: request.minimumMacOS)
        ]
    }
}
