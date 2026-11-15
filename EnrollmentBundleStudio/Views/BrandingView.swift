import AppKit
import SwiftUI

/// Organization identity, dialog text, images, colour and support information.
struct BrandingView: View {
    @Binding var document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel

    var body: some View {
        Form {
            Section("Organization and title") {
                ValidatedTextField(
                    title: "Organization name",
                    text: $document.project.settings.organizationNameLinkedToIdentifiers,
                    prompt: "Contoso",
                    issue: FieldValidator.requiredTextIssue(document.project.settings.organizationName)
                )
                PlaceholderTextField(title: "Window title", text: $document.project.branding.title)
                TextField("Completion button text", text: $document.project.branding.buttonText)
                TextField("Button text while in progress", text: $document.project.branding.inProgressButtonText)
            }

            Section("Messages") {
                PlaceholderTextField(title: "Welcome message", text: $document.project.branding.welcomeMessage, multiline: true)
                PlaceholderTextField(title: "Completion message", text: $document.project.branding.completionMessage, multiline: true)
                PlaceholderTextField(title: "Warning message", text: $document.project.branding.warningMessage, multiline: true)
                PlaceholderTextField(title: "Failure message", text: $document.project.branding.failureMessage, multiline: true)
                Text("Messages support inline Markdown such as **bold** and *italic*.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Images and color") {
                ImageAssetRow(
                    title: BrandingImageRole.logo.title,
                    path: document.project.branding.logoPath,
                    data: document.assetData(at: document.project.branding.logoPath),
                    recommendation: "Square PNG, 512 × 512 pixels or larger.",
                    onChoose: { chooseImage(for: .logo) },
                    onRemove: { document.removeBrandingImage(.logo) }
                )
                ImageAssetRow(
                    title: BrandingImageRole.banner.title,
                    path: document.project.branding.bannerPath,
                    data: document.assetData(at: document.project.branding.bannerPath),
                    recommendation: "Optional. Wide PNG or JPEG, about 1200 × 200 pixels.",
                    onChoose: { chooseImage(for: .banner) },
                    onRemove: { document.removeBrandingImage(.banner) }
                )
                ImageAssetRow(
                    title: BrandingImageRole.overlay.title,
                    path: document.project.branding.overlayIconPath,
                    data: document.assetData(at: document.project.branding.overlayIconPath),
                    recommendation: "Optional. Small square PNG shown as a badge over the dialog icon.",
                    onChoose: { chooseImage(for: .overlay) },
                    onRemove: { document.removeBrandingImage(.overlay) }
                )
                ColorPicker("Accent color", selection: accentColorBinding.deferringWrites(), supportsOpacity: false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Completion icon (SF Symbol)", text: $document.project.branding.completionSymbol)
                        Image(systemName: isKnownSymbol ? document.project.branding.completionSymbol : "questionmark.square.dashed")
                            .font(.title2)
                            .foregroundStyle(document.project.branding.accentColor.color)
                            .accessibilityHidden(true)
                    }
                    if !isKnownSymbol {
                        FieldIssueLabel(message: "Unknown SF Symbol name.", severity: .warning)
                    }
                }
            }

            Section("Window") {
                Toggle("Blur the screen behind the dialog", isOn: $document.project.branding.blurScreen)
                Text("The dialog always opens as a normal window using the size set in Settings. On: swiftDialog blurs the rest of the screen behind it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Information box") {
                Toggle("Show device information", isOn: $document.project.branding.showDeviceInfo)
                if document.project.branding.showDeviceInfo {
                    PlaceholderTextField(title: "Information box text", text: $document.project.branding.infoboxTemplate, multiline: true)
                }
            }

            Section("Support") {
                TextField("Support contact", text: $document.project.branding.supportContact, prompt: Text("IT Service Desk, +1 555 0100"))
                ValidatedTextField(
                    title: "Support URL",
                    text: $document.project.branding.supportURL,
                    prompt: "https://support.example.com",
                    issue: FieldValidator.urlIssue(document.project.branding.supportURL)
                )
            }

            Section("Available placeholders") {
                ForEach(Placeholder.allCases) { placeholder in
                    HStack(alignment: .firstTextBaseline) {
                        Text(placeholder.token)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(minWidth: 150, alignment: .leading)
                        Text(placeholder.explanation)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Placeholders are replaced on the device when enrollment runs. Matching ignores case. Insert buttons add the token at the end of the field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var isKnownSymbol: Bool {
        NSImage(systemSymbolName: document.project.branding.completionSymbol, accessibilityDescription: nil) != nil
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { document.project.branding.accentColor.color },
            set: { newValue in
                if let hex = HexColor(color: newValue), hex != document.project.branding.accentColor {
                    document.project.branding.accentColor = hex
                }
            }
        )
    }

    private func chooseImage(for role: BrandingImageRole) {
        Task {
            let urls = await FilePanels.openFiles(title: "Choose the \(role.title)", allowedContentTypes: AssetImporter.allowedImageTypes)
            guard let url = urls.first else { return }
            do {
                let data = try AssetImporter.readFile(at: url)
                let format = try AssetImporter.validateImage(data)
                let path = AssetImporter.brandingPath(role: role, format: format)
                var updated = document
                try updated.replaceBrandingImage(role, data: data, path: path)
                document = updated
            } catch {
                workspace.present(error, title: "Could Not Import Image")
            }
        }
    }
}
