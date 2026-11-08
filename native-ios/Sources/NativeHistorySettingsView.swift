import SwiftUI

struct NativeHistorySettingsView: View {
    @EnvironmentObject private var vault: VaultStore
    let workspaceID: UUID
    @State private var snapshot: NativeHistoryMaintenanceSnapshot?
    @State private var enabled = true
    @State private var limit = 10
    @State private var busy = false
    @State private var issue: String?
    @State private var plan: NativeHistoryMaintenancePlan?
    @State private var review = false
    var body: some View {
        Group {
            if let snapshot {
                Form {
                    if let warning = vault.historyWarning {
                        Section { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange); Button("Retry external history") { Task { await vault.refresh() } } }
                    }
                    Section("Saved history") {
                        LabeledContent("Versions", value: String(snapshot.records.count)).accessibilityIdentifier("history.management.count")
                        LabeledContent("Kept versions", value: String(snapshot.groups.flatMap(\.versions).filter(\.kept).count))
                        LabeledContent("Saved images", value: String(snapshot.inventory.blobs.count))
                    }
                    Section {
                        Toggle("Automatic history", isOn: $enabled).accessibilityIdentifier("history.management.enabled")
                        Picker("History limit", selection: $limit) {
                            Text("Unlimited").tag(0)
                            ForEach(Array(Set([1, 5, 10, 25, 50, 100, snapshot.configuration.limit ?? 0])).filter { $0 > 0 }.sorted(), id: \.self) { Text("\($0) checkpoints").tag($0) }
                        }.accessibilityIdentifier("history.management.limit")
                        if enabled != snapshot.configuration.enabled || limit != (snapshot.configuration.limit ?? 0) {
                            Button("Review history settings") { prepare(.settings(enabled: enabled, limit: limit == 0 ? nil : limit)) }.accessibilityIdentifier("history.management.settings")
                        }
                    } header: { Text("Capture and retention") } footer: {
                        Text("Applies to this vault. A checkpoint includes the changes saved after it. The review shows older versions and unused images to remove now. Kept versions and incomplete history stay protected from automatic pruning.")
                    }
                    Section {
                        Button("Review unused image cleanup", systemImage: "photo.badge.checkmark") { prepare(.cleanup) }.accessibilityIdentifier("history.management.cleanup")
                        Button("Review clearing all history", systemImage: "trash", role: .destructive) { prepare(.clearAll) }.disabled(snapshot.records.isEmpty && snapshot.inventory.blobs.isEmpty).accessibilityIdentifier("history.management.clear")
                    } footer: { Text("Clearing history removes automatic and kept versions across this vault, including history of deleted or missing notes. Current notes, deliberate revisions, live images and audit/recovery records are preserved.") }
                    let incomplete = snapshot.groups.flatMap(\.versions).filter(\.incomplete).count
                    if incomplete > 0 { Text("\(incomplete) versions have missing text or images. They remain protected during retention changes.").font(.caption).foregroundStyle(.orange) }
                    ForEach(snapshot.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    if let issue { Section { Text(issue).foregroundStyle(.red); Button("Reload") { Task { await reload() } } } }
                }
            } else if let issue {
                ContentUnavailableView { Label("History settings unavailable", systemImage: "clock.badge.exclamationmark") } description: { Text(issue) } actions: { Button("Try again") { Task { await reload() } } }
            } else { ProgressView("Loading vault history…") }
        }
        .navigationTitle("Version history").navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .overlay { if busy { ProgressView("Preparing review…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .task(id: vault.schemaRevision) { await reload() }
        .sheet(isPresented: $review) {
            if let plan { NativeHistoryMaintenanceReview(plan: plan) { try await vault.saveHistoryMaintenance(plan); review = false; await reload() } }
        }
    }
    private func reload() async {
        do {
            let next = try await vault.historyMaintenanceSnapshot(workspace: workspaceID)
            snapshot = next; enabled = next.configuration.enabled; limit = next.configuration.limit ?? 0; issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func prepare(_ intent: NativeHistoryMaintenanceIntent) {
        guard let snapshot, !busy else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { plan = try await vault.prepareHistoryMaintenance(snapshot, intent: intent); review = true } catch { issue = error.localizedDescription } }
    }
}

struct NativeHistoryMaintenanceReview: View {
    @Environment(\.dismiss) private var dismiss
    let plan: NativeHistoryMaintenancePlan
    let apply: () async throws -> Void
    @State private var saving = false
    @State private var confirmation = false
    @State private var issue: String?
    private var deletes: Bool { !plan.removedRecords.isEmpty || !plan.removedBlobs.isEmpty }
    private var hasChanges: Bool { plan.changes.contains { $0.before != $0.after } }
    var body: some View {
        NavigationStack {
            List {
                Section("Review change") {
                    switch plan.intent {
                    case .settings(let enabled, let limit):
                        LabeledContent("Automatic history", value: enabled ? "On" : "Off")
                        LabeledContent("History limit", value: limit.map { "\($0) checkpoints" } ?? "Unlimited")
                    case .cleanup: Text("Remove history images that no surviving version, note, revision or recovery record uses.")
                    case .clearAll: Text("Permanently clear all automatic and kept versions in this vault, including deleted and missing notes.")
                    case .clearNote: Text("Permanently clear this note’s automatic and kept versions.")
                    }
                    LabeledContent("Versions to delete", value: String(plan.removedRecords.count))
                    LabeledContent("Known kept versions to delete", value: String(plan.keptRemoved))
                    if plan.unrecognizedRemoved > 0 { LabeledContent("Unsupported records to delete", value: String(plan.unrecognizedRemoved)) }
                    LabeledContent("Unused images to delete", value: String(plan.removedBlobs.count))
                    LabeledContent("Space to free", value: ByteCountFormatter.string(fromByteCount: Int64(plan.bytesRemoved), countStyle: .file))
                    if deletes { Text("Deletion cannot be undone. Current notes, deliberate revisions and live images stay unchanged.").foregroundStyle(.secondary) }
                    else if !hasChanges { Text("Nothing to remove. Saved images are still used or protected.").foregroundStyle(.secondary) }
                }
                if !plan.removedRecords.isEmpty {
                    Section("Versions to remove") {
                        ForEach(plan.removedRecords, id: \.self) { path in
                            let group = plan.snapshot.groups.first { path.hasPrefix(".zerus/history/notes/" + $0.id + "/") }
                            let version = group?.versions.first { $0.path == path }
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(group?.title ?? "Unrecognized history")
                                    if version?.kept == true { Image(systemName: "pin.fill").accessibilityLabel("Kept") }
                                }
                                if let date = version.flatMap({ NativeRevisionIndex.date($0.timestamp) }) { Text(date, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                                Text(path).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                            }
                        }
                    }
                }
                if !plan.removedBlobs.isEmpty { Section("Unused image files") { ForEach(plan.removedBlobs, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } } }
                if !plan.warnings.isEmpty { Section("Preserved data") { ForEach(plan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } } }
                if let issue { Text(issue).foregroundStyle(.red) }
            }
            .navigationTitle("Review history changes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("history.management.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Apply changes") { if deletes { confirmation = true } else { save() } }.disabled(saving || !hasChanges).accessibilityIdentifier("history.management.commit") }
            }
            .confirmationDialog("Permanently delete \(plan.removedRecords.count) versions and \(plan.removedBlobs.count) unused images?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Delete reviewed history", role: .destructive) { save() }.accessibilityIdentifier("history.management.delete")
                Button("Cancel", role: .cancel) {}.accessibilityIdentifier("history.management.confirm.cancel")
            } message: { Text("This includes \(plan.keptRemoved) known kept versions and \(plan.unrecognizedRemoved) unsupported records. The reviewed deletion cannot be undone.") }
            .interactiveDismissDisabled(saving)
            .overlay { if saving { ProgressView("Updating history…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
    private func save() { saving = true; Task { defer { saving = false }; do { try await apply() } catch { issue = error.localizedDescription } } }
}
