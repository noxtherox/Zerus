import SwiftUI

struct MacFolderRequest: Identifiable {
    enum Action { case rename, trash }
    let id = UUID()
    let folder: String
    let action: Action
    let workspaceID: UUID
}
struct MacFolderReview: View {
    @Bindable var store: MacWorkspace
    let request: MacFolderRequest
    @State private var destination = ""
    @State private var renamePlan: NativeFolderRenamePlan?
    @State private var trashPlan: NativeFolderTrashPlan?
    @State private var issue: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.action == .rename ? "Rename folder" : "Move folder to Trash").font(.title2.bold())
            Text(request.folder).foregroundStyle(.secondary)
            if request.action == .rename { TextField("New folder path", text: $destination).disabled(renamePlan != nil) }
            if let plan = renamePlan {
                Text("Move to “\(plan.destination)”").font(.headline)
                Text("\(plan.tree.files.count) files and \(plan.tree.directories.count) folders. References, task links and folder settings are updated together.")
                ScrollView { Text(plan.updatedNotes.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
            } else if let plan = trashPlan {
                Text("\(plan.entry.record.tree.files.count) files will move into recoverable folder trash. Notes, attachments, empty folders and shared settings are kept together.")
                Text("Restore the whole folder from Trash → Deleted folders & revisions.").font(.caption).foregroundStyle(.secondary)
            } else { Text(request.action == .rename ? "Review the files and references affected before applying this rename." : "Review the complete folder before moving it. You can restore it later.").foregroundStyle(.secondary) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer(); Button("Cancel") { dismiss() }.disabled(busy)
                if renamePlan != nil || trashPlan != nil {
                    Button(request.action == .rename ? "Rename folder" : "Move to Trash") { Task { await commit() } }.keyboardShortcut(.defaultAction).disabled(busy)
                } else { Button("Review changes") { Task { await prepare() } }.keyboardShortcut(.defaultAction).disabled(busy || request.action == .rename && destination == request.folder) }
            }
        }.padding(24).frame(width: 520).onAppear { destination = request.folder }
    }
    private func prepare() async {
        busy = true; defer { busy = false }; issue = nil
        guard request.workspaceID == store.workspaceID else { issue = "The vault changed. Reopen the folder review."; return }
        do {
            switch request.action {
            case .rename: renamePlan = try await store.prepareFolderRename(request.folder, destination: destination)
            case .trash: trashPlan = try await store.prepareFolderTrash(request.folder)
            }
        } catch { issue = error.localizedDescription }
    }
    private func commit() async {
        busy = true; defer { busy = false }
        do {
            if let renamePlan { try await store.commitFolderRename(renamePlan) }
            if let trashPlan { try await store.commitFolderTrash(trashPlan) }
            dismiss()
        } catch { issue = error.localizedDescription }
    }
}

