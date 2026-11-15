import Foundation
@testable import EnrollmentBundleStudio

/// Test-only reader for the shell literals the generator writes. It understands exactly the forms
/// ShellQuoting produces ('...' with '\'' for embedded quotes, and plain integers).
enum ShellLiteralReader {
    struct ParseError: Error {}

    /// Decodes a single-quoted literal such as 'it'\''s' back to it's.
    static func decodeSingleQuoted(_ literal: String) throws -> String {
        var result = ""
        var index = literal.startIndex
        while index < literal.endIndex {
            if literal[index] == "'" {
                guard let close = literal[literal.index(after: index)...].firstIndex(of: "'") else { throw ParseError() }
                result += literal[literal.index(after: index)..<close]
                index = literal.index(after: close)
            } else if literal[index...].hasPrefix("\\'") {
                result += "'"
                index = literal.index(index, offsetBy: 2)
            } else {
                throw ParseError()
            }
        }
        return result
    }

    /// Parses a data-only file into NAME -> value. Fails on anything that is not a comment or an assignment
    /// of a quoted string or integer, which proves the file contains no code.
    static func assignments(in text: String) throws -> [String: String] {
        var values: [String: String] = [:]
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\n" {
                index = text.index(after: index)
                continue
            }
            if text[index] == "#" {
                index = text[index...].firstIndex(of: "\n") ?? text.endIndex
                continue
            }
            guard let equals = text[index...].firstIndex(of: "=") else { throw ParseError() }
            let name = String(text[index..<equals])
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw ParseError() }
            var cursor = text.index(after: equals)
            if cursor < text.endIndex, text[cursor] == "'" {
                var literal = ""
                while cursor < text.endIndex, text[cursor] == "'" || text[cursor...].hasPrefix("\\'") {
                    if text[cursor] == "'" {
                        guard let close = text[text.index(after: cursor)...].firstIndex(of: "'") else { throw ParseError() }
                        literal += text[cursor...close]
                        cursor = text.index(after: close)
                    } else {
                        literal += "\\'"
                        cursor = text.index(cursor, offsetBy: 2)
                    }
                }
                values[name] = try decodeSingleQuoted(literal)
            } else {
                let end = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
                let raw = String(text[cursor..<end])
                guard raw.range(of: "^-?[0-9]+$", options: .regularExpression) != nil else { throw ParseError() }
                values[name] = raw
                cursor = end
            }
            guard cursor == text.endIndex || text[cursor] == "\n" else { throw ParseError() }
            index = cursor
        }
        return values
    }
}

extension TestSupport {
    /// A project exercising every generator path: required group, summary group with parallel members,
    /// a script, a logo, a bundled installer and a wait condition.
    static func makeGeneratorProject(packageURL: URL) throws -> EnrollmentProjectDocument {
        var document = try makeProjectWithScript()
        document.project.settings.organizationName = "Contoso & \"Partners\" it's"
        document.project.settings.packageIdentifier = "com.contoso.enrollment.bundle"
        document.project.settings.bundleIdentifier = "com.contoso.enrollment"
        document.project.settings.installLocation = "/Library/Application Support/Contoso/Enrollment"
        document.project.branding.title = "Welcome to {CompanyName}"
        try document.replaceBrandingImage(.logo, data: try makePNG(), path: "Branding/CompanyLogo.png")

        let entries = ["microsoft-365"].compactMap(ApplicationCatalog.entry(id:))
        document.project.addCatalogEntries(entries, target: .categoryGroups)
        if let index = document.project.applicationGroups.firstIndex(where: { $0.name == "Microsoft 365" }) {
            var companion = ApplicationItem.makeCustom(strategy: .waitForIntune, timeoutSeconds: 900)
            companion.displayName = "Microsoft 365 Companion"
            companion.applicationPath = "/Applications/Microsoft 365 Companion.app"
            companion.taskIdentifier = "app.m365-companion"
            document.project.addApplication(companion, toGroup: document.project.applicationGroups[index].id)
            document.project.applicationGroups[index].displayBehavior = .singleSummaryItem
            for itemIndex in document.project.applicationGroups[index].applications.indices {
                document.project.applicationGroups[index].applications[itemIndex].execution.parallelGroup = "m365"
            }
        }

        var tool = ApplicationItem.makeCustom(strategy: .bundledInstaller, timeoutSeconds: 900)
        tool.displayName = "Tool $(touch /tmp/pwned) 'quoted'"
        tool.applicationPath = "/Applications/Example Tool.app"
        tool.taskIdentifier = "app.example-tool"
        let groupID = document.project.addGroup(named: "Custom Applications")
        document.project.addApplication(tool, toGroup: groupID)
        document.attachInstaller(PendingInstaller(sourceURL: packageURL, inspection: try InstallerImporter.inspect(at: packageURL)), toApplication: tool.id)

        let waitID = document.project.addSystemTask(type: .waitCondition)
        if var wait = document.project.systemTask(id: waitID) {
            wait.validation = TaskCheck(method: .customCommand, value: "/usr/bin/test -f \"/var/db/.AppleSetupDone\"")
            document.project.updateSystemTask(wait)
        }
        return document
    }

    static func makeFakePackage(in directory: URL, name: String = "Example Tool.pkg") throws -> URL {
        let url = directory.appendingPathComponent(name)
        var data = Data(InstallerImporter.xarMagic)
        data.append(Data("payload".utf8))
        try data.write(to: url)
        return url
    }
}
