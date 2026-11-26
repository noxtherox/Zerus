import Foundation

struct MacChatNoteReference: Equatable, Sendable {
    let path: String
    let noteID: String?
    let fingerprint: String?
    var object: [String: Any] { ["path": path, "noteID": noteID as Any? ?? NSNull(), "fingerprint": fingerprint as Any? ?? NSNull()] }
    static func decode(_ rows: [[String: Any]]) throws -> [Self] {
        let result = try rows.map { row -> Self in
            guard let path = row["path"] as? String, row["noteID"] == nil || row["noteID"] is NSNull || row["noteID"] is String, row["fingerprint"] == nil || row["fingerprint"] is NSNull || row["fingerprint"] is String else { throw VaultFailure(message: "The saved note context is unsupported. Its original draft is preserved.") }
            return .init(path: path, noteID: row["noteID"] as? String, fingerprint: row["fingerprint"] as? String)
        }
        try check(result); return result
    }
    static func check(_ references: [Self]) throws {
        guard references.count <= 8, Set(references.map(\.path)).count == references.count,
              references.allSatisfy({ !$0.path.isEmpty && $0.path.utf8.count <= 4096 && !($0.path as NSString).isAbsolutePath && !$0.path.split(separator: "/").contains("..") && ($0.noteID.map { !$0.isEmpty && $0.utf8.count <= 4096 } ?? true) && ($0.fingerprint.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true) }) else { throw VaultFailure(message: "Choose up to eight valid notes from this vault for context.") }
    }
    static func capture(_ paths: Set<String>, notes: [NoteDocument]) throws -> [Self] {
        let result = try paths.sorted().map { path -> Self in
            let matches = notes.filter { $0.path == path && !$0.trashed }
            guard matches.count == 1, let note = matches.first else { throw VaultFailure(message: "A chosen note changed. Refresh the context picker.") }
            if let id = note.stableID {
                guard notes.filter({ !$0.trashed && $0.stableID == id }).count == 1 else { throw VaultFailure(message: "A chosen note has a duplicate ID. Resolve the duplicate before sharing context.") }
                return .init(path: path, noteID: id, fingerprint: nil)
            }
            return .init(path: path, noteID: nil, fingerprint: NativeHistory.hash(note.content))
        }
        try check(result); return result
    }
}

struct MacChatContextSnapshot: Sendable {
    struct Draft: Sendable { let baseline: NoteDocument; let content: String }
    let workspaceID: UUID
    let root: URL
    let notes: [NoteDocument]
    let drafts: [Draft]
    func resolve(_ references: [MacChatNoteReference]) throws -> (references: [MacChatNoteReference], sources: [MacChatSource]) {
        try MacChatNoteReference.check(references)
        var resolved: [NoteDocument] = []
        for reference in references {
            let matches: [NoteDocument]
            if let id = reference.noteID { matches = notes.filter { !$0.trashed && $0.stableID == id } }
            else if let fingerprint = reference.fingerprint {
                let samePath = notes.filter { !$0.trashed && $0.path == reference.path && $0.stableID == nil && NativeHistory.hash($0.content) == fingerprint }
                matches = samePath.isEmpty ? notes.filter { !$0.trashed && $0.stableID == nil && NativeHistory.hash($0.content) == fingerprint } : samePath
            } else { throw VaultFailure(message: "Review the saved note context once to confirm its identities. The question and attachments are kept.") }
            guard matches.count == 1, let note = matches.first else { throw VaultFailure(message: "A context note moved to Trash, disappeared, changed identity or became ambiguous. Review Context before sending; the question and attachments are kept.") }
            resolved.append(note)
        }
        guard Set(resolved.map(\.path)).count == resolved.count else { throw VaultFailure(message: "Context references now identify the same note. Review the selection before sending.") }
        let updated = try MacChatNoteReference.capture(Set(resolved.map(\.path)), notes: notes)
        let sources = resolved.map { note -> MacChatSource in
            let draft = drafts.first { draft in
                if let id = note.stableID { return draft.baseline.stableID == id }
                return draft.baseline.path == note.path && draft.baseline.content == note.content
            }
            return .init(noteID: note.stableID ?? note.path, title: note.title, folder: note.folder, content: draft?.content ?? note.content)
        }
        return (updated, sources)
    }
}

import SwiftUI

struct MacChatContextPicker: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var chat: MacChatController
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: MacChatContextSnapshot?
    @State private var choices = Set<String>()
    @State private var issue: String?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Note context").macFont(.title2.bold())
            Text("Choose the exact notes included with your next message. Note identities are checked again before Send; their text is saved as a conversation snapshot.").macFont(.callout).foregroundStyle(.secondary)
            if let issue { Text(issue).macFont(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if loading { ProgressView("Checking notes…") }
            ScrollView { LazyVStack(alignment: .leading) {
                ForEach(snapshot?.notes.filter { !$0.trashed } ?? []) { note in
                    Toggle(note.title + " · " + note.path, isOn: Binding(get: { choices.contains(note.path) }, set: { if $0 { choices.insert(note.path) } else { choices.remove(note.path) } })).toggleStyle(.checkbox)
                }
            } }.disabled(loading || chat.isBusy)
            HStack {
                Button("Clear selection") { choices = [] }; Button("Refresh notes") { Task { await load() } }.disabled(loading)
                Spacer(); Button("Cancel") { dismiss() }
                Button("Confirm selection") {
                    do {
                        guard let snapshot, snapshot.workspaceID == workspace.workspaceID else { throw VaultFailure(message: "The vault changed. Reopen Context.") }
                        try chat.setContextReferences(MacChatNoteReference.capture(choices, notes: snapshot.notes))
                        chat.issue = nil; dismiss()
                    } catch { issue = error.localizedDescription }
                }.disabled(loading || snapshot == nil || chat.isBusy)
            }
        }.padding(24).frame(width: 640, height: 520).task { await load() }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let fresh = try await workspace.chatContextSnapshot(); snapshot = fresh
            var selected = Set<String>(), unresolved = false
            for reference in chat.contextReferences ?? [] {
                if let current = try? fresh.resolve([reference]) { selected.formUnion(current.references.map(\.path)) } else { unresolved = true }
            }
            choices = selected
            issue = unresolved ? "Some saved notes need review. Choose the notes you want to share, then confirm; your question and attachments are kept." : nil
        } catch is CancellationError {} catch { issue = error.localizedDescription }
    }
}
