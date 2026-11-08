import SwiftUI
import UIKit
import QuickLook

struct NativeHistoryView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NoteSession
    @State private var snapshot: NativeHistorySnapshot?
    @State private var selected: String?
    @State private var plan: NativeHistoryPlan?
    @State private var review = false
    @State private var maintenance: NativeHistoryMaintenancePlan?
    @State private var maintenanceReview = false
    @State private var busy = false
    @State private var issue: String?
    @State private var enabled = true
    @State private var limit = 10
    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    List {
                        if let warning = vault.historyWarning {
                            Section { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange); Button("Retry external history") { Task { await vault.refresh() } } }
                        }
                        Section {
                            Text("Earlier saves are kept automatically. Revisions are separate milestones you create deliberately.").font(.subheadline).foregroundStyle(.secondary)
                            Toggle("Automatic history", isOn: $enabled)
                            Picker("History limit", selection: $limit) {
                                Text("Unlimited").tag(0)
                                ForEach(Array(Set([1, 5, 10, 25, 50, 100, snapshot.limit ?? 0])).filter { $0 > 0 }.sorted(), id: \.self) { Text("\($0) checkpoints").tag($0) }
                            }
                            if enabled != snapshot.enabled || limit != (snapshot.limit ?? 0) {
                                Button("Save history settings") { settings() }.accessibilityIdentifier("history.settings.save")
                            }
                        } footer: { Text("Applies to this vault. A checkpoint includes the changes saved after it. Review older checkpoints before removing them; kept versions and incomplete records stay protected.") }
                        Section("Saved versions") {
                            if snapshot.versions.isEmpty { Text("No earlier saves yet").foregroundStyle(.secondary) }
                            ForEach(snapshot.versions, id: \.path) { version in
                                Button { selected = version.path; issue = nil } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(version.label ?? (NativeRevisionIndex.date(version.timestamp)?.formatted(date: .abbreviated, time: .standard) ?? version.timestamp)).foregroundStyle(.primary)
                                            Text([version.source.capitalized, version.checkpoint ? "Checkpoint" : "Changes", version.alternate ? "Alternate branch" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if version.kept { Image(systemName: "pin.fill").accessibilityLabel("Kept") }
                                        if version.incomplete { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityLabel("Incomplete") }
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }.accessibilityIdentifier("history.version." + version.id)
                            }
                        }
                        ForEach(snapshot.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        if !snapshot.records.isEmpty { Section { Button("Clear this note’s history", systemImage: "trash", role: .destructive) { prepare(.clear) }.accessibilityIdentifier("history.clear") } }
                        if let issue { Text(issue).foregroundStyle(.red) }
                    }
                } else if let issue { ContentUnavailableView { Label("History unavailable", systemImage: "clock.badge.exclamationmark") } description: { Text(issue) } actions: { Button("Try again") { Task { await reload() } } } }
                else { ProgressView("Loading history…") }
            }
            .navigationTitle("Version history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .disabled(busy)
            .overlay { if busy { ProgressView("Preparing history…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .navigationDestination(item: $selected) { id in
                if let snapshot, let version = snapshot.versions.first(where: { $0.path == id }) {
                    NativeHistoryDetail(snapshot: snapshot, version: version, issue: issue, prepare: prepare)
                }
            }
        }
        .task(id: vault.schemaRevision) { await reload() }
        .sheet(isPresented: $review) {
            if let plan { NativeHistoryReview(plan: plan) { try await vault.saveHistory(plan); review = false; selected = nil; await reload() } }
        }
        .sheet(isPresented: $maintenanceReview) {
            if let maintenance { NativeHistoryMaintenanceReview(plan: maintenance) { try await vault.saveHistoryMaintenance(maintenance); maintenanceReview = false; await reload() } }
        }
    }
    private func reload() async {
        do { let next = try await vault.historySnapshot(note: session.document); snapshot = next; enabled = next.enabled; limit = next.limit ?? 0; issue = nil }
        catch { issue = error.localizedDescription }
    }
    private func prepare(_ action: NativeHistoryAction) {
        guard let snapshot, !busy else { return }
        busy = true; issue = nil
        Task { defer { busy = false }; do { plan = try await vault.prepareHistory(snapshot, action: action); review = true } catch { issue = error.localizedDescription } }
    }
    private func settings() {
        guard let snapshot, let workspace = snapshot.workspaceID, !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                let all = try await vault.historyMaintenanceSnapshot(workspace: workspace)
                guard all.configuration.bytes == snapshot.settingsBytes else { throw VaultFailure(message: "History settings changed. Reload before reviewing them.") }
                maintenance = try await vault.prepareHistoryMaintenance(all, intent: .settings(enabled: enabled, limit: limit == 0 ? nil : limit))
                maintenanceReview = true
            } catch { issue = error.localizedDescription }
        }
    }
}

