import SwiftUI

struct MacNoteMovesView: View {
    @Bindable var workspace: MacWorkspace
    let paths: Set<String>
    @State private var workspaceID: UUID
    @State private var folder = ""
    @State private var newFolder = ""
    @State private var review: MacNoteMoveReview?
    @State private var result: MacNoteMoveResult?
    @State private var historyReview: MacNoteMoveHistoryReview?
    @State private var undone = false
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    init(workspace: MacWorkspace, paths: Set<String>) { self.workspace = workspace; self.paths = paths; _workspaceID = State(initialValue: workspace.workspaceID) }
    private var destination: String { newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folder : newFolder.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(result == nil ? "Move \(paths.count) notes" : "Move results").font(.title2.bold()); Spacer(); if busy { ProgressView().controlSize(.small) } }
            if let result {
                Text("\(result.moved.count) moved · \(result.skipped.count) skipped · \(result.failed.count) not moved").font(.headline)
                ScrollView { VStack(alignment: .leading, spacing: 12) {
                    ForEach(result.moved) { move in Label(move.destination, systemImage: "checkmark.circle").font(.callout) }
                    issueRows(result.skipped, title: "Skipped")
                    issueRows(result.failed, title: "Not moved")
                    issueRows(result.warnings, title: "Metadata warnings")
                }.frame(maxWidth: .infinity, alignment: .leading) }
                if result.undoRecord != nil { Text(undone ? "Moves undone. Original paths and references restored. You can review Redo." : "Review Undo here or later in Organization history. Later edits to affected notes or references block Undo and Redo. Unrelated notes are preserved.").font(.caption).foregroundStyle(.secondary) }
                Text("Completed moves stay saved. Skipped and blocked notes remain selected so you can resolve them and try again.").font(.caption).foregroundStyle(.secondary)
                HStack { if let record = result.undoRecord { Button(undone ? "Review Redo" : "Review Undo") { busy = true; issue = nil; Task { defer { busy = false }; do { historyReview = try await workspace.prepareNoteMoveHistory(record.id, undo: !undone) } catch { issue = error.localizedDescription } } } }; Button("Open destination") { Task { if destination.isEmpty { await workspace.openCollection("All Notes") } else { await workspace.openCollection(destination, folder: true) }; dismiss() } }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else if let review {
                Text("Moves maintain note identities, paired relations, incoming links and relative attachment references. Attachment files stay in place.").font(.callout).foregroundStyle(.secondary)
                ScrollView { VStack(alignment: .leading, spacing: 12) {
                    ForEach(review.moves) { move in VStack(alignment: .leading, spacing: 4) { Text(move.title).font(.headline); Text(move.source + " → " + move.destination).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                    issueRows(review.skipped, title: "Will skip")
                    if !review.warnings.isEmpty { Text("Reference warnings").font(.headline); ForEach(review.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
                }.frame(maxWidth: .infinity, alignment: .leading) }
                Text("Each note moves through its own coordinated save. If a later move is blocked, completed moves remain saved and the result lists the notes still in place.").font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView(value: Double(workspace.noteMoveProgress.0), total: Double(max(1, workspace.noteMoveProgress.1))); Text("\(workspace.noteMoveProgress.0) of \(workspace.noteMoveProgress.1)").font(.caption).foregroundStyle(.secondary) }
                HStack { Button("Back") { self.review = nil }.disabled(busy); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Move notes") { commit(review) }.keyboardShortcut(.defaultAction).disabled(review.moves.isEmpty) }
            } else {
                Text("Choose an existing folder or enter a new path. Conflicting filenames receive a numbered name. Review every destination and any unavailable notes before moving.").font(.callout).foregroundStyle(.secondary)
                Picker("Destination", selection: $folder) { Text("Vault root (Inbox)").tag(""); ForEach(workspace.folders, id: \.self) { MacFolderLabel(path: $0, icon: workspace.folderIcon($0)).tag($0) } }.disabled(!newFolder.isEmpty)
                TextField("New folder (optional, e.g. Projects/Research)", text: $newFolder).textFieldStyle(.roundedBorder)
                Spacer()
                HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Review moves") { prepare() }.keyboardShortcut(.defaultAction).disabled(paths.isEmpty) }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(24).frame(width: 680, height: 520).disabled(busy).interactiveDismissDisabled(busy)
        .macSheet(item: $historyReview) { review in MacNoteMoveHistoryView(workspace: workspace, review: review) { undone = review.undo } }
        .onChange(of: workspace.workspaceID) { issue = "The vault changed. Close and reopen Move." }
    }
    private func issueRows(_ rows: [MacNoteMoveIssue], title: String) -> some View {
        Group { if !rows.isEmpty { Text(title).font(.headline); ForEach(rows) { row in VStack(alignment: .leading, spacing: 4) { Text(row.path).font(.callout); Text(row.reason).font(.caption).foregroundStyle(.secondary) } } } }
    }
    private func prepare() {
        busy = true; issue = nil
        Task { defer { busy = false }; do { review = try await workspace.prepareNoteMoves(paths: paths, folder: destination, workspaceID: workspaceID) } catch { issue = error.localizedDescription } }
    }
    private func commit(_ review: MacNoteMoveReview) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { result = try await workspace.commitNoteMoves(review) } catch { issue = error.localizedDescription } }
    }
}
