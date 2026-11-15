import UniformTypeIdentifiers

extension UTType {
    /// Declared in Config/Info.plist under UTExportedTypeDeclarations. Conforms to com.apple.package,
    /// so Finder shows the folder as one document while it stays an ordinary directory on disk.
    static let enrollmentProject = UTType(exportedAs: "com.example.enrollmentbundlestudio.project", conformingTo: .package)
}

