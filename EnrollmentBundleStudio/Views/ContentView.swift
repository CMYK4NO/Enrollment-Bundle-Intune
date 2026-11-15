import SwiftUI

/// Root view of a project window.
struct ContentView: View {
    @Binding var document: EnrollmentProjectDocument
    let fileURL: URL?
    @StateObject private var workspace = WorkspaceViewModel()
    /// Owned here as @State: List(selection:) may write during a view update, which is safe for @State.
    @State private var selection: SidebarSection? = .overview

    var body: some View {
        let report = ValidationEngine.validate(project: document.project, assets: document.assets, environment: .live(),
                                              installerPaths: Set(document.installerSources.keys))
        NavigationSplitView {
            SidebarView(selection: $selection, project: document.project, validationErrorCount: report.errorCount)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail(report: report)
                .disabled(document.isReadOnly && selection != .preview)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if document.isReadOnly {
                        NoticeBanner(
                            symbolName: "lock.fill",
                            message: "Read-only: this project uses a newer schema (\(document.project.schemaVersion)). Editing is disabled and the original will not be overwritten."
                        )
                    }
                }
                .frame(minWidth: 620, minHeight: 480)
        }
        .focusedSceneValue(\.workspace, workspace)
        .task(id: workspace.navigationRequestID) {
            if let section = workspace.consumeNavigation() {
                selection = section
            }
        }
        .modifier(ProjectTransferModifier(document: $document, workspace: workspace))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    selection = .applications
                    workspace.request(.catalog)
                } label: {
                    Label("Add Apps", systemImage: "plus.app")
                }
                .help("Add applications from the catalogue")
                .disabled(document.isReadOnly)

                Button {
                    selection = .preview
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .help("Show the static enrollment preview")
            }
        }
        .alert(
            workspace.alert?.title ?? "",
            isPresented: Binding(
                get: { workspace.alert != nil },
                set: { isPresented in
                    if !isPresented {
                        Task { @MainActor in workspace.alert = nil }
                    }
                }
            ),
            presenting: workspace.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private func detail(report: ValidationReport) -> some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(document: $document, fileURL: fileURL, workspace: workspace)
        case .branding:
            BrandingView(document: $document, workspace: workspace)
        case .applications:
            ApplicationsView(document: $document, workspace: workspace)
        case .scripts:
            ScriptsView(document: $document, workspace: workspace, shellCheckURL: ShellCheckService.locate())
        case .execution:
            ExecutionView(document: $document, workspace: workspace)
        case .preview:
            PreviewView(document: document, workspace: workspace)
        case .validation:
            ValidationView(report: report, selection: $selection)
        case .settings:
            ProjectSettingsView(document: $document)
        case .packageBuilder:
            PackageBuilderView(document: $document, report: report, workspace: workspace)
        case .buildHistory:
            BuildHistoryView(projectID: document.project.id, workspace: workspace)
        }
    }
}
