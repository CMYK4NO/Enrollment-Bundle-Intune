import AppKit
import SwiftUI

/// Native approximation of the swiftDialog enrollment window: banner, title, logo with information
/// box, message, task list, progress and completion button.
struct DialogMockView: View {
    let project: EnrollmentProject
    let assets: [String: Data]
    let state: PreviewState
    let deviceValues: [Placeholder: String]
    let onSetStatus: (PreviewListItem, TaskStatus?) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var branding: Branding { project.branding }

    var body: some View {
        VStack(spacing: 0) {
            banner
            Text(resolve(branding.title))
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .padding(.horizontal, 24)
            Divider()
                .padding(.top, 12)
            HStack(alignment: .top, spacing: 22) {
                sidebar
                    .frame(width: 180)
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownText(text: resolve(currentMessage))
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                    taskList
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .foregroundStyle(Color.primary)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 6)
        .tint(branding.accentColor.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Static preview of the enrollment dialog")
    }

    // MARK: Regions

    @ViewBuilder
    private var banner: some View {
        if let data = assets[branding.bannerPath ?? ""], let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityLabel("Banner")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            logo
            if branding.showDeviceInfo {
                MarkdownText(text: resolve(branding.infoboxTemplate))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var logo: some View {
        logoImage
            .overlay(alignment: .bottomTrailing) {
                if let data = assets[branding.overlayIconPath ?? ""], let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Overlay icon")
                }
            }
    }

    @ViewBuilder
    private var logoImage: some View {
        if state.outcome == .success || state.outcome == .successWithWarnings {
            Image(systemName: branding.completionSymbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(branding.accentColor.color)
                .frame(width: 120, height: 120)
                .accessibilityLabel("Completion icon")
        } else if let data = assets[branding.logoPath ?? ""], let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .accessibilityLabel("Company logo")
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(branding.accentColor.color.opacity(0.18))
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "building.2")
                        .font(.system(size: 46))
                        .foregroundStyle(branding.accentColor.color)
                )
                .accessibilityLabel("Logo placeholder")
        }
    }

    private var taskList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if state.displayItems.isEmpty {
                    Text("No visible items. Hidden tasks still run in the background.")
                        .font(.callout)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(state.displayItems) { item in
                    taskRow(item)
                        .contextMenu {
                            Menu("Simulate Status") {
                                ForEach(TaskStatus.allCases) { status in
                                    Button(status.title) {
                                        onSetStatus(item, status)
                                    }
                                }
                            }
                            Button("Use Scenario Status") {
                                onSetStatus(item, nil)
                            }
                        }
                }
            }
        }
    }

    private func taskRow(_ item: PreviewListItem) -> some View {
        HStack(spacing: 10) {
            IconSourceImage(icon: item.icon, applicationPath: item.applicationPath, assets: assets, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                    if !item.isRequired {
                        Text("Optional")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                }
                Text(item.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(item.status.isFailure ? Color.red : Color.secondary)
            }
            Spacer()
            StatusIndicator(status: item.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.isRequired ? "required" : "optional"), \(item.status.title)")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: state.progress)
                    .frame(maxWidth: 320)
                Text(progressText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            if !branding.supportContact.isEmpty {
                Text(branding.supportContact)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Button {
            } label: {
                HStack(spacing: 5) {
                    if !state.isButtonEnabled {
                        Image(systemName: "lock.fill")
                    }
                    Text(state.isButtonEnabled ? branding.buttonText : branding.inProgressButtonText)
                }
                .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!state.isButtonEnabled)
            .accessibilityLabel(state.isButtonEnabled ? "\(branding.buttonText), enabled" : "\(branding.inProgressButtonText), locked until required tasks finish")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Helpers

    private var currentMessage: String {
        switch state.outcome {
        case .inProgress: return branding.welcomeMessage
        case .success: return branding.completionMessage
        case .successWithWarnings: return branding.warningMessage
        case .failed: return branding.failureMessage
        }
    }

    private var progressText: String {
        switch state.outcome {
        case .inProgress: return "\(state.finishedCount) of \(state.totalCount) complete"
        case .success: return "Setup complete"
        case .successWithWarnings: return "Setup complete with warnings"
        case .failed: return "Setup needs attention"
        }
    }

    private func resolve(_ text: String) -> String {
        PlaceholderResolver.resolve(text, values: deviceValues)
    }

    private var windowBackground: Color {
        colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.97)
    }

    private var rowBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }
}
