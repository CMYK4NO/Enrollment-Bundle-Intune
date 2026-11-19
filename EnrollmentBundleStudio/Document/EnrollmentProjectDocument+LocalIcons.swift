import Foundation

/// Which applications got an embedded icon and which could not be read from this Mac.
struct LocalIconEmbedResult: Equatable {
    var embedded: [String] = []
    var notFound: [String] = []
}

extension EnrollmentProjectDocument {
    /// Copies the icon of every application that still uses "Installed app icon" into the project's Icons folder
    /// and points the application at it. `iconData` receives the application path and returns PNG data, or nil when
    /// the app is not installed on this Mac. Applications whose icon cannot be read stay unchanged.
    mutating func embedLocalApplicationIcons(iconData: (String) -> Data?) -> LocalIconEmbedResult {
        var result = LocalIconEmbedResult()
        for application in project.allApplications where application.icon.kind == .applicationBundle {
            if embedLocalIcon(into: application, iconData: iconData) {
                result.embedded.append(application.displayName)
            } else {
                result.notFound.append(application.displayName)
            }
        }
        return result
    }

    /// Stores one application's icon in the project. Returns false when the app has no path, no icon could be read,
    /// or the data is not a valid image.
    @discardableResult
    mutating func embedLocalIcon(into original: ApplicationItem, iconData: (String) -> Data?) -> Bool {
        guard !original.applicationPath.isEmpty,
              let data = iconData(original.applicationPath),
              let format = try? AssetImporter.validateImage(data) else {
            return false
        }
        let path = AssetImporter.iconPath(for: original.displayName, format: format, existingPaths: Set(assets.keys))
        do {
            try setAsset(data, at: path)
        } catch {
            return false
        }
        var item = original
        item.icon = IconSource(kind: .projectAsset, value: path)
        return project.updateApplication(item) != nil
    }
}
