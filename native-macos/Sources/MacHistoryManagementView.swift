import SwiftUI

struct MacHistoryManagementView: View {
    @Bindable var workspace: MacWorkspace
    @State private var workspaceID: UUID
    private let noteID: String?
    @State private var snapshot: MacHistoryManagementSnapshot?
    @State private var review: MacHistoryManagementReview?
    @State private var enabled = true
    @State private var unlimited = false
    @State private var limit = 10
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var issue: String?
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macSettingsEmbedded) private var embedded
    init(workspace: MacWorkspace, noteID: String? = nil) { self.workspace = workspace; self.noteID = noteID; _workspaceID = State(initialValue: workspace.workspaceID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !embedded || review != nil || busy { HStack { if !embedded || review != nil { Text(review == nil ? "Version history settings" : "Review history changes").font(embedded ? .headline : .title2.bold()) }; Spacer(); if busy { ProgressView().controlSize(.small) }; if !embedded { Button("Done") { dismiss() } } } }
            if let review { reviewPane(review) }
            else if let snapshot { settings(snapshot) }
            else { ContentUnavailableView("History settings", systemImage: "clock.arrow.circlepath", description: Text(issue ?? "Loading saved versions and recovery references…")); Button("Retry") { Task { await reload() } } }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.macSettingsChrome(width: 780, height: 650).disabled(busy).interactiveDismissDisabled(busy)
        .task { await reload() }
        .onChange(of: workspace.workspaceID) { snapshot = nil; review = nil; issue = "The vault changed. Close and reopen history settings." }
        .confirmationDialog("Permanently delete the reviewed history?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete reviewed history", role: .destructive) { if let review { commit(review) } }
            Button("Cancel", role: .cancel) {}
        } message: { if let review { Text(counted(review.plan.removedRecords.count, "version") + " (\(review.plan.keptRemoved) kept) and " + counted(review.plan.removedBlobs.count, "unused image") + " will be deleted. This cannot be undone.") } }
    }
    private func settings(_ snapshot: MacHistoryManagementSnapshot) -> some View {
        let data = snapshot.history
        return ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text(workspace.vaultTitle).font(.headline)
            HStack(spacing: 30) { metric("Versions", data.records.count); metric("Kept", data.groups.flatMap(\.versions).filter(\.kept).count); metric("Saved images", data.inventory.blobs.count) }
            Divider()
            Toggle("Automatic history", isOn: $enabled)
            Toggle("Unlimited checkpoints", isOn: $unlimited)
            if !unlimited { HStack { Text("Checkpoint limit"); TextField("1–100", value: $limit, format: .number).textFieldStyle(.roundedBorder).frame(width: 75); Stepper("Checkpoint limit", value: $limit, in: 1...100).labelsHidden() } }
            Text("Applies to this vault. Each checkpoint includes the changes saved after it. Kept versions and incomplete history stay protected from automatic pruning. A lower limit can remove older versions immediately; review the affected files before saving.").font(.caption).foregroundStyle(.secondary)
            Button("Review settings…") {
                guard unlimited || (1...100).contains(limit) else { issue = "Enter a checkpoint limit from 1 to 100, or choose Unlimited."; return }
                prepare(snapshot, intent: .settings(enabled: enabled, limit: unlimited ? nil : limit))
            }.disabled(enabled == data.configuration.enabled && (unlimited ? nil : limit) == data.configuration.limit)
            Divider()
            Button("Review unused image cleanup…") { prepare(snapshot, intent: .cleanup) }
            if let noteID, let note = data.notes.first(where: { $0.stableID == noteID }), data.groups.contains(where: { $0.id == noteID }) {
                Button("Review clearing history for “" + note.title + "”…", role: .destructive) { prepare(snapshot, intent: .clearNote(noteID)) }
            }
            Button("Review clearing all history…", role: .destructive) { prepare(snapshot, intent: .clearAll) }.disabled(data.records.isEmpty && data.inventory.blobs.isEmpty)
            Text("Clearing removes automatic and kept versions, including history for deleted or missing notes. Current notes and deliberate revisions stay in place. Saved images are deleted only when surviving data and recovery drafts no longer reference them.").font(.caption).foregroundStyle(.secondary)
            if !data.problems.isEmpty { Text("Preserved data").font(.headline); ForEach(data.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
            Button("Refresh") { Task { await reload() } }
        }.frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func counted(_ value: Int, _ noun: String) -> String { "\(value) " + noun + (value == 1 ? "" : "s") }
    private func metric(_ title: String, _ value: Int) -> some View { VStack(alignment: .leading) { Text(value.formatted()).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) } }
    private func reviewPane(_ review: MacHistoryManagementReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch review.plan.intent {
            case .settings(let enabled, let limit): Text("Automatic history: " + (enabled ? "On" : "Off") + " · " + (limit.map { counted($0, "checkpoint") } ?? "Unlimited checkpoints")).font(.headline)
            case .cleanup: Text("Remove unused history image files").font(.headline)
            case .clearAll: Text("Clear automatic and kept history across this vault").font(.headline)
            case .clearNote: Text("Clear this note’s automatic and kept history").font(.headline)
            }
            Text(counted(review.plan.removedRecords.count, "version") + " · " + counted(review.plan.keptRemoved, "kept version") + " · " + counted(review.plan.removedBlobs.count, "unused image") + " to delete").font(.callout)
            Text("Space to free: " + ByteCountFormatter.string(fromByteCount: Int64(review.plan.bytesRemoved), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
            if review.deletes { Text("Deletion cannot be undone. Review the affected versions and protected data below.").font(.callout).foregroundStyle(.red) }
            else if !review.hasChanges { Text("Nothing to remove. Saved images remain used or protected.").font(.callout).foregroundStyle(.secondary) }
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                ForEach(review.plan.removedRecords, id: \.self) { path in
                    let group = review.plan.snapshot.groups.first { path.hasPrefix(".zerus/history/notes/" + $0.id + "/") }
                    let version = group?.versions.first { $0.path == path }
                    VStack(alignment: .leading, spacing: 3) { Text((group?.title ?? "Unrecognized history") + (version?.kept == true ? " · kept" : "")).font(.headline); if let version { Text((version.label ?? "Saved version") + " · " + version.timestamp).font(.caption) }; Text(path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if !review.plan.removedBlobs.isEmpty { Text("Unused image files").font(.headline); ForEach(review.plan.removedBlobs, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) } }
                if !review.plan.warnings.isEmpty { Text("Preserved data and warnings").font(.headline); ForEach(review.plan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
            }.frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Button("Back") { self.review = nil; issue = nil }; Spacer(); Button("Cancel") { self.review = nil; issue = nil }; Button(review.deletes ? "Delete reviewed history…" : "Apply settings") { if review.deletes { confirmDelete = true } else { commit(review) } }.disabled(!review.hasChanges) }
        }
    }
    private func reload() async {
        busy = true; issue = nil; defer { busy = false }
        do { let data = try await workspace.historyManagementSnapshot(workspaceID: workspaceID); snapshot = data; enabled = data.history.configuration.enabled; unlimited = data.history.configuration.limit == nil; limit = data.history.configuration.limit ?? 10 }
        catch { issue = error.localizedDescription }
    }
    private func prepare(_ snapshot: MacHistoryManagementSnapshot, intent: NativeHistoryMaintenanceIntent) {
        busy = true; issue = nil; notice = nil
        Task { defer { busy = false }; do { review = try await workspace.prepareHistoryManagement(snapshot, intent: intent) } catch { issue = error.localizedDescription } }
    }
    private func commit(_ review: MacHistoryManagementReview) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await workspace.commitHistoryManagement(review); self.review = nil; notice = "History changes saved."; await reload() } catch { issue = error.localizedDescription } }
    }
}
