import AppKit
import SwiftUI

/// Previous package builds of this project, newest first. Removing an entry never deletes files.
struct BuildHistoryView: View {
    let projectID: UUID
    @ObservedObject var workspace: WorkspaceViewModel

    @State private var records: [BuildRecord] = []
    @State private var pendingRemoval: BuildRecord?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(records.count) build(s)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding(10)
            Divider()
            if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No builds yet").font(.title3.bold())
                    Text("Packages built in Package Builder appear here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(records) { record in
                    BuildRecordRow(record: record)
                        .contextMenu {
                            Button("Reveal Package in Finder") { reveal(record.packagePath) }
                                .disabled(!FileManager.default.fileExists(atPath: record.packagePath))
                            Button("Open Report") { NSWorkspace.shared.open(URL(fileURLWithPath: record.reportPath)) }
                                .disabled(!FileManager.default.fileExists(atPath: record.reportPath))
                            Button("Copy SHA-256") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.sha256, forType: .string)
                            }
                            Divider()
                            Button("Remove from History…", role: .destructive) { pendingRemoval = record }
                        }
                }
                .listStyle(.inset)
            }
        }
        .task { reload() }
        .confirmationDialog(
            "Remove this build from the history?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { record in
            Button("Remove", role: .destructive) {
                do {
                    try BuildHistoryStore.standard().remove(recordID: record.id, for: projectID)
                    reload()
                } catch {
                    workspace.present(error, title: "Could Not Update Build History")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only the history entry is removed. The package and report files stay where they are.")
        }
    }

    private func reload() {
        records = (try? BuildHistoryStore.standard().records(for: projectID)) ?? []
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

private struct BuildRecordRow: View {
    let record: BuildRecord

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: record.packagePath)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: record.verificationPassed ? "shippingbox.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(record.verificationPassed ? Color.accentColor : Color.orange)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Package \(record.packageVersion)").font(.body.weight(.semibold))
                    Text("bundle \(record.bundleVersion)").font(.caption).foregroundStyle(.secondary)
                    if !exists {
                        Label("File moved or deleted", systemImage: "questionmark.folder").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text(record.builtAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.packagePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("SHA-256 \(record.sha256)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: record.sizeBytes, countStyle: .file)).font(.caption)
                Text("\(record.warningCount) warning(s)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
