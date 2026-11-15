import UniformTypeIdentifiers

extension UTType {
    /// Portable configuration export (a JSON file). Declared in Config/Info.plist.
    /// Exports are written directly with an NSSavePanel; see ProjectTransferModifier.
    static let enrollmentConfiguration = UTType(exportedAs: "com.example.enrollmentbundlestudio.configuration", conformingTo: .json)
}
