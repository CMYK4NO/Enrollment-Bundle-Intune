import SwiftUI
import UniformTypeIdentifiers

/// Configuration export and import and "Duplicate as New Project" for one window.
/// Uses AppKit panels (see FilePanels) and handles menu requests in `.task(id:)`, after view updates.
struct ProjectTransferModifier: ViewModifier {
    @Binding var document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel

    @Environment(\.openDocument) private var openDocument
    @State private var pendingImport: PendingImport?
    /// Set by the import review sheet; saved once the sheet has fully closed so the save panel
    /// attaches to the project window, not to the closing sheet.
    @State private var queuedNewProject: EnrollmentProjectDocument?

    func body(content: Content) -> some View {
        content
            .task(id: workspace.requestCount(.exportConfiguration)) {
                if workspace.consume(.exportConfiguration) { exportConfiguration() }
            }
            .task(id: workspace.requestCount(.duplicateProject)) {
                if workspace.consume(.duplicateProject) { duplicateProject() }
            }
            .task(id: workspace.requestCount(.importConfiguration)) {
                if workspace.consume(.importConfiguration) { importConfiguration() }
            }
            .sheet(item: $pendingImport, onDismiss: saveQueuedProject) { pending in
                ImportReviewSheet(pending: pending) { assignNewID in
                    let imported = EnrollmentProjectDocument(project: pending.result.project, assets: pending.result.assets)
                    queuedNewProject = imported.asNewProject(keepProjectID: !assignNewID)
                }
            }
    }

    // MARK: Actions

    private func exportConfiguration() {
        guard !document.isReadOnly else {
            workspace.alert = AppAlert(title: "Export Unavailable", message: "This project is read-only because it uses a newer schema.")
            return
        }
        let data: Data
        do {
            data = try ConfigurationArchive.export(project: document.project, assets: document.assets)
        } catch {
            workspace.present(error, title: "Could Not Export Configuration")
            return
        }
        let name = FilenameSanitizer.sanitize(document.project.settings.projectName, fallback: "Enrollment")
        Task {
            guard let url = await FilePanels.saveLocation(
                title: "Export Configuration",
                defaultName: "\(name).\(ConfigurationArchive.fileExtension)",
                contentType: .enrollmentConfiguration
            ) else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                workspace.present(error, title: "Could Not Export Configuration")
            }
        }
    }

    private func duplicateProject() {
        guard !document.isReadOnly else {
            workspace.alert = AppAlert(title: "Duplicate Unavailable", message: "This project is read-only because it uses a newer schema.")
            return
        }
        saveNewProject(document.asNewProject(name: document.project.settings.projectName + " Copy"))
    }

    private func importConfiguration() {
        Task {
            // Project packages are accepted too. The extension type is added in case the system has not
            // registered the project type yet, so the panel never greys out a .ebsproject.
            var types: [UTType] = [.enrollmentConfiguration, .json, .enrollmentProject]
            if let byExtension = UTType(filenameExtension: ProjectLayout.fileExtension), !types.contains(byExtension) {
                types.append(byExtension)
            }
            let urls = await FilePanels.openFiles(title: "Import Configuration", allowedContentTypes: types)
            guard let url = urls.first else { return }
            do {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values.isDirectory == true || url.pathExtension.lowercased() == ProjectLayout.fileExtension {
                    let package = try EnrollmentProjectDocument(fileWrapper: try FileWrapper(url: url))
                    pendingImport = PendingImport(fileName: url.lastPathComponent, result: try ConfigurationArchive.importResult(from: package))
                    return
                }
                let size = values.fileSize ?? 0
                guard size <= ConfigurationArchive.maximumArchiveBytes else {
                    throw ProjectFileError.invalidProjectFile("The configuration file is larger than 64 MB.")
                }
                let parsed = try ConfigurationArchive.parse(try Data(contentsOf: url))
                pendingImport = PendingImport(fileName: url.lastPathComponent, result: parsed)
            } catch {
                workspace.present(error, title: "Could Not Import Configuration")
            }
        }
    }

    private func saveQueuedProject() {
        guard let project = queuedNewProject else { return }
        queuedNewProject = nil
        saveNewProject(project)
    }

    /// Asks where to save, writes the package, then opens it in a new window.
    private func saveNewProject(_ newProject: EnrollmentProjectDocument) {
        let name = FilenameSanitizer.sanitize(newProject.project.settings.projectName, fallback: "Enrollment")
        Task {
            guard let url = await FilePanels.saveLocation(
                title: "Save New Project",
                defaultName: "\(name).\(ProjectLayout.fileExtension)",
                contentType: .enrollmentProject
            ) else { return }
            do {
                let wrapper = try newProject.makeFileWrapper(existing: nil)
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            } catch {
                workspace.present(error, title: "Could Not Save the New Project")
                return
            }
            do {
                try await openDocument(at: url)
            } catch {
                workspace.present(error, title: "The Project Was Saved but Could Not Be Opened")
            }
        }
    }
}
