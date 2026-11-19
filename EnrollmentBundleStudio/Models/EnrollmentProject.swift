import Foundation

/// A macOS release that can be chosen as the bundle's minimum supported version.
struct MacOSRelease: Identifiable, Hashable {
    let version: String
    let name: String
    var id: String { version }
}

/// Identity, packaging and runtime settings for a project.
struct ProjectSettings: Codable, Equatable {
    var projectName: String
    var organizationName: String
    /// Reverse-DNS identifier of the enrollment bundle itself (state files, LaunchDaemon label).
    var bundleIdentifier: String
    /// Reverse-DNS identifier of the installer package.
    var packageIdentifier: String
    var packageDisplayName: String
    var packageVersion: String
    var minimumMacOSVersion: String
    /// Absolute path of the folder that receives exported files and packages. Empty means the Downloads folder.
    var outputDirectoryPath: String
    /// Where the package installs the enrollment framework on the device.
    var installLocation: String
    /// Protected folder for task state and resume information on the device.
    var stateDirectory: String
    var windowWidth: Int
    var windowHeight: Int
    var debugLogging: Bool
    var defaultTaskTimeoutSeconds: Int
    var maximumEnrollmentDurationSeconds: Int
    var applicationInstallStrategy: ApplicationInstallStrategy
    var scriptExecutionStrategy: ScriptExecutionStrategy
    var lockCompletionButtonUntilRequiredComplete: Bool
    var swiftDialogPath: String
    var swiftDialogMinimumVersion: String
    /// Marks a Mac as onboarded (schema 4). Written by the framework after success, checked by the
    /// framework. Empty turns the onboarding guard off.
    var onboardingFlagPath: String
    /// A normal run only starts on Macs whose MDM enrollment is at most this many hours old (needs the onboarding flag).
    var enrollmentWindowHours: Int
    /// Folder on the device that receives the small placeholder app Intune uses to detect the package. Nil or empty
    /// means the install location. Optional so projects saved before this setting existed open unchanged.
    var detectionAppDirectory: String? = nil

    static let supportedMinimumMacOSVersions: [MacOSRelease] = [
        MacOSRelease(version: "26.0", name: "macOS Tahoe 26"),
        MacOSRelease(version: "27.0", name: "macOS Golden Gate 27")
    ]
    static let defaultMinimumMacOSVersion = "26.0"

    static let windowWidthRange: ClosedRange<Int> = 600...1600
    static let windowHeightRange: ClosedRange<Int> = 400...1200
    static let taskTimeoutRange: ClosedRange<Int> = 30...14_400
    static let enrollmentDurationRange: ClosedRange<Int> = 600...43_200
    static let enrollmentWindowRange: ClosedRange<Int> = 1...720
    static let defaultEnrollmentWindowHours = 20
    /// Default onboarding flag location (Intune script log folder).
    static let defaultOnboardingFlagPath = "/Library/Logs/Microsoft/IntuneScripts/onBoarding/onboarding.flag"

    static func makeDefault() -> ProjectSettings {
        ProjectSettings(
            projectName: "Enrollment Bundle",
            organizationName: "",
            bundleIdentifier: "com.example.enrollment",
            packageIdentifier: "com.example.enrollment.bundle",
            packageDisplayName: "Enrollment Bundle",
            packageVersion: "1.0.0",
            minimumMacOSVersion: defaultMinimumMacOSVersion,
            outputDirectoryPath: "",
            installLocation: "/Library/Application Support/EnrollmentBundle",
            stateDirectory: "/Library/Application Support/EnrollmentBundle/State",
            windowWidth: 900,
            windowHeight: 620,
            debugLogging: false,
            defaultTaskTimeoutSeconds: 900,
            maximumEnrollmentDurationSeconds: 7_200,
            applicationInstallStrategy: .bundledInstaller,
            scriptExecutionStrategy: .sequential,
            lockCompletionButtonUntilRequiredComplete: true,
            swiftDialogPath: "/usr/local/bin/dialog",
            swiftDialogMinimumVersion: "2.5.0",
            onboardingFlagPath: defaultOnboardingFlagPath,
            enrollmentWindowHours: defaultEnrollmentWindowHours
        )
    }
}

