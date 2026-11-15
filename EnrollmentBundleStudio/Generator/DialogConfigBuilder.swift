import Foundation

/// One row of the dialog list and the tasks it represents.
struct DialogListEntry: Equatable {
    let index: Int
    let title: String
    let icon: String
    let isSummary: Bool
    let taskIdentifiers: [String]
    let waitingText: String
}

/// Builds the swiftDialog JSON configuration. Used both for the generated bundle (icons at their device
/// paths, placeholders left for the device) and for the live preview (icons in a temporary folder,
/// placeholders already resolved).
enum DialogConfigBuilder {
    /// The dialog list, in the same order and grouping as the static preview.
    static func listEntries(project: EnrollmentProject, iconPath: (IconSource, String) -> String) -> [DialogListEntry] {
        let state = PreviewBuilder.makeState(project: project, scenario: .initial, overrides: [:])
        var messagesByTask: [String: String] = [:]
        for task in TaskPlanner.plan(project) where messagesByTask[task.taskIdentifier] == nil {
            messagesByTask[task.taskIdentifier] = task.execution.messages.waiting
        }
        return state.displayItems.enumerated().map { index, item in
            DialogListEntry(
                index: index,
                title: item.title,
                icon: iconPath(item.icon, item.applicationPath),
                isSummary: item.isSummary,
                taskIdentifiers: item.memberIDs,
                waitingText: item.isSummary ? "0 of \(item.memberIDs.count) finished" : (messagesByTask[item.id] ?? "")
            )
        }
    }

    /// The JSON object for swiftDialog's --jsonfile.
    /// - Parameters:
    ///   - resolve: applied to every user-facing text (normalizes tokens for the device, or resolves them for previews).
    ///   - logoPath / bannerPath / overlayIconPath: paths where the images will be found when the dialog runs.
    static func configuration(
        project: EnrollmentProject,
        entries: [DialogListEntry],
        totalTasks: Int,
        logoPath: String?,
        bannerPath: String?,
        overlayIconPath: String?,
        resolve: (String) -> String
    ) -> [String: Any] {
        let branding = project.branding
        let settings = project.settings
        let locked = settings.lockCompletionButtonUntilRequiredComplete
        var configuration: [String: Any] = [
            "title": resolve(branding.title),
            "message": resolve(branding.welcomeMessage),
            "icon": logoPath ?? "SF=building.2.fill",
            "button1text": locked ? branding.inProgressButtonText : branding.buttonText,
            "width": String(settings.windowWidth),
            "height": String(settings.windowHeight),
            "moveable": true,
            // Always written, so swiftDialog never falls back to a mode of its own. The window is never full screen.
            "blurscreen": branding.blurScreen,
            "progress": String(max(totalTasks, 1)),
            "progresstext": "Starting…",
            "listitem": entries.map { entry in
                [
                    "title": entry.title,
                    "status": "pending",
                    "statustext": DialogCommand.oneLine(entry.waitingText),
                    "icon": entry.icon
                ]
            }
        ]
        if let bannerPath {
            configuration["bannerimage"] = bannerPath
        }
        if let overlayIconPath {
            configuration["overlayicon"] = overlayIconPath
        }
        if branding.showDeviceInfo && !branding.infoboxTemplate.isEmpty {
            configuration["infobox"] = resolve(branding.infoboxTemplate)
        }
        var help: [String] = []
        if !branding.supportContact.isEmpty { help.append(resolve(branding.supportContact)) }
        if !branding.supportURL.isEmpty { help.append(branding.supportURL) }
        if !help.isEmpty {
            configuration["helpmessage"] = help.joined(separator: "\n\n")
        }
        return configuration
    }

    static func jsonData(_ configuration: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
