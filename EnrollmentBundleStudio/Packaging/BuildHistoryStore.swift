import Foundation

struct BuildRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var builtAt: Date
    var packagePath: String
    var reportPath: String
    var sha256: String
    var sizeBytes: Int64
    var packageIdentifier: String
    var packageVersion: String
    var bundleVersion: String
    var verificationPassed: Bool
    var warningCount: Int
    var applicationVersion: String
}

/// Build history per project, kept in the administrator's Application Support folder. It is not stored in
/// the project package, so building never edits the open document, and packages stay in the output folder.
struct BuildHistoryStore {
    let directory: URL

    static func standard() throws -> BuildHistoryStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return BuildHistoryStore(directory: base.appendingPathComponent("Enrollment Bundle Studio/BuildHistory", isDirectory: true))
    }

    func fileURL(for projectID: UUID) -> URL {
        directory.appendingPathComponent("\(projectID.uuidString).json")
    }

    func records(for projectID: UUID) -> [BuildRecord] {
        guard let data = try? Data(contentsOf: fileURL(for: projectID)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([BuildRecord].self, from: data)) ?? []).sorted { $0.builtAt > $1.builtAt }
    }

    func append(_ record: BuildRecord, for projectID: UUID) throws {
        try save(records(for: projectID) + [record], for: projectID)
    }

    func remove(recordID: UUID, for projectID: UUID) throws {
        try save(records(for: projectID).filter { $0.id != recordID }, for: projectID)
    }

    private func save(_ records: [BuildRecord], for projectID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records.sorted { $0.builtAt > $1.builtAt }).write(to: fileURL(for: projectID), options: .atomic)
    }
}