/// Everything the end user sees in the enrollment dialog.
struct Branding: Codable, Equatable {
    var title: String
    var welcomeMessage: String
    var completionMessage: String
    var warningMessage: String
    var failureMessage: String
    var buttonText: String
    var inProgressButtonText: String
    /// Shell command the generated framework runs after the user clicks the completion button. Empty means none.
    var completionCommand: String
    /// True runs the command as the console user (right for opening apps or URLs); false runs it as root.
    var completionCommandRunsAsUser: Bool
    /// Relative path inside Branding/, or nil.
    var logoPath: String?
    /// Relative path inside Branding/, or nil.
    var bannerPath: String?
    /// Relative path inside Branding/, or nil. Shown as a small badge over the dialog icon.
    var overlayIconPath: String?
    /// Relative path inside Branding/, or nil. PNG or JPEG applied once as the desktop wallpaper on each Mac.
    var wallpaperPath: String?
    var accentColor: HexColor
    /// SF Symbol shown when enrollment completes.
    var completionSymbol: String
    var showDeviceInfo: Bool
    var infoboxTemplate: String
    var supportContact: String
    var supportURL: String
    /// Blurs the screen behind the dialog. On by default; the dialog itself stays a normal window.
    var blurScreen: Bool

    static func makeDefault() -> Branding {
        Branding(
            title: "Welcome to {companyname}",
            welcomeMessage: "Hi {userfullname}, we're setting up your Mac. This usually takes 15 to 30 minutes, and you can keep working while apps install.",
            completionMessage: "Your Mac is ready. Click **Get Started** to begin.",
            warningMessage: "Setup finished, but some optional apps are still missing. They will keep installing in the background.",
            failureMessage: "Some required items could not be set up. Please contact IT support.",
            buttonText: "Get Started",
            inProgressButtonText: "Please wait",
            completionCommand: "open -a \"Company Portal\"",
            completionCommandRunsAsUser: true,
            logoPath: nil,
            bannerPath: nil,
            overlayIconPath: nil,
            wallpaperPath: nil,
            accentColor: HexColor(hex: "#0A64D2"),
            completionSymbol: "checkmark.seal.fill",
            showDeviceInfo: true,
            infoboxTemplate: "**Username:** {username}\n**Computer:** {computername}\n**Model:** {computermodel}\n**macOS:** {osname} {osversion}\n**Serial:** {serialnumber}",
            supportContact: "",
            supportURL: "",
            blurScreen: true
        )
    }
}

/// Root object of project.json.
struct EnrollmentProject: Codable, Equatable {
    /// Version of the project.json structure.
    var schemaVersion: Int
    /// Version of Enrollment Bundle Studio that last saved the project.
    var applicationVersion: String
    /// Version of the enrollment bundle content. Raising it makes devices re-evaluate completed tasks.
    var projectVersion: String
    var id: UUID
    var createdAt: Date
    var modifiedAt: Date
    var settings: ProjectSettings
    var branding: Branding
    var applicationGroups: [ApplicationGroup]
    var scripts: [ScriptItem]
    var systemTasks: [EnrollmentTask]
    /// The Dock set up after enrollment, or nil when the project never configured one (schema-compatible addition).
    var dock: DockConfiguration?

    static func makeDefault(now: Date = Date()) -> EnrollmentProject {
        let timestamp = ProjectCoding.wholeSeconds(now)
        var project = EnrollmentProject(
            schemaVersion: AppInfo.currentSchemaVersion,
            applicationVersion: AppInfo.version,
            projectVersion: "1.0.0",
            id: UUID(),
            createdAt: timestamp,
            modifiedAt: timestamp,
            settings: .makeDefault(),
            branding: .makeDefault(),
            applicationGroups: [],
            scripts: [],
            systemTasks: []
        )
        if let portal = ApplicationCatalog.entry(id: "company-portal") {
            let item = portal.makeApplicationItem(
                taskIdentifier: project.uniqueTaskIdentifier(for: portal.displayName, prefix: "app"),
                strategy: .waitForIntune
            )
            project.applicationGroups = [
                ApplicationGroup(
                    id: UUID(),
                    name: "Device Management",
                    symbolName: ApplicationCatalog.symbol(forCategory: "Device Management"),
                    isRequired: true,
                    displayBehavior: .individualItems,
                    applications: [item]
                )
            ]
        }
        project.systemTasks = [EnrollmentTask.makeFinalValidation(taskIdentifier: "system.final-validation")]
        return project
    }
}
