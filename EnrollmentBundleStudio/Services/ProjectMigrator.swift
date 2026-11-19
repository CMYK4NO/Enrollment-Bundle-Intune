import Foundation

struct MigrationResult {
    let data: Data
    let fromVersion: Int
    let toVersion: Int
    let summary: [String]
}

/// Upgrades project.json from older schema versions, one step at a time, on the JSON level.
/// Working on dictionaries (not Codable types) means old files never need old Swift types.
enum ProjectMigrator {
    typealias Step = (inout [String: Any], inout [String]) throws -> Void

    /// Step that upgrades from the key version to key + 1.
    static let steps: [Int: Step] = [
        1: ProjectMigrator.migrateV1ToV2,
        2: ProjectMigrator.migrateV2ToV3,
        3: ProjectMigrator.migrateV3ToV4
    ]

    /// Adds settings introduced without a schema change when a project saved by an earlier build lacks them.
    static func fillingMissingDefaults(_ data: Data) -> Data {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return data
        }
        var changed = false
        if var settings = object["settings"] as? [String: Any], settings["enrollmentWindowHours"] == nil {
            settings["enrollmentWindowHours"] = ProjectSettings.defaultEnrollmentWindowHours
            object["settings"] = settings
            changed = true
        }
        if var branding = object["branding"] as? [String: Any], branding["blurScreen"] == nil {
            branding["blurScreen"] = true
            object["branding"] = branding
            changed = true
        }
        if var branding = object["branding"] as? [String: Any],
           branding["completionCommand"] == nil || branding["completionCommandRunsAsUser"] == nil {
            if branding["completionCommand"] == nil { branding["completionCommand"] = "" }
            if branding["completionCommandRunsAsUser"] == nil { branding["completionCommandRunsAsUser"] = true }
            object["branding"] = branding
            changed = true
        }
        guard changed else { return data }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? data
    }

    static func backupFileName(forSchema version: Int) -> String {
        "project.schema-\(version).backup.json"
    }

    static func migrate(_ data: Data, from version: Int, to target: Int = AppInfo.currentSchemaVersion) throws -> MigrationResult {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectFileError.invalidProjectFile("The top level is not a JSON object.")
        }
        var summary: [String] = []
        var current = version
        while current < target {
            guard let step = steps[current] else {
                throw ProjectFileError.migrationRequired(current)
            }
            try step(&object, &summary)
            current += 1
            object["schemaVersion"] = current
        }
        let migrated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return MigrationResult(data: migrated, fromVersion: version, toVersion: current, summary: summary)
    }

    /// Schema 2 adds `sourceWasExecutable` and `importedAt` to every script.
    static func migrateV1ToV2(_ object: inout [String: Any], _ summary: inout [String]) throws {
        let fallbackDate = (object["modifiedAt"] as? String) ?? (object["createdAt"] as? String) ?? "1970-01-01T00:00:00Z"
        var scripts = (object["scripts"] as? [[String: Any]]) ?? []
        for index in scripts.indices {
            if scripts[index]["sourceWasExecutable"] == nil {
                scripts[index]["sourceWasExecutable"] = false
            }
            if scripts[index]["importedAt"] == nil {
                scripts[index]["importedAt"] = fallbackDate
            }
        }
        object["scripts"] = scripts
        summary.append(scripts.isEmpty
            ? "Schema 1 → 2: no scripts needed changes."
            : "Schema 1 → 2: added import metadata to \(scripts.count) script(s).")
    }

    /// Schema 3 adds an optional `installer` to applications. Existing data needs no change; the version bump
    /// makes older app versions open schema 3 projects read-only so they never drop installer references.
    static func migrateV2ToV3(_ object: inout [String: Any], _ summary: inout [String]) throws {
        summary.append("Schema 2 → 3: applications can now reference an installer package. No existing data changed.")
    }

    /// Schema 4 adds the onboarding flag setting.
    static func migrateV3ToV4(_ object: inout [String: Any], _ summary: inout [String]) throws {
        var settings = (object["settings"] as? [String: Any]) ?? [:]
        if settings["onboardingFlagPath"] == nil {
            settings["onboardingFlagPath"] = ProjectSettings.defaultOnboardingFlagPath
        }
        if settings["enrollmentWindowHours"] == nil {
            settings["enrollmentWindowHours"] = ProjectSettings.defaultEnrollmentWindowHours
        }
        object["settings"] = settings
        summary.append("Schema 3 → 4: added the onboarding flag (\(ProjectSettings.defaultOnboardingFlagPath)) and a \(ProjectSettings.defaultEnrollmentWindowHours)-hour enrollment window.")
    }
}