private struct NativeHistoryDetail: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.openURL) private var openURL
    let snapshot: NativeHistorySnapshot
    let version: NativeHistoryVersion
    let issue: String?
    let prepare: (NativeHistoryAction) -> Void
    @State private var mode = 0
    @State private var internalMetadata = false
    @State private var kept = false
    @State private var label = ""
    @State private var preview: String?
    @State private var images: [String: UIImage] = [:]
    @State private var previewIssue: String?
    @State private var file: URL?
    private var visible: String { let value = preview ?? version.content ?? ""; return internalMetadata ? value : NativeHistory.stripped(value) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let date = NativeRevisionIndex.date(version.timestamp) { Text(date, format: .dateTime.day().month().year().hour().minute().second()).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button { kept.toggle() } label: { Label(kept ? "Kept" : "Keep", systemImage: kept ? "pin.fill" : "pin") }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .accessibilityIdentifier("history.keep").accessibilityValue(kept ? "Kept" : "Not kept")
                    TextField("Optional label", text: $label).textFieldStyle(.roundedBorder).accessibilityIdentifier("history.label")
                    if kept != version.kept || label != (version.label ?? "") { Button("Save") { prepare(.update(version.id, kept: kept, label: label)) }.accessibilityIdentifier("history.label.save") }
                }.font(.subheadline)
                Picker("Preview", selection: $mode) { Text("Formatted").tag(0); Text("Source").tag(1); Text("Changes").tag(2) }.pickerStyle(.segmented)
                Toggle("Internal metadata", isOn: $internalMetadata).font(.caption)
                if version.incomplete { Label("Some text or image data is missing or still syncing. Restore is unavailable.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
                if let previewIssue { Text(previewIssue).font(.caption).foregroundStyle(.orange) }
                HStack {
                    ShareLink(item: version.content ?? "", preview: SharePreview(version.label ?? "Saved version")) { Label("Share text", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button("Restore version", systemImage: "arrow.uturn.backward") { prepare(.restore(version.id)) }.disabled(version.incomplete || snapshot.note.trashed).accessibilityIdentifier("history.restore")
                }.font(.subheadline).buttonStyle(.bordered)
            }.padding().background(Accent.paper)
            if mode == 2 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Compared with the current note").font(.caption).foregroundStyle(.secondary)
                        let before = (internalMetadata ? snapshot.note.content : NativeHistory.stripped(snapshot.note.content)).components(separatedBy: "\n")
                        let after = (internalMetadata ? version.content ?? "" : NativeHistory.stripped(version.content ?? "")).components(separatedBy: "\n")
                        let diff = after.difference(from: before)
                        if diff.isEmpty { Text("No text changes") }
                        ForEach(Array(diff.enumerated()), id: \.offset) { _, change in
                            switch change {
                            case .remove(_, let line, _): Text("− " + line).foregroundStyle(.red)
                            case .insert(_, let line, _): Text("+ " + line).foregroundStyle(.green)
                            }
                        }
                    }.font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
                }
            } else {
                RevisionText(markdown: mode == 0 && !internalMetadata ? NoteDocument.split(visible).body : visible, source: mode == 1 || internalMetadata, images: images, open: open, accessibilityID: "history.preview")
            }
        }
        .navigationTitle("Saved version").navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($file)
        .task(id: version.id) {
            kept = version.kept; label = version.label ?? ""; images = [:]
            do {
                let content = try await vault.historyPreview(version, snapshot: snapshot); preview = content
                for reference in MarkdownText.imageReferences(NoteDocument.split(content).body) {
                    guard !Task.isCancelled, reference.range(of: #"^\.zerus/history/blobs/[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                          let bytes = try? await vault.imageData(reference, notePath: snapshot.note.path, workspace: snapshot.workspaceID),
                          NativeHistory.hash(bytes) == (reference as NSString).lastPathComponent, let image = UIImage(data: bytes) else { continue }
                    images[reference] = image
                }
            } catch { previewIssue = error.localizedDescription }
        }
    }
    private func open(_ url: URL) {
        if ["https", "http", "mailto"].contains(url.scheme ?? "") { openURL(url) }
        else {
            let reference = url.scheme == "zerus-image" ? String(url.absoluteString.dropFirst("zerus-image:".count)).removingPercentEncoding : url.scheme == nil ? url.relativeString : nil
            if let reference {
                if reference.hasPrefix("zerus-history-unavailable:") { previewIssue = "This image was not captured with the saved version." }
                else { Task { file = await vault.assetURL(reference, notePath: snapshot.note.path, workspace: snapshot.workspaceID) } }
            }
        }
    }
}

private struct NativeHistoryReview: View {
    @Environment(\.dismiss) private var dismiss
    let plan: NativeHistoryPlan
    let apply: () async throws -> Void
    @State private var saving = false
    @State private var issue: String?
    @State private var confirmClear = false
    private var title: String { switch plan.action { case .restore: "Restore version"; case .update: "Save details"; case .clear: "Clear history" } }
    var body: some View {
        NavigationStack {
            List {
                Section("Review change") {
                    LabeledContent("Note", value: plan.snapshot.note.title)
                    switch plan.action {
                    case .restore: Text("Restore the selected text and its frozen images. Today’s Zerus metadata stays in place. The current text remains recoverable as another history version, including when automatic capture is off.")
                    case .update(_, let kept, let label):
                        Text("Update the label and retention choice. The saved text stays unchanged.")
                        LabeledContent("Keep", value: kept ? "Yes" : "No")
                        LabeledContent("Label", value: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : label)
                    case .clear: Text("Permanently delete all \(plan.snapshot.records.count) history records for this note, including kept and unsupported versions. The current note, deliberate revisions and live images stay unchanged. Unused history images may also be removed. This cannot be undone.")
                    }
                }
                if let maintenance = plan.maintenance {
                    LabeledContent("Unused history images", value: String(maintenance.removedBlobs.count))
                    ForEach(maintenance.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
                if let content = plan.content { Section("Resulting note") { Text(NativeHistory.stripped(content)).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
                if let issue { Text(issue).foregroundStyle(.red) }
            }
            .navigationTitle("Review history").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(title) { if case .clear = plan.action { confirmClear = true } else { save() } }.disabled(saving).accessibilityIdentifier("history.confirm") }
            }
            .confirmationDialog("Permanently clear this note’s history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all saved versions", role: .destructive) { save() }
                Button("Cancel", role: .cancel) {}
            }
            .interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Saving history…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
    private func save() { saving = true; Task { defer { saving = false }; do { try await apply() } catch { issue = error.localizedDescription } } }
}
