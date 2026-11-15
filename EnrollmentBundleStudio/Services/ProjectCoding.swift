import Foundation

/// Errors raised while reading or writing a project package.
enum ProjectFileError: LocalizedError, Equatable {
    case notAProjectPackage
    case missingProjectFile
    case invalidProjectFile(String)
    case unsupportedSchema(Int)
    case newerSchemaUnreadable(Int)
    case migrationRequired(Int)
    case readOnlyProject(Int)
    case unexpectedItem(String)
    case unsafeAssetPath(String)

    var errorDescription: String? {
        switch self {
        case .notAProjectPackage:
            return "This item is not an Enrollment Bundle Studio project folder."
        case .missingProjectFile:
            return "The project folder does not contain a readable project.json file."
        case .invalidProjectFile(let detail):
            return "project.json could not be read. \(detail)"
        case .unsupportedSchema(let version):
            return "The project uses schema version \(version), which this version of \(AppInfo.displayName) cannot open."
        case .newerSchemaUnreadable(let version):
            return "The project uses schema version \(version), which is newer than this application supports (\(AppInfo.currentSchemaVersion))."
        case .migrationRequired(let version):
            return "No migration exists from schema version \(version), so the project cannot be upgraded."
        case .readOnlyProject(let version):
            return "This project uses newer schema version \(version) and is open read-only. It was not saved, so the original stays intact."
        case .unexpectedItem(let name):
            return "The project contains a file named \"\(name)\" where a folder was expected."
        case .unsafeAssetPath(let path):
            return "Refused to use the file path \"\(path)\" because it points outside the project's asset folders."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .newerSchemaUnreadable, .readOnlyProject:
            return "Open the project with a newer version of \(AppInfo.displayName)."
        case .unexpectedItem:
            return "Rename or remove the file in Finder, then try again."
        case .invalidProjectFile:
            return "Check project.json in a text editor, or restore it from a backup."
        case .notAProjectPackage, .missingProjectFile, .unsupportedSchema, .migrationRequired, .unsafeAssetPath:
            return nil
        }
    }
}

/// Result of reading project.json.
struct ProjectLoadResult {
    var project: EnrollmentProject
    var isReadOnly: Bool
    var notes: [String]
    /// Set when the file was upgraded from an older schema.
    var migratedFromVersion: Int? = nil
    var migrationSummary: [String] = []
}

/// Encoding and decoding rules for project.json.
enum ProjectCoding {
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// ISO 8601 output has no fractional seconds, so timestamps are truncated to keep round trips exact.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func encode(_ project: EnrollmentProject) throws -> Data {
        var data = try makeEncoder().encode(project)
        data.append(0x0A)
        return data
    }

    /// Reads project.json, checking the schema version before full decoding.
    static func load(_ data: Data) throws -> ProjectLoadResult {
        let decoder = makeDecoder()
        let probe: SchemaProbe
        do {
            probe = try decoder.decode(SchemaProbe.self, from: data)
        } catch {
            throw ProjectFileError.invalidProjectFile(describe(error))
        }

        if probe.schemaVersion < AppInfo.minimumSupportedSchemaVersion {
            throw ProjectFileError.unsupportedSchema(probe.schemaVersion)
        }

        if probe.schemaVersion > AppInfo.currentSchemaVersion {
            do {
                let project = try decoder.decode(EnrollmentProject.self, from: data)
                return ProjectLoadResult(
                    project: project,
                    isReadOnly: true,
                    notes: ["This project was saved with newer schema version \(probe.schemaVersion). It is open read-only and will not be overwritten."]
                )
            } catch {
                throw ProjectFileError.newerSchemaUnreadable(probe.schemaVersion)
            }
        }

        if probe.schemaVersion < AppInfo.currentSchemaVersion {
            let migration = try ProjectMigrator.migrate(data, from: probe.schemaVersion)
            do {
                let project = try decoder.decode(EnrollmentProject.self, from: ProjectMigrator.fillingMissingDefaults(migration.data))
                return ProjectLoadResult(
                    project: project,
                    isReadOnly: false,
                    notes: [],
                    migratedFromVersion: migration.fromVersion,
                    migrationSummary: migration.summary
                )
            } catch {
                throw ProjectFileError.invalidProjectFile("After migration from schema \(probe.schemaVersion): \(describe(error))")
            }
        }

        do {
            let project = try decoder.decode(EnrollmentProject.self, from: ProjectMigrator.fillingMissingDefaults(data))
            return ProjectLoadResult(project: project, isReadOnly: false, notes: [])
        } catch {
            throw ProjectFileError.invalidProjectFile(describe(error))
        }
    }

    /// Short, administrator-readable description of a decoding failure.
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        func path(_ context: DecodingError.Context) -> String {
            let components = context.codingPath.map { key -> String in
                if let index = key.intValue {
                    return "[\(index)]"
                }
                return key.stringValue
            }
            return components.isEmpty ? "the top level" : components.joined(separator: ".")
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "Missing key \"\(key.stringValue)\" at \(path(context))."
        case .typeMismatch(_, let context):
            return "Unexpected value type at \(path(context))."
        case .valueNotFound(_, let context):
            return "Missing value at \(path(context))."
        case .dataCorrupted(let context):
            return "Invalid data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