struct MacTrashBrowser: View {
    @Bindable var store: MacWorkspace
    @State private var revisions: NativeRevisionTrashSnapshot?
    @State private var folders: NativeFolderTrashSnapshot?
    @State private var page = "Folders"
    @State private var images = false
    @State private var loadedWorkspace: UUID?
    @State private var issue: String?
    @State private var busy = false
    @State private var purge: Purge?
    @State private var reviewing = false
    @Environment(\.dismiss) private var dismiss
    enum Purge {
        case notes(NativeNoteTrashPlan), revisions(NativeRevisionTrashPlan), folder(NativeFolderTrashPlan)
        var description: String { switch self {
        case .notes(let plan): return "Permanently remove \(plan.deleted.count) notes and their retained versions. This cannot be undone."
        case .revisions(let plan): return "Permanently remove \(plan.deleted.count) deleted revisions and \(plan.removedFiles.count) unreferenced files. This cannot be undone."
        case .folder(let plan): return "Permanently remove “\(plan.entry.record.folder)” and all its files. This cannot be undone."
        } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Recently deleted").font(.title2.bold()); Spacer(); Button("Images…") { images = true }; if busy { ProgressView().controlSize(.small) }; Button("Refresh") { Task { await reload() } }; Button("Done") { dismiss() } }
            Picker("Deleted items", selection: $page) { Text("Notes").tag("Notes"); Text("Revisions").tag("Revisions"); Text("Folders").tag("Folders") }.pickerStyle(.segmented)
            List {
                if page == "Notes" {
                    ForEach(store.notes.filter(\.trashed)) { note in
                        HStack { VStack(alignment: .leading) { Text(note.title); Text(note.folder).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Restore") { Task { await store.trash(note); await reload() } }; Button("Delete permanently…", role: .destructive) { Task { await prepareNotePurge([note.path]) } } }
                    }
                } else if page == "Revisions" {
                    ForEach(revisions?.entries ?? []) { entry in
                        HStack { Text(entry.title); Spacer(); Button("Restore") { Task { await restoreRevision(entry) } }.disabled(entry.note == nil) }
                    }
                } else {
                    ForEach(folders?.entries ?? []) { entry in
                        HStack { VStack(alignment: .leading) { Text(entry.record.folder); Text(entry.record.deletedAt, format: .dateTime).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Restore") { Task { await restoreFolder(entry) } }; Button("Delete permanently…", role: .destructive) { Task { await prepareFolderPurge(entry) } } }
                    }
                }
            }.disabled(busy)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if page == "Revisions", !(revisions?.entries.isEmpty ?? true) { Button("Delete all deleted revisions permanently…", role: .destructive) { Task { await prepareRevisionPurge() } }.disabled(busy) }
        }.padding(24).frame(width: 760, height: 520).task { await reload() }
        .macSheet(isPresented: $images) { MacImagesView(workspace: store) }
        .confirmationDialog("Delete permanently?", isPresented: $reviewing) {
            Button("Delete permanently", role: .destructive) { Task { await commitPurge() } }
        } message: { Text(purge?.description ?? "") }
    }
    private func reload() async {
        guard let io = store.io else { return }; busy = true; defer { busy = false }
        do { let origin = store.workspaceID; let versions = try await io.revisionTrashSnapshot(), deleted = try await io.folderTrashSnapshot(); guard origin == store.workspaceID else { throw VaultFailure(message: "The vault changed. Refresh Recently deleted.") }; revisions = versions; folders = deleted; loadedWorkspace = origin; await store.refresh(); issue = ((revisions?.problems ?? []) + (folders?.issues ?? [])).joined(separator: "\n"); if issue == "" { issue = nil } }
        catch { issue = error.localizedDescription }
    }
    private func restoreFolder(_ entry: NativeFolderTrashEntry) async {
        guard loadedWorkspace == store.workspaceID else { issue = "The vault changed. Refresh Recently deleted."; return }
        do { let plan = try await store.prepareFolderRestore(entry); try await store.commitFolderTrash(plan); await reload() }
        catch { issue = error.localizedDescription }
    }
    private func restoreRevision(_ entry: NativeTrashedRevision) async {
        guard let io = store.io, let note = entry.note, await store.save() else { return }
        do { let snapshot = try await io.revisionSnapshot(notePath: note.path); let plan = try await io.prepareRevision(snapshot, action: .restore(entry.revision.id)); store.apply(try await io.applyRevision(plan)); await store.reloadCurrent(); await reload() }
        catch { issue = error.localizedDescription }
    }
    private func prepareNotePurge(_ paths: Set<String>) async {
        guard let io = store.io, await store.save() else { return }
        do { let snapshot = try await io.revisionTrashSnapshot(); purge = .notes(try await io.prepareNoteTrashPurge(snapshot, paths: paths)); reviewing = true }
        catch { issue = error.localizedDescription }
    }
    private func prepareRevisionPurge() async {
        guard let io = store.io, await store.save() else { return }
        do { let snapshot = try await io.revisionTrashSnapshot(); purge = .revisions(try await io.prepareRevisionTrashPurge(snapshot)); reviewing = true }
        catch { issue = error.localizedDescription }
    }
    private func prepareFolderPurge(_ entry: NativeFolderTrashEntry) async {
        guard loadedWorkspace == store.workspaceID else { issue = "The vault changed. Refresh Recently deleted."; return }
        do { purge = .folder(try await store.prepareFolderRestore(entry, purge: true)); reviewing = true }
        catch { issue = error.localizedDescription }
    }
    private func commitPurge() async {
        guard let io = store.io, let purge, await store.save() else { return }
        busy = true
        do {
            switch purge {
            case .notes(let plan): guard plan.snapshot.root == store.root else { throw VaultFailure(message: "The vault changed. Review the deletion again.") }; store.apply(try await io.applyNoteTrashPurge(plan)); await store.reconcileNavigation()
            case .revisions(let plan): guard plan.snapshot.root == store.root else { throw VaultFailure(message: "The vault changed. Review the deletion again.") }; store.apply(try await io.applyRevisionTrashPurge(plan))
            case .folder(let plan): try await store.commitFolderTrash(plan)
            }
            self.purge = nil; await reload()
        } catch { busy = false; issue = error.localizedDescription }
    }
}
