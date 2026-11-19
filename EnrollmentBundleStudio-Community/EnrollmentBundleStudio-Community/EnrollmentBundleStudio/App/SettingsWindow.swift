import SwiftUI

enum SettingsWindow {
    static let id = "project-settings"
}

/// The project window that asked for the Settings window, so Save can write the values into it.
struct SettingsContext {
    let id: UUID
    let projectName: String
    let isReadOnly: Bool
    let document: Binding<EnrollmentProjectDocument>
}

struct SettingsContextFocusedValueKey: FocusedValueKey {
    typealias Value = SettingsContext
}

extension FocusedValues {
    var settingsContext: SettingsContext? {
        get { self[SettingsContextFocusedValueKey.self] }
        set { self[SettingsContextFocusedValueKey.self] = newValue }
    }
}

/// Holds the project the Settings window saves into.
///
/// Focused values follow the key window, so they are empty while the Settings window itself is key.
/// The target is therefore captured when the menu item is chosen and released when its project window closes.
@MainActor
final class SettingsWindowModel: ObservableObject {
    static let shared = SettingsWindowModel()

    @Published private(set) var context: SettingsContext?

    func show(_ context: SettingsContext?) {
        self.context = context
    }

    func clear(id: UUID) {
        guard context?.id == id else { return }
        context = nil
    }
}

/// App-wide Settings window. Edits a draft; Save stores it as the defaults for new projects and writes it
/// into the project the window was opened from. The Microsoft Entra tab is app-wide only and never enters a project.
struct ProjectSettingsWindowView: View {
    @ObservedObject private var model = SettingsWindowModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var values = AppSettingsStore.shared.load()
    @State private var savedValues = AppSettingsStore.shared.load()
    @State private var connection = IntuneConnectionStore.shared.load()
    @State private var savedConnection = IntuneConnectionStore.shared.load()
    @State private var message: String?
    @State private var isShowingRestoreConfirmation = false

    private let store = AppSettingsStore.shared
    private let connectionStore = IntuneConnectionStore.shared

    private var hasUnsavedChanges: Bool { values != savedValues || connection.normalized != savedConnection }
    private var canSave: Bool { values.isValid && connection.isSavable }

    /// The open project that Save also writes into; nil when there is none or it is read-only.
    private var targetProject: SettingsContext? {
        guard let context = model.context, !context.isReadOnly else { return nil }
        return context
    }

    private var projectDiffers: Bool {
        guard let targetProject else { return false }
        return RuntimeSettingsDefaults(targetProject.document.wrappedValue.project.settings) != values
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ProjectSettingsView(values: $values)
                    .tabItem { Text("Enrollment") }
                EntraSettingsView(connection: $connection)
                    .tabItem { Text("Microsoft Entra") }
            }
            .padding(.top, 8)
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear(perform: reload)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Restore the built-in settings?",
            isPresented: $isShowingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Built-in Settings", role: .destructive) {
                store.reset()
                values = .builtIn()
                savedValues = .builtIn()
                message = "Built-in settings restored."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New projects will use the built-in values again. Open projects and the Microsoft Entra IDs are not changed.")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Restore Built-in…") {
                isShowingRestoreConfirmation = true
            }
            Spacer()
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if hasUnsavedChanges && !canSave {
                Text("Fix the highlighted fields to save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let targetProject {
                // The target is otherwise invisible: it is the project that was in front when Settings was opened.
                Text("Save also applies to “\(targetProject.projectName)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave || !(hasUnsavedChanges || projectDiffers))
            .help(targetProject.map { "Save as the defaults for new projects and apply to “\($0.projectName)”" }
                  ?? "Save as the defaults for new projects")
        }
        .padding(12)
        .onChange(of: values) { _ in
            message = nil
        }
        .onChange(of: connection) { _ in
            message = nil
        }
    }

    /// Starts from what is stored, so a window that was closed and reopened never shows stale edits.
    private func reload() {
        values = store.load()
        savedValues = values
        connection = connectionStore.load()
        savedConnection = connection
        message = nil
    }

    private func save() {
        let normalizedConnection = connection.normalized
        do {
            try store.save(values)
            try connectionStore.save(normalizedConnection)
            savedValues = values
            connection = normalizedConnection
            savedConnection = normalizedConnection
        } catch {
            message = "Could not save: \(error.localizedDescription)"
            return
        }
        if let targetProject {
            var document = targetProject.document.wrappedValue
            values.apply(to: &document.project.settings)
            targetProject.document.wrappedValue = document
        }
        dismiss()
    }
}

/// Tenant ID and client ID of the administrator's own Microsoft Entra app registration, used by Upload to Intune.
struct EntraSettingsView: View {
    @Binding var connection: IntuneConnection

    var body: some View {
        Form {
            Section("App registration") {
                ValidatedTextField(
                    title: "Tenant ID",
                    text: $connection.tenantID,
                    prompt: "00000000-0000-0000-0000-000000000000",
                    issue: issue(for: connection.tenantID)
                )
                ValidatedTextField(
                    title: "Client ID",
                    text: $connection.clientID,
                    prompt: "00000000-0000-0000-0000-000000000000",
                    issue: issue(for: connection.clientID)
                )
                if connection.isEmpty {
                    Text("Not configured. Upload to Intune stays unavailable until both IDs are entered; everything else works without them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Use the Directory (tenant) ID and Application (client) ID of your own app registration; see docs/PACKAGING_AND_DEPLOYMENT.md for the one-time setup. They are identifiers, not secrets, and the app has no client secret. They are kept in this Mac's preferences, never in a project, an export or a package. Sign-in happens in your browser when you upload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Nothing is flagged while both fields are empty; that is the "not configured" state, not a mistake.
    private func issue(for value: String) -> String? {
        connection.isEmpty ? nil : IntuneConnection.idIssue(value)
    }
}
