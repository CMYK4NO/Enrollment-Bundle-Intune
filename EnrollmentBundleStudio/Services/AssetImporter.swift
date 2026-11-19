import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String, Equatable {
    case png
    case jpeg
    case icns

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .icns: return "icns"
        }
    }
}

/// Branding images with fixed, predictable file names inside Branding/.
enum BrandingImageRole: String, CaseIterable, Identifiable {
    case logo
    case banner
    case overlay
    case wallpaper

    var id: String { rawValue }

    var baseFilename: String {
        switch self {
        case .logo: return "CompanyLogo"
        case .banner: return "Banner"
        case .overlay: return "OverlayIcon"
        case .wallpaper: return "Wallpaper"
        }
    }

    var title: String {
        switch self {
        case .logo: return "Company logo"
        case .banner: return "Banner"
        case .overlay: return "Overlay icon"
        case .wallpaper: return "Desktop wallpaper"
        }
    }
}

enum AssetImportError: LocalizedError, Equatable {
    case notARegularFile
    case emptyFile
    case tooLarge(Int)
    case unsupportedFormat
    case undecodableImage
    case unsupportedWallpaperFormat

    var errorDescription: String? {
        switch self {
        case .notARegularFile:
            return "The selected item is not a regular file."
        case .emptyFile:
            return "The selected file is empty."
        case .tooLarge(let bytes):
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "The selected file is \(formatted). Images must be 10 MB or smaller."
        case .unsupportedFormat:
            return "Only PNG, JPEG and ICNS images are supported."
        case .undecodableImage:
            return "The file looks like an image but could not be decoded."
        case .unsupportedWallpaperFormat:
            return "A wallpaper must be a PNG or JPEG image."
        }
    }
}

/// Reads and checks images before they are copied into the project.
/// The original file is never referenced after import, so moving it later does not break the project.
enum AssetImporter {
    static let maximumImageBytes = 10 * 1024 * 1024
    /// Wallpapers are large photographs, so they get a higher limit than logos and icons.
    static let maximumWallpaperBytes = 50 * 1024 * 1024
    static let allowedWallpaperTypes: [UTType] = [.png, .jpeg]
    static let allowedImageTypes: [UTType] = [.png, .jpeg, .icns]

    /// Reads a user-selected file after checking that it is a regular file within the size limit.
    static func readFile(at url: URL, maximumBytes: Int = maximumImageBytes) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let resolved = url.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw AssetImportError.notARegularFile
        }
        if let size = values.fileSize, size > maximumBytes {
            throw AssetImportError.tooLarge(size)
        }
        let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else {
            throw AssetImportError.tooLarge(data.count)
        }
        return data
    }

    /// Identifies the format from the file signature rather than trusting the extension.
    static func detectFormat(_ data: Data) -> ImageFormat? {
        let header = [UInt8](data.prefix(8))
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }
        if header.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }
        if header.starts(with: [0x69, 0x63, 0x6E, 0x73]) {
            return .icns
        }
        return nil
    }

    static func validateImage(_ data: Data, maximumBytes: Int = maximumImageBytes) throws -> ImageFormat {
        guard !data.isEmpty else { throw AssetImportError.emptyFile }
        guard data.count <= maximumBytes else { throw AssetImportError.tooLarge(data.count) }
        guard let format = detectFormat(data) else { throw AssetImportError.unsupportedFormat }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw AssetImportError.undecodableImage
        }
        return format
    }

    /// Validates a wallpaper: a decodable PNG or JPEG within the wallpaper size limit.
    static func validateWallpaper(_ data: Data) throws -> ImageFormat {
        let format = try validateImage(data, maximumBytes: maximumWallpaperBytes)
        guard format == .png || format == .jpeg else { throw AssetImportError.unsupportedWallpaperFormat }
        return format
    }

    static func brandingPath(role: BrandingImageRole, format: ImageFormat) -> String {
        "\(ProjectLayout.brandingDirectory)/\(role.baseFilename).\(format.fileExtension)"
    }

    /// A unique path inside Icons/ derived from the application's display name.
    static func iconPath(for displayName: String, format: ImageFormat, existingPaths: Set<String>) -> String {
        let base = FilenameSanitizer.sanitize(displayName, fallback: "Icon")
        let prefix = "\(ProjectLayout.iconsDirectory)/"
        let existingNames = Set(existingPaths.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        let name = FilenameSanitizer.uniqueName(base: base, fileExtension: format.fileExtension, existing: existingNames)
        return prefix + name
    }
}
