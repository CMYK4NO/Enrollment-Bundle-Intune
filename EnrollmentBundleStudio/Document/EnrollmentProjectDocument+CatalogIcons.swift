import Foundation

private final class CatalogIconBundleToken {}

/// Loads icons that ship inside the app for catalogue entries. Nothing is downloaded.
enum CatalogIconLoader {
    static func data(for entry: CatalogEntry) -> Data? {
        guard let name = entry.bundledIconResource else { return nil }
        let bundle = Bundle(for: CatalogIconBundleToken.self)
        for fileExtension in ["icns", "png"] {
            if let url = bundle.url(forResource: name, withExtension: fileExtension) {
                return try? AssetImporter.readFile(at: url)
            }
        }
        return nil
    }
}

extension EnrollmentProjectDocument {
    /// Adds catalogue entries and, for entries that ship an icon, copies that icon into the project's Icons folder
    /// and points the new application at it. A missing or invalid icon leaves the default application icon.
    /// Returns the number of applications added.
    @discardableResult
    mutating func addCatalogEntries(
        _ entries: [CatalogEntry],
        target: CatalogTarget,
        iconData: (CatalogEntry) -> Data? = CatalogIconLoader.data(for:)
    ) -> Int {
        let existingIDs = Set(project.allApplications.map { $0.id })
        let added = project.addCatalogEntries(entries, target: target)
        guard added > 0 else { return 0 }
        for item in project.allApplications where !existingIDs.contains(item.id) {
            assignBundledIcon(to: item, iconData: iconData)
        }
        return added
    }

    /// Gives existing catalogue items that ship an icon, and still use the default application icon, that icon.
    mutating func applyBundledCatalogIcons(iconData: (CatalogEntry) -> Data? = CatalogIconLoader.data(for:)) {
        let defaultIcon = IconSource(kind: .applicationBundle, value: "")
        for item in project.allApplications where item.icon == defaultIcon {
            assignBundledIcon(to: item, iconData: iconData)
        }
    }

    private mutating func assignBundledIcon(to original: ApplicationItem, iconData: (CatalogEntry) -> Data?) {
        var item = original
        guard let catalogID = item.catalogID,
              let entry = ApplicationCatalog.entry(id: catalogID),
              let data = iconData(entry),
              let format = try? AssetImporter.validateImage(data) else {
            return
        }
        let path = AssetImporter.iconPath(for: item.displayName, format: format, existingPaths: Set(assets.keys))
        do {
            try setAsset(data, at: path)
        } catch {
            return
        }
        item.icon = IconSource(kind: .projectAsset, value: path)
        _ = project.updateApplication(item)
    }
}
