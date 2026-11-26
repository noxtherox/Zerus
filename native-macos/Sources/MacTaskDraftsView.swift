import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum MacTaskDraftReview {
    case discard, reload, copy
    var title: String {
        switch self { case .discard: return "Discard this task draft?"; case .reload: return "Discard draft and reload?"; case .copy: return "Save this draft as a new task?" }
    }
    var message: String {
        switch self {
        case .discard: return "The task in your vault stays unchanged. This private draft will be removed."
        case .reload: return "The latest saved task will replace this private draft."
        case .copy: return "The original task stays unchanged. A separate task will contain this draft’s values."
        }
    }
}

enum MacTaskDraftExport {
    static func message(_ value: String) -> String { value.replacingOccurrences(of: "on this iPhone", with: "on this Mac") }
    static func save(_ text: String) throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Task draft.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}

struct MacTaskDraftsEntry: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var drafts: NativeTaskDraftStore
    @State private var showing = false
    var body: some View {
        Button("Drafts (\(drafts.records.count))") { drafts.reload(); showing = true }
            .macSheet(isPresented: $showing) { MacTaskDraftsView(workspace: workspace, drafts: drafts, workspaceID: workspace.workspaceID) }
    }
}

private struct MacTaskDraftsView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var drafts: NativeTaskDraftStore
    let workspaceID: UUID
    @State private var opened: NativeTaskDraft?
    @State private var discarding: NativeTaskDraft?
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Task drafts").macFont(.title2.bold()); Spacer(); Button("Refresh") { drafts.reload() }; Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Unfinished task changes stay privately on this Mac. Save updates your vault; closing keeps the draft.").macFont(.callout).foregroundStyle(.secondary)
            Divider()
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(drafts.records) { record in
                    HStack {
                        Button { opened = record } label: {
                            VStack(alignment: .leading, spacing: 4) { Text(record.title).macFont(.headline); Text(record.task.baseline == nil ? "New task" : "Unsaved changes").macFont(.caption); Text(record.date, style: .relative).macFont(.caption) }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(MacBoxButtonStyle())
                        Button("Export…") { do { try MacTaskDraftExport.save(record.task.shareDraft) } catch { issue = error.localizedDescription } }
                        Button("Discard…") { discarding = record }
                    }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                if drafts.records.isEmpty && drafts.unreadable.isEmpty { ContentUnavailableView("No task drafts", systemImage: "doc.badge.clock", description: Text("Unfinished tasks appear here until you save or discard them.")) }
                if !drafts.unreadable.isEmpty {
                    Text("Preserved files need attention").macFont(.headline)
                    Text("These drafts could not be opened. Their original files are preserved.").macFont(.caption).foregroundStyle(.secondary)
                    ForEach(drafts.unreadable, id: \.self) { file in Button("Reveal " + file.lastPathComponent) { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
                }
            } }
            if let warning = drafts.issue { Text(MacTaskDraftExport.message(warning)).macFont(.caption).foregroundStyle(.orange) }
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width: 660, height: 520)
        .onChange(of: workspace.workspaceID) { dismiss() }
        .macSheet(item: $opened) { record in MacTaskEditor(store: workspace, task: activated(record), recovered: record) }
        .alert("Discard this task draft?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
            Button("Cancel", role: .cancel) { discarding = nil }
            Button("Discard draft", role: .destructive) {
                do { if let record = discarding, try !drafts.remove(record) { throw VaultFailure(message: "This draft changed. Refresh before discarding it.") }; discarding = nil }
                catch { issue = error.localizedDescription }
            }
        } message: { Text("The task in your vault stays unchanged.") }
    }
    private func activated(_ record: NativeTaskDraft) -> NativeTask { var task = record.task; task.workspaceID = workspaceID; return task }
}
