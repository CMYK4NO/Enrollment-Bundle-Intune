import AppKit
import Foundation

extension ValidationEnvironment {
    /// Reads the real file system of this Mac. Never writes anything.
    static func live() -> ValidationEnvironment {
        ValidationEnvironment(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            isWritableDirectory: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
                    && FileManager.default.isWritableFile(atPath: path)
            },
            isKnownSymbol: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil },
            shellCheckPath: ShellCheckService.locate()?.path
        )
    }
}
