import AppKit
import SwiftUI

/// Signs in to Microsoft Entra in the default browser and uploads the built package to Intune as a
/// macOS app (PKG). The access token is kept in memory for this upload only.
struct IntuneUploadSheet: View {
    let packageURL: URL
    let identifier: String
    let version: String
    let minimumMacOS: String

    @AppStorage("intune.tenantID") private var tenantID = ""
    @AppStorage("intune.clientID") private var clientID = ""
    @State private var displayName: String
    @State private var publisher: String
    @State private var appDescription: String
    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case idle
        case working(String, Double?)
        case done(URL)
        case failed(String)
    }

    init(packageURL: URL, identifier: String, version: String, minimumMacOS: String, displayName: String, publisher: String) {
        self.packageURL = packageURL
        self.identifier = identifier
        self.version = version
        self.minimumMacOS = minimumMacOS
        _displayName = State(initialValue: displayName)
        _publisher = State(initialValue: publisher)
        _appDescription = State(initialValue: "Enrollment experience for new Macs. Shows progress while required apps are deployed.")
    }

    private var settings: IntuneConnectionSettings {
        IntuneConnectionSettings(tenantID: tenantID, clientID: clientID)
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var canStart: Bool {
        settings.isValid && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !publisher.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Package") {
                    LabeledContent("File") {
                        Text(packageURL.lastPathComponent).font(.callout.monospaced()).textSelection(.enabled)
                    }
                    LabeledContent("Identifier", value: identifier)
                    LabeledContent("Version", value: version)
                }
                Section("Intune app") {
                    TextField("Name", text: $displayName)
                    TextField("Publisher", text: $publisher)
                    TextField("Description", text: $appDescription, axis: .vertical)
                        .lineLimit(2...4)
                    Text("Created as a macOS app (PKG), the app type that accepts unsigned packages. Minimum macOS: \(minimumMacOS). Assign it to your enrollment group in Intune afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Microsoft Entra sign-in") {
                    TextField("Directory (tenant) ID", text: $tenantID, prompt: Text("contoso.onmicrosoft.com or a GUID"))
                    if !tenantID.isEmpty, let issue = settings.tenantIssue {
                        FieldIssueLabel(message: issue, severity: .error)
                    }
                    TextField("Application (client) ID", text: $clientID, prompt: Text("00000000-0000-0000-0000-000000000000"))
                    if !clientID.isEmpty, let issue = settings.clientIssue {
                        FieldIssueLabel(message: issue, severity: .error)
                    }
                    Text("Sign-in opens your default browser. No password or token is stored by this app; the values above are only identifiers and are remembered on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("One-time setup in Microsoft Entra") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Entra admin center > App registrations > New registration (this organization only).")
                            Text("2. Authentication > Add a platform > Mobile and desktop applications, and add the redirect URI http://localhost. Turn on Allow public client flows.")
                            Text("3. API permissions > Add > Microsoft Graph > Delegated > DeviceManagementApps.ReadWrite.All, then grant admin consent.")
                            Text("4. Copy the Directory (tenant) ID and the Application (client) ID from the Overview page into the fields above.")
                            Text("The person who signs in needs an Intune role that can add apps, such as Application Manager.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    statusView
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 560, idealHeight: 680)
        .interactiveDismissDisabled(isWorking)
    }

    @ViewBuilder
    private var statusView: some View {
        switch phase {
        case .idle:
            Text("The package is encrypted and uploaded to your Intune tenant. It includes the enrollment scripts, so upload it only to a tenant you trust.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .working(let text, let fraction):
            VStack(alignment: .leading, spacing: 6) {
                if let fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(text).font(.callout)
            }
        case .done(let url):
            VStack(alignment: .leading, spacing: 6) {
                Label("Uploaded. The app is in Intune and ready to assign.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Open in Intune") { NSWorkspace.shared.open(url) }
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(isWorking ? "Cancel Upload" : "Close") {
                if isWorking {
                    task?.cancel()
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
            Button("Sign In and Upload") { start() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
        }
        .padding(12)
    }

    private func start() {
        guard canStart else { return }
        let connection = settings
        let request = IntuneUploadRequest(
            packageURL: packageURL,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: appDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            publisher: publisher.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: identifier,
            bundleVersion: version,
            minimumMacOS: minimumMacOS
        )
        phase = .working("Opening your browser to sign in…", nil)
        task = Task {
            do {
                let token = try await IntuneAuthenticator().signIn(settings: connection)
                await MainActor.run { phase = .working("Signed in. Starting the upload…", nil) }
                let result = try await IntunePackageUploader().upload(request: request, token: token) { text, fraction in
                    Task { @MainActor in phase = .working(text, fraction) }
                }
                await MainActor.run { phase = .done(result.portalURL) }
            } catch is CancellationError {
                await MainActor.run { phase = .idle }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { phase = .failed(message) }
            }
        }
    }
}
