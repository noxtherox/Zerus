import SwiftUI

struct NativeTaskDraftsEntry: View {
    @ObservedObject var store: NativeTaskDraftStore
    let workspaceID: UUID
    @State private var presented = false
    var body: some View {
        Section {
            Button { store.reload(); presented = true } label: {
                HStack {
                    Label("Drafts", systemImage: "doc.badge.clock").font(.body).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("\(store.records.count)").foregroundStyle(Accent.secondaryText)
                }
            }.accessibilityIdentifier("tasks.drafts")
            if let issue = store.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
        }.sheet(isPresented: $presented) { NativeTaskDraftsView(store: store, workspaceID: workspaceID) }
    }
}
private struct NativeTaskDraftsView: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NativeTaskDraftStore
    let workspaceID: UUID
    @State private var opened: NativeTaskDraft?
    @State private var deleting: NativeTaskDraft?
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            List {
                if store.records.isEmpty && store.unreadable.isEmpty { ContentUnavailableView("No task drafts", systemImage: "doc.badge.clock", description: Text("Unfinished task changes are kept on this iPhone until you save or discard them.")) }
                ForEach(store.records) { record in
                    Button { opened = record } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).foregroundStyle(.primary)
                            Text(record.task.baseline == nil ? "New task" : "Unsaved changes").font(.caption).foregroundStyle(.secondary)
                            Text(record.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("task.draft." + record.id.uuidString)
                        .swipeActions { Button("Discard", systemImage: "trash", role: .destructive) { deleting = record } }
                        .contextMenu { ShareLink(item: record.task.shareDraft) { Label("Share draft", systemImage: "square.and.arrow.up") }; Button("Discard draft", systemImage: "trash", role: .destructive) { deleting = record } }
                }
                if !store.unreadable.isEmpty {
                    Section { ForEach(store.unreadable, id: \.self) { file in ShareLink(item: file) { Label("Share preserved draft file", systemImage: "doc.badge.ellipsis") } } } header: { Text("Needs attention") } footer: { Text("These draft files could not be opened. Their original bytes are preserved; they are not overwritten or automatically removed.") }
                }
                if let issue { Text(issue).foregroundStyle(.red) }
            }.navigationTitle("Task drafts").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("tasks.drafts.done") } }
                .refreshable { store.reload() }
                .onChange(of: vault.workspaceID) { _, value in if value != workspaceID { dismiss() } }
                .fullScreenCover(item: $opened) { record in
                    TaskDetailView(task: activated(record), recovered: record)
                }
                .alert("Discard this task draft?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    if let deleting { Button("Discard draft", role: .destructive) { do { guard try store.remove(deleting) else { throw VaultFailure(message: "This draft changed. Refresh before discarding it.") }; self.deleting = nil } catch { issue = error.localizedDescription } } }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: { Text("The task in your vault stays unchanged.") }
        }
    }
    private func activated(_ record: NativeTaskDraft) -> NativeTask { var task = record.task; task.workspaceID = workspaceID; return task }

}
