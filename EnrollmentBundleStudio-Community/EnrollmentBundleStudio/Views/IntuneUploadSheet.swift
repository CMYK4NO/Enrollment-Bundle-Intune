import AppKit
import SwiftUI

/// Uploads the built package to Intune as a macOS app (PKG), using the Microsoft Entra IDs from Settings.
/// The administrator signs in through the browser on the first upload; the sign-in is renewed or repeated only when it expires.
struct IntuneUploadSheet: View {
    let packageURL: URL
    let identifier: String
    let version: String
    let minimumMacOS: String
    /// Text of the pre-install script that is set on the app, or nil for none.
    let preInstallScript: String?

    @State private var displayName: String
    @State private var publisher: String
    @State private var appDescription: String
    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case idle
        case working(String, Double?)
        case done(URL, preInstallScriptAdded: Bool)
        case failed(String)
    }

    init(packageURL: URL, identifier: String, version: String, minimumMacOS: String, displayName: String, publisher: String,
         preInstallScript: String? = nil) {
        self.preInstallScript = preInstallScript
        self.packageURL = packageURL
        self.identifier = identifier
        self.version = version
        self.minimumMacOS = minimumMacOS
        _displayName = State(initialValue: displayName)
        _publisher = State(initialValue: publisher)
        _appDescription = State(initialValue: "Enrollment experience for new Macs. Shows progress while required apps are deployed.")
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var isConfigured: Bool { IntuneConnectionStore.shared.load().isComplete }

    private var canStart: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !publisher.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking && isConfigured
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
                    if preInstallScript != nil {
                        Text("The app is created with a pre-install script (the same file as intune/pre-install.sh in the export). It stops the installation on Macs that already have the onboarding flag.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch phase {
        case .idle:
            if !isConfigured {
                Label("Enter your Microsoft Entra tenant ID and client ID in Settings (app menu > Settings…, Microsoft Entra tab) before uploading.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
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
        case .done(_, let preInstallScriptAdded):
            VStack(alignment: .leading, spacing: 6) {
                Label("Uploaded. The app is in Intune and ready to assign.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if preInstallScript != nil {
                    if preInstallScriptAdded {
                        Label("The pre-install script is set on the app.", systemImage: "checkmark.circle")
                            .font(.callout)
                    } else {
                        Label("Intune did not accept the pre-install script, so the app was created without it. In Intune, open the app > Properties > Pre-install script and paste the contents of intune/pre-install.sh from the export.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
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
            if case .done(let portalURL, _) = phase {
                Button("Open in Intune") { NSWorkspace.shared.open(portalURL) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Upload to Intune") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
        .padding(12)
    }

    private func start() {
        guard canStart else { return }
        let request = IntuneUploadRequest(
            packageURL: packageURL,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: appDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            publisher: publisher.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: identifier,
            bundleVersion: version,
            minimumMacOS: minimumMacOS,
            preInstallScript: preInstallScript
        )
        phase = .working("Starting the upload…", nil)
        task = Task {
            do {
                let token = try await AuthSession.shared.validToken {
                    phase = .working("Sign in with Microsoft in your browser…", nil)
                }
                let result = try await IntunePackageUploader().upload(request: request, token: token) { text, fraction in
                    // Progress arrives asynchronously; never let a late update replace the finished, failed or cancelled state.
                    Task { @MainActor in
                        if case .working = phase { phase = .working(text, fraction) }
                    }
                }
                await MainActor.run { phase = .done(result.portalURL, preInstallScriptAdded: result.preInstallScriptAdded) }
            } catch is CancellationError {
                await MainActor.run { phase = .idle }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { phase = .failed(message) }
            }
        }
    }
}
