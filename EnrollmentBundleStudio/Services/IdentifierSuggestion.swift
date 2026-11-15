import Foundation

/// Suggests reverse-DNS identifiers from the organization name, for example "Contoso Ltd." gives
/// com.contosoltd.enrollment.bundle.
enum IdentifierSuggestion {
    /// Used while no organization name is set. Matches the identifiers of a new project.
    static let fallbackLabel = "example"

    /// Lowercase ASCII letters and digits only, so the result is always a valid reverse-DNS label.
    static func label(forOrganization name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var label = ""
        for scalar in folded.unicodeScalars where label.count < 40 {
            let isLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            if isLetter || isDigit {
                label.unicodeScalars.append(scalar)
            }
        }
        return label.isEmpty ? fallbackLabel : label
    }

    static func bundleIdentifier(forOrganization name: String) -> String {
        "com.\(label(forOrganization: name)).enrollment"
    }

    static func packageIdentifier(forOrganization name: String) -> String {
        "com.\(label(forOrganization: name)).enrollment.bundle"
    }
}

extension ProjectSettings {
    /// The chosen output folder, or the current user's Downloads folder when none is chosen.
    var effectiveOutputDirectoryPath: String {
        if !outputDirectoryPath.isEmpty { return outputDirectoryPath }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads.path
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
    }

    /// Sets the organization name and keeps both identifiers in step with it, but only while they still hold
    /// the value suggested for the previous name. An identifier the administrator edited by hand is left alone.
    mutating func setOrganizationName(_ name: String) {
        guard name != organizationName else { return }
        let previousBundle = IdentifierSuggestion.bundleIdentifier(forOrganization: organizationName)
        let previousPackage = IdentifierSuggestion.packageIdentifier(forOrganization: organizationName)
        organizationName = name
        let newBundle = IdentifierSuggestion.bundleIdentifier(forOrganization: name)
        let newPackage = IdentifierSuggestion.packageIdentifier(forOrganization: name)
        if bundleIdentifier == previousBundle, FieldValidator.isValidReverseDNS(newBundle) {
            bundleIdentifier = newBundle
        }
        if packageIdentifier == previousPackage, FieldValidator.isValidReverseDNS(newPackage) {
            packageIdentifier = newPackage
        }
    }

    /// Binding target for the organization field: editing it updates the identifiers as described above.
    var organizationNameLinkedToIdentifiers: String {
        get { organizationName }
        set { setOrganizationName(newValue) }
    }
}

extension EnrollmentProject {
    /// The enrollment bundle and the installer package always carry the same version.
    mutating func setVersion(_ version: String) {
        settings.packageVersion = version
        projectVersion = version
    }
}
