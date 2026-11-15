import SwiftUI

/// Static, native preview of the enrollment dialog. Does not need swiftDialog, runs nothing and
/// reads no files outside the project.
struct PreviewView: View {
    let document: EnrollmentProjectDocument
    @ObservedObject var workspace: WorkspaceViewModel
    @StateObject private var player = SimulationPlayer()
    @StateObject private var live = LiveDialogPreviewController()

    var body: some View {
        let state = PreviewBuilder.makeState(
            project: document.project,
            scenario: workspace.previewScenario,
            overrides: workspace.previewStatusOverrides
        )
        VStack(spacing: 0) {
            controls
            actions
            Divider()
            canvas(state: state)
            Divider()
            statusBar(state: state)
        }
        // Mirror every change of the static preview into the live swiftDialog window, after the update.
        .task(id: state) {
            live.apply(state: state, project: document.project, deviceValues: deviceInfo.values)
        }
        .onDisappear {
            player.stop()
            live.stop()
        }
    }

    /// Simulation and live preview. Neither runs enrollment scripts, installs anything or needs admin rights.
    private var actions: some View {
        HStack(spacing: 12) {
            if player.isPlaying {
                Button {
                    player.stop()
                } label: {
                    Label("Stop Simulation", systemImage: "stop.fill")
                }
                Text(player.currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Button {
                    startSimulation()
                } label: {
                    Label("Simulate", systemImage: "play.fill")
                }
                .help("Play a timed run of the selected scenario: tasks wait, run and finish in run order.")
            }
            Divider().frame(height: 18)
            liveControls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var liveControls: some View {
        switch live.phase {
        case .running:
            Button {
                live.stop()
            } label: {
                Label("Stop Live Preview", systemImage: "xmark.circle")
            }
            Text("swiftDialog is open and follows this preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
            Text("Checking swiftDialog…").font(.caption).foregroundStyle(.secondary)
        case .idle, .unavailable, .failed:
            Button {
                startLivePreview()
            } label: {
                Label("Live Preview", systemImage: "macwindow")
            }
            .help("Open the real swiftDialog with a temporary configuration. Simulated statuses only; nothing is executed.")
            if case .unavailable(let reason) = live.phase {
                Text(reason).font(.caption).foregroundStyle(.orange).lineLimit(2)
            } else if case .failed(let reason) = live.phase {
                Text(reason).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
    }

    private func startSimulation() {
        let steps = SimulationTimeline.make(project: document.project, scenario: workspace.previewScenario)
        player.play(steps) { overrides in
            workspace.previewStatusOverrides = overrides
        }
    }

    private func startLivePreview() {
        let state = PreviewBuilder.makeState(
            project: document.project,
            scenario: workspace.previewScenario,
            overrides: workspace.previewStatusOverrides
        )
        Task {
            await live.start(project: document.project, assets: document.assets, deviceValues: deviceInfo.values, state: state)
        }
    }

    /// One stable bar: labels never wrap and every control keeps its natural size. When the window is too
    /// narrow for one row, ViewThatFits switches to two rows instead of squeezing the labels, so the bar's
    /// height never fluctuates and the preview canvas below keeps a steady scale.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                scenarioControl
                valuesControl
                appearanceControl
                Spacer(minLength: 12)
                resetButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    scenarioControl
                    Spacer(minLength: 12)
                    resetButton
                }
                HStack(spacing: 18) {
                    valuesControl
                    appearanceControl
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var scenarioControl: some View {
        labeled("Scenario") {
            Picker("Scenario", selection: $workspace.previewScenario.deferringWrites()) {
                ForEach(PreviewScenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var valuesControl: some View {
        labeled("Values") {
            Picker("Values", selection: $workspace.previewDeviceSource.deferringWrites()) {
                ForEach(PreviewDeviceSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var appearanceControl: some View {
        labeled("Appearance") {
            Picker("Appearance", selection: $workspace.previewAppearance.deferringWrites()) {
                ForEach(PreviewAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var resetButton: some View {
        Button("Reset Statuses") {
            workspace.previewStatusOverrides.removeAll()
        }
        .disabled(workspace.previewStatusOverrides.isEmpty)
        .fixedSize()
    }

    /// A one-line label in front of a control. The control keeps its accessibility label.
    private func labeled<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            control()
                .accessibilityLabel(title)
        }
    }

    private func canvas(state: PreviewState) -> some View {
        let settings = document.project.settings
        let width = CGFloat(min(max(settings.windowWidth, ProjectSettings.windowWidthRange.lowerBound), ProjectSettings.windowWidthRange.upperBound))
        let height = CGFloat(min(max(settings.windowHeight, ProjectSettings.windowHeightRange.lowerBound), ProjectSettings.windowHeightRange.upperBound))
        return GeometryReader { geometry in
            let available = CGSize(width: max(geometry.size.width - 48, 100), height: max(geometry.size.height - 48, 100))
            let fitted = min(1, min(available.width / width, available.height / height))
            let scale = max(0.3, (fitted * 50).rounded(.down) / 50)
            appearanceApplied(
                DialogMockView(
                    project: document.project,
                    assets: document.assets,
                    state: state,
                    deviceValues: deviceInfo.values,
                    onSetStatus: { item, status in
                        workspace.setPreviewStatus(status, for: item.memberIDs)
                    }
                )
            )
            .frame(width: width, height: height)
            .scaleEffect(scale)
            .frame(width: width * scale, height: height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func appearanceApplied<Content: View>(_ content: Content) -> some View {
        if let scheme = workspace.previewAppearance.colorScheme {
            content.environment(\.colorScheme, scheme)
        } else {
            content
        }
    }

    private var deviceInfo: PreviewDeviceInfo {
        let organization = document.project.settings.organizationName
        switch workspace.previewDeviceSource {
        case .sample: return .sample(organizationName: organization)
        case .thisMac: return .currentMac(organizationName: organization)
        }
    }

    private func statusBar(state: PreviewState) -> some View {
        HStack(spacing: 16) {
            Label(
                state.isButtonEnabled ? "Completion button unlocked" : "Completion button locked",
                systemImage: state.isButtonEnabled ? "lock.open" : "lock"
            )
            Text("\(state.finishedCount) of \(state.totalCount) tasks finished")
            if state.hiddenCount > 0 {
                Text("\(state.hiddenCount) hidden background task(s) included")
            }
            Spacer()
            Text("Right-click an item to set its status. Simulate plays a run; Live Preview opens the real swiftDialog.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
