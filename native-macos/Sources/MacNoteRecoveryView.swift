import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacNoteRecoveryView: View {
    @Bindable var workspace: MacWorkspace
    @State private var snapshot = MacNoteRecoverySnapshot()
    @State private var selected: String?
    @State private var original = false
    @State private var busy = false
    @State private var issue: String?
    @State private var notice: String?
    @State private var origin: UUID?
    @Environment(\.dismiss) private var dismiss
    private var record: MacNoteRecoveryRecord? { snapshot.records.first { $0.id == selected } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Note recovery drafts").macFont(.title2.bold()); Spacer(); if busy { ProgressView().controlSize(.small) }; Button("Refresh") { Task { await load() } }; Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(18)
            HStack { Text("Text kept on this Mac, including notes whose original file changed or disappeared.").macFont(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            MacZoomSplitView {
                List(snapshot.records, selection: $selected) { draft in
                    VStack(alignment: .leading, spacing: 5) { Text(draft.note.title).macFont(.headline); Text(draft.note.path).macFont(.caption).foregroundStyle(.secondary); Text(draft.body.split(separator: "\n").dropFirst().joined(separator: " ")).macFont(.caption).lineLimit(2); Text(draft.modified, style: .date).macFont(.caption2).foregroundStyle(.secondary) }.padding(.vertical, 5).tag(draft.id)
                }.frame(minWidth: 235, idealWidth: 260, maxWidth: 300)
                if let record {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(record.note.title).macFont(.headline)
                        Text(workspace.notes.contains { $0.path == record.note.path && $0.content == record.note.content } ? "The original still matches this draft’s saved baseline." : "The original changed or is unavailable. This preview keeps the retained text.").macFont(.caption).foregroundStyle(.secondary)
                        Picker("Preview", selection: $original) { Text("Retained text").tag(false); Text("Original baseline").tag(true) }.pickerStyle(.segmented)
                        ScrollView { Text(original ? record.note.content : record.content).macFont(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.background(.quaternary.opacity(0.3))
                        HStack { Text("Exports contain Markdown text. Linked files stay in their original locations.").macFont(.caption).foregroundStyle(.secondary); Spacer(); Button("Export text…") { export(record) } }
                    }.padding(18).frame(minWidth: 470, maxWidth: .infinity)
                } else { ContentUnavailableView("No note draft selected", systemImage: "doc.text", description: Text(snapshot.records.isEmpty ? "There are no readable note recovery drafts for this vault." : "Choose a draft to preview or export its retained text.")).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            if let message = issue ?? snapshot.warnings.first ?? notice { HStack { Text(message).macFont(.caption).foregroundStyle(issue == nil ? Color.secondary : Color.red).textSelection(.enabled); Spacer() }.padding(12) }
        }.frame(width: 940, height: 620).task { await load() }
        .onChange(of: workspace.workspaceID) { snapshot = .init(); selected = nil; origin = nil; issue = "The vault changed. Close and reopen note recovery." }
    }
    private func load() async {
        guard let root = workspace.root else { return }
        let expected = workspace.workspaceID; busy = true; defer { busy = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try MacNoteRecoveryStore.snapshot(root: root) }.value
            guard expected == workspace.workspaceID else { return }
            snapshot = loaded; origin = expected; issue = nil; notice = nil
            if !loaded.records.contains(where: { $0.id == selected }) { selected = loaded.records.first?.id }
        } catch { if expected == workspace.workspaceID { issue = error.localizedDescription } }
    }
    private func export(_ record: MacNoteRecoveryRecord) {
        guard let origin, origin == workspace.workspaceID else { issue = "The vault changed. Reopen recovery."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = record.note.title + " recovered.md"; panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { guard origin == workspace.workspaceID else { throw CancellationError() }; try workspace.exportNoteRecovery(record, to: url, workspaceID: origin); notice = "Exported the retained Markdown. The private recovery draft is kept."; issue = nil }
        catch { issue = error.localizedDescription }
    }
}
