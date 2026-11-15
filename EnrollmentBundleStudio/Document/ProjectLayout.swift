import Foundation

/// Folder and file names inside a .enrollmentproject package.
enum ProjectLayout {
    static let fileExtension = "enrollmentproject"
    static let projectFileName = "project.json"

    static let brandingDirectory = "Branding"
    static let iconsDirectory = "Icons"
    static let scriptsDirectory = "Scripts"
    static let templatesDirectory = "Templates"
    static let generatedDirectory = "Generated"
    static let buildsDirectory = "Builds"
    /// Installer packages. Kept as file references, never loaded into memory as asset data.
    static let installersDirectory = "Installers"

    /// Folders whose files are loaded into the document and written back on save.
    static let managedAssetDirectories = [brandingDirectory, iconsDirectory, scriptsDirectory]

    /// Folders that are created for a readable layout but never rewritten by document saves.
    static let preservedDirectories = [templatesDirectory, generatedDirectory, buildsDirectory]
}
