import SwiftUI

struct NoteReferenceSheet: View {
    let workspaceID: UUID
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    let reference: NoteReference
    let open: (NoteDocument) -> Void
    @State private var title = ""
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                let matches = vault.targets(for: reference)
                let deleted = vault.targets(for: reference, includeTrash: true).filter(\.trashed)
                if !matches.isEmpty {
                    Section("Choose a note") {
                        ForEach(matches) { note in
                            Button { dismiss(); open(note) } label: { NoteRow(note: note) }.foregroundStyle(.primary)
                        }
                    }
                } else if !deleted.isEmpty {
                    Section {
                        Text("This note is in Recently Deleted.").foregroundStyle(.secondary)
                        ForEach(deleted) { note in
                            Button("Restore \(note.title)", systemImage: "arrow.uturn.backward") {
                                busy = true
                                Task {
                                    await vault.move(note, restore: true)
                                    if vault.workspaceID == workspaceID, let restored = vault.targets(for: reference).first { dismiss(); open(restored) }
                                    busy = false
                                }
                            }.disabled(busy)
                        }
                    }
                } else {
                    Section {
                        Text("This linked note hasn’t been created yet.").foregroundStyle(.secondary)
                        TextField("Note title", text: $title).accessibilityIdentifier("linked-note.title")
                        Button("Create linked note", systemImage: "square.and.pencil") {
                            busy = true
                            let identity = reference.target.hasPrefix("zerus:") ? reference.target.dropFirst("zerus:".count).split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) : nil
                            Task {
                                if let note = await vault.createNote(title: title, stableID: identity, workspace: workspaceID) { dismiss(); open(note) }
                                busy = false
                            }
                        }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Linked note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { title = reference.label }
        }.presentationDetents([.medium, .large])
    }
}
