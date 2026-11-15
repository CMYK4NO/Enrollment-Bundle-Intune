import XCTest
@testable import EnrollmentBundleStudio

final class ScriptImporterTests: XCTestCase {
    func testSHA256MatchesKnownVectors() {
        XCTAssertEqual(Hashing.sha256Hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(Hashing.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testImportCreatesScriptItem() throws {
        let document = try TestSupport.makeProjectWithScript()
        let script = try XCTUnwrap(document.project.scripts.first)
        XCTAssertEqual(script.relativePath, "Scripts/CheckExample.sh")
        XCTAssertEqual(script.taskIdentifier, "script.checkexample")
        XCTAssertEqual(script.displayName, "CheckExample")
        XCTAssertEqual(script.interpreter, "/bin/bash")
        XCTAssertEqual(script.sha256, Hashing.sha256Hex(Data(TestSupport.cleanScript.utf8)))
        XCTAssertTrue(script.sourceWasExecutable)
        XCTAssertEqual(script.successExitCodes, [0])
        XCTAssertFalse(script.execution.isRequired)
        XCTAssertEqual(script.execution.messages, .script)
        XCTAssertNotNil(document.assets["Scripts/CheckExample.sh"])
    }

    func testImportRejectsBadFiles() {
        XCTAssertThrowsError(try ScriptImporter.validate(data: Data("#!/bin/bash\n".utf8), filename: "x.py")) { error in
            XCTAssertEqual(error as? ScriptImportError, .unsupportedExtension("x.py"))
        }
        XCTAssertThrowsError(try ScriptImporter.validate(data: Data(), filename: "x.sh")) { error in
            XCTAssertEqual(error as? ScriptImportError, .emptyFile)
        }
        XCTAssertThrowsError(try ScriptImporter.validate(data: Data([0xFF, 0xFE]), filename: "x.sh")) { error in
            XCTAssertEqual(error as? ScriptImportError, .notUTF8)
        }
        XCTAssertThrowsError(try ScriptImporter.validate(data: Data(count: ScriptImporter.maximumBytes + 1), filename: "x.zsh"))
        XCTAssertNoThrow(try ScriptImporter.validate(data: Data("#!/bin/zsh\n".utf8), filename: "Setup.ZSH"))
    }

    func testScriptPathsAreSanitizedAndUnique() {
        let existing: Set<String> = ["Scripts/Check-Defender.sh"]
        XCTAssertEqual(ScriptImporter.scriptPath(for: "Check Defender.sh", existingPaths: existing), "Scripts/Check-Defender-2.sh")
        XCTAssertEqual(ScriptImporter.scriptPath(for: "../../evil.zsh", existingPaths: []), "Scripts/evil.zsh")
    }

    func testReadScriptReportsExecutableBit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.sh")
        try Data(TestSupport.cleanScript.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertFalse(try ScriptImporter.readScript(at: file).wasExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        XCTAssertTrue(try ScriptImporter.readScript(at: file).wasExecutable)
    }

    func testReplaceAndAcceptFile() throws {
        var document = try TestSupport.makeProjectWithScript()
        let id = try XCTUnwrap(document.project.scripts.first?.id)
        let newSource = Data("#!/bin/zsh\necho replaced\n".utf8)
        try document.replaceScriptFile(id: id, data: newSource, originalFilename: "CheckExample.zsh", wasExecutable: false)
        let replaced = try XCTUnwrap(document.project.script(id: id))
        XCTAssertEqual(replaced.relativePath, "Scripts/CheckExample.zsh")
        XCTAssertEqual(replaced.interpreter, "/bin/zsh")
        XCTAssertEqual(replaced.sha256, Hashing.sha256Hex(newSource))
        XCTAssertNil(document.assets["Scripts/CheckExample.sh"], "The old file is removed")

        // Simulate an outside edit by writing different bytes at the same path, then accept it.
        try document.setAsset(Data("#!/bin/zsh\necho edited\n".utf8), at: replaced.relativePath)
        XCTAssertNotEqual(Hashing.sha256Hex(try XCTUnwrap(document.assets[replaced.relativePath])), document.project.script(id: id)?.sha256)
        document.acceptCurrentScriptFile(id: id)
        XCTAssertEqual(Hashing.sha256Hex(try XCTUnwrap(document.assets[replaced.relativePath])), document.project.script(id: id)?.sha256)
    }

    func testRemoveScriptDropsFileAndDependencies() throws {
        var document = try TestSupport.makeProjectWithScript()
        let script = try XCTUnwrap(document.project.scripts.first)
        var portal = try XCTUnwrap(document.project.allApplications.first)
        portal.execution.dependencies = [script.taskIdentifier]
        document.project.updateApplication(portal)

        document.removeScript(id: script.id)
        XCTAssertTrue(document.project.scripts.isEmpty)
        XCTAssertNil(document.assets[script.relativePath])
        XCTAssertEqual(document.project.allApplications.first?.execution.dependencies, [])
    }

    func testExitCodeParsing() {
        XCTAssertEqual(ExitCodeParser.parse("0"), [0])
        XCTAssertEqual(ExitCodeParser.parse(" 0, 2 ,2"), [0, 2])
        XCTAssertNil(ExitCodeParser.parse(""))
        XCTAssertNil(ExitCodeParser.parse("0, 256"))
        XCTAssertNil(ExitCodeParser.parse("zero"))
    }
}
