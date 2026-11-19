import Foundation

/// The runtime settings that are edited in the app-wide Settings window.
///
/// They are the starting values for every new project and can be applied to an open project. A project
/// keeps its own copy in `project.json` (`ProjectSettings`), so exports, generated frameworks and packages
/// always carry the settings the project was saved with.
struct RuntimeSettingsDefaults: Codable, Equatable {
    var windowWidth: Int
    var windowHeight: Int
    var lockCompletionButtonUntilRequiredComplete: Bool
    var defaultTaskTimeoutSeconds: Int
    var maximumEnrollmentDurationSeconds: Int
    var applicationInstallStrategy: ApplicationInstallStrategy
    var scriptExecutionStrategy: ScriptExecutionStrategy
    var swiftDialogPath: String
    var swiftDialogMinimumVersion: String
    var onboardingFlagPath: String
    var enrollmentWindowHours: Int
    var installLocation: String
    var stateDirectory: String
    var debugLogging: Bool
    /// See `ProjectSettings.detectionAppDirectory`. Optional so defaults saved earlier still decode.
    var detectionAppDirectory: String?

    init(_ settings: ProjectSettings) {
        windowWidth = settings.windowWidth
        windowHeight = settings.windowHeight
        lockCompletionButtonUntilRequiredComplete = settings.lockCompletionButtonUntilRequiredComplete
        defaultTaskTimeoutSeconds = settings.defaultTaskTimeoutSeconds
        maximumEnrollmentDurationSeconds = settings.maximumEnrollmentDurationSeconds
        applicationInstallStrategy = settings.applicationInstallStrategy
        scriptExecutionStrategy = settings.scriptExecutionStrategy
        swiftDialogPath = settings.swiftDialogPath
        swiftDialogMinimumVersion = settings.swiftDialogMinimumVersion
        onboardingFlagPath = settings.onboardingFlagPath
        enrollmentWindowHours = settings.enrollmentWindowHours
        installLocation = settings.installLocation
        stateDirectory = settings.stateDirectory
        debugLogging = settings.debugLogging
        detectionAppDirectory = settings.detectionAppDirectory
    }

    /// The values a project gets when nothing has been saved.
    static func builtIn() -> RuntimeSettingsDefaults {
        RuntimeSettingsDefaults(.makeDefault())
    }

    /// Copies these values into a project's settings and leaves every other property untouched.
    func apply(to settings: inout ProjectSettings) {
        settings.windowWidth = windowWidth
        settings.windowHeight = windowHeight
        settings.lockCompletionButtonUntilRequiredComplete = lockCompletionButtonUntilRequiredComplete
        settings.defaultTaskTimeoutSeconds = defaultTaskTimeoutSeconds
        settings.maximumEnrollmentDurationSeconds = maximumEnrollmentDurationSeconds
        settings.applicationInstallStrategy = applicationInstallStrategy
        settings.scriptExecutionStrategy = scriptExecutionStrategy
        settings.swiftDialogPath = swiftDialogPath
        settings.swiftDialogMinimumVersion = swiftDialogMinimumVersion
        settings.onboardingFlagPath = onboardingFlagPath
        settings.enrollmentWindowHours = enrollmentWindowHours
        settings.installLocation = installLocation
        settings.stateDirectory = stateDirectory
        settings.debugLogging = debugLogging
        settings.detectionAppDirectory = detectionAppDirectory
    }

    /// True when every value can be saved: ranges hold and paths and versions pass the field checks.
    var isValid: Bool {
        ProjectSettings.windowWidthRange.contains(windowWidth)
            && ProjectSettings.windowHeightRange.contains(windowHeight)
            && ProjectSettings.taskTimeoutRange.contains(defaultTaskTimeoutSeconds)
            && ProjectSettings.enrollmentDurationRange.contains(maximumEnrollmentDurationSeconds)
            && ProjectSettings.enrollmentWindowRange.contains(enrollmentWindowHours)
            && FieldValidator.absolutePathIssue(swiftDialogPath) == nil
            && FieldValidator.versionIssue(swiftDialogMinimumVersion) == nil
            && (onboardingFlagPath.isEmpty || FieldValidator.absolutePathIssue(onboardingFlagPath) == nil)
            && FieldValidator.deviceDirectoryIssue(installLocation) == nil
            && FieldValidator.deviceDirectoryIssue(stateDirectory) == nil
            && FieldValidator.detectionDirectoryIssue(detectionAppDirectory ?? "") == nil
    }
}

/// Keeps the app-wide defaults in the user's preferences. Nothing leaves the Mac.
struct AppSettingsStore: @unchecked Sendable {
    static let shared = AppSettingsStore()
    static let storageKey = "runtimeSettingsDefaults.v1"

    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    /// The saved defaults, or the built-in values when nothing valid has been saved.
    func load() -> RuntimeSettingsDefaults {
        guard let data = preferences.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode(RuntimeSettingsDefaults.self, from: data),
              saved.isValid
        else {
            return .builtIn()
        }
        return saved
    }

    func save(_ defaults: RuntimeSettingsDefaults) throws {
        preferences.set(try JSONEncoder().encode(defaults), forKey: Self.storageKey)
    }

    /// Forgets the saved defaults so new projects use the built-in values again.
    func reset() {
        preferences.removeObject(forKey: Self.storageKey)
    }
}
