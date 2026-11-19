import Foundation

/// Guards every relative path that comes from project.json or an imported configuration.
/// Paths must stay inside one of the allowed top-level project folders.
enum RelativePathValidator {
    static func isSafe(_ path: String, allowedRoots: [String]) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 1024 else { return false }
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\") else { return false }
        guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2, let root = components.first, allowedRoots.contains(root) else { return false }
        for component in components {
            if component.isEmpty || component == "." || component == ".." || component.utf8.count > 255 {
                return false
            }
        }
        return true
    }

    /// Resolves a safe relative path against a project root and confirms the result stays inside it.
    static func resolve(_ path: String, in root: URL, allowedRoots: [String]) -> URL? {
        guard isSafe(path, allowedRoots: allowedRoots) else { return nil }
        let rootPath = root.standardizedFileURL.path
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidate.path.hasPrefix(prefix) ? candidate : nil
    }
}
