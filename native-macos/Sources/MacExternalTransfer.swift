import SwiftUI

struct MacExternalTransferRequest: Identifiable {
    let id = UUID()
    let mode: NativeExternalTransferMode
    var pending: NativeExternalMoveRecord? = nil
}

struct MacExternalTransferReview: Identifiable {
    var id: UUID { transfer.id }
    let transfer: NativeExternalTransferReview
    let presentationID: UUID
}

extension MacWorkspace {
    func prepareExternalTransfer(_ session: MacExternalSession, folder: String, mode: NativeExternalTransferMode) async throws -> MacExternalTransferReview {
        let origin = workspaceID
        guard let io, external.selected === session, !busy, !preparingToClose, !externalCopySaving else {
            throw VaultFailure(message: "Open a destination vault and finish the current change before importing.")
        }
        guard await save() else { throw VaultFailure(message: "Save the vault note before importing.") }
        await session.save(); await session.refresh()
        guard origin == workspaceID, external.selected === session, !session.dirty, !session.conflict, session.failure == nil else {
            throw VaultFailure(message: session.failure ?? "The file or destination changed. Save the original and review the copy again.")
        }
        let review = try await io.prepareExternalTransfer(session.snapshot, project: session.project, folder: folder, mode: mode, workspaceID: origin, inboxIsRoot: false)
        try Task.checkCancellation()
        guard origin == workspaceID, external.selected === session, !session.dirty,
              session.snapshot.bytes == review.source.bytes else { throw VaultFailure(message: "The file or vault changed while preparing the copy. Review it again.") }
        return .init(transfer: review, presentationID: session.presentationID)
    }
    func preparePendingExternalMove(_ record: NativeExternalMoveRecord, session: MacExternalSession) async throws -> MacExternalTransferReview {
        let origin = workspaceID
        guard let io, external.selected === session, !busy, !preparingToClose, !externalCopySaving, record.phase != .removed else { throw VaultFailure(message: "Open this move’s destination vault before reviewing its original.") }
        await session.save(); await session.refresh()
        guard origin == workspaceID, !session.dirty, !session.conflict, session.failure == nil,
              session.id == record.sourceID, session.snapshot.bytes == record.sourceBytes else {
            throw VaultFailure(message: "The original changed after the copy was saved. Its current file and retained recovery bytes are preserved.")
        }
        let note = try await io.pendingExternalMoveNote(record), destination = try record.destination()
        guard origin == workspaceID, external.selected === session else { throw CancellationError() }
        var transfer = NativeExternalTransferReview(id: record.id, mode: .move, workspaceID: origin, destination: destination,
            source: session.snapshot, sourceLease: try NativeFileLease(scope: session.snapshot.access.url), project: nil,
            path: record.destinationPath, content: note.content, noteID: record.noteID, assets: [], existingNotePaths: [], noteInventory: [],
            warnings: ["The verified vault copy already exists. Only the unchanged original Markdown file will be removed. Project attachments stay in place."])
        transfer.pendingMove = record
        return .init(transfer: transfer, presentationID: session.presentationID)
    }
    func commitExternalTransfer(_ review: MacExternalTransferReview, session: MacExternalSession) async throws -> NativeExternalTransferOutcome {
        let transfer = review.transfer
        guard let io, workspaceID == transfer.workspaceID, external.selected === session,
              session.presentationID == review.presentationID, !session.dirty, !session.conflict,
              session.snapshot.bytes == transfer.source.bytes,
              session.snapshot.encoded(session.document.content) == transfer.source.bytes,
              !busy, !preparingToClose, !externalCopySaving else {
            throw VaultFailure(message: "The file or destination changed after review. Prepare a fresh transfer.")
        }
        externalCopySaving = true; defer { externalCopySaving = false }
        var held: [MacExternalSession] = []
        defer { held.forEach { $0.endTransfer() } }
        let peers = transfer.mode == .move ? Self.windows.compactMap { $0.value?.external.selected }.filter { $0.snapshot.access.canonical == session.snapshot.access.canonical } : [session]
        for peer in peers {
            if held.contains(where: { $0 === peer }) { continue }
            try await peer.beginTransfer(transfer.source); held.append(peer)
        }
        // The selected editor is always held, including isolated library sessions.
        if !held.contains(where: { $0 === session }) { try await session.beginTransfer(transfer.source); held.append(session) }
        var record = transfer.pendingMove, copied: NoteDocument?, removed = false
        var iconWarning: String?
        do {
            if transfer.mode == .move, record == nil {
                let next = try NativeExternalTransferFiles.record(for: transfer)
                try await external.moveStore.save(next, replacing: nil); record = next
            }
            if let record = transfer.pendingMove { copied = try await io.pendingExternalMoveNote(record) }
            else {
                let previous = try await io.scan().folders
                copied = try await io.commitExternalCopy(transfer)
                let snapshot = try await io.scan()
                let decorated = await suggestingFolderIcons(in: snapshot, destinations: [copied!.folder], previousFolders: previous, using: io)
                iconWarning = decorated.warning
            }
            if transfer.mode == .move, var next = record {
                if next.phase == .prepared { next.phase = .copied; try await external.moveStore.save(next, replacing: record); record = next }
                try await NativeExternalTransferFiles.removeOriginal(transfer.source, record: next, destination: transfer.destination)
                removed = true; held.forEach { $0.markMoved() }
                next.phase = .removed; try await external.moveStore.save(next, replacing: record); record = next
                try await external.finishImportedMove(next.sourceID)
                try await external.moveStore.finish(next)
            }
            do { apply(try await io.scan()) } catch { issue = "The transfer was saved, but the note list could not refresh: " + error.localizedDescription }
            await external.restore()
            return .init(note: copied!, sourceRemoved: removed, recoveryPending: false, message: iconWarning)
        } catch {
            await external.restore()
            if let copied {
                do { apply(try await io.scan()) } catch { issue = error.localizedDescription }
                return .init(note: copied, sourceRemoved: removed, recoveryPending: record != nil,
                    message: (removed ? "The original moved. Finish its saved connection in Pending moves. " : "The vault copy is kept. The original has not been removed. ") + error.localizedDescription)
            }
            throw error
        }
    }
    func finishPendingExternalMove(_ record: NativeExternalMoveRecord) async throws {
        guard let io, !busy, !preparingToClose, !externalCopySaving else { throw VaultFailure(message: "Open this move’s destination vault before finishing its connection.") }
        externalCopySaving = true; defer { externalCopySaving = false }
        _ = try await io.pendingExternalMoveNote(record)
        let peers = Self.windows.compactMap { $0.value?.external.selected }.filter { $0.id == record.sourceID }
        guard !peers.contains(where: { $0.dirty || $0.transferring }) else { throw VaultFailure(message: "Keep or close the original draft in the other window first.") }
        try await external.finishImportedMove(record.sourceID)
        for peer in peers { if record.phase == .removed { peer.markMoved() } else { peer.deactivate() } }
        try await external.moveStore.finish(record); await external.restore()
    }

}

struct MacExternalTransferView: View {
    @Bindable var workspace: MacWorkspace
    @ObservedObject var session: MacExternalSession
    let mode: NativeExternalTransferMode
    var pending: NativeExternalMoveRecord? = nil
    var openCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folder = ""
    @State private var newFolder = ""
    private var destinationFolder: String { newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folder : newFolder.trimmingCharacters(in: .whitespacesAndNewlines) }
    @State private var review: MacExternalTransferReview?
    @State private var outcome: NativeExternalTransferOutcome?
    @State private var issue: String?
    @State private var busy = false
    @State private var committing = false
    @State private var work: Task<Void, Never>?
    private var title: String { pending != nil ? "Finish move" : mode == .copy ? "Copy into vault" : "Move into vault" }
    private var folders: [String] { Array(Set([""] + workspace.folders.filter { !$0.split(separator: "/").contains(where: { $0.hasPrefix(".") }) && $0.split(separator: "/").first != "assets" })).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(title).font(.title2.bold()); Spacer(); Button(outcome == nil ? "Cancel" : "Done") { work?.cancel(); dismiss() }.disabled(committing).keyboardShortcut(.cancelAction) }
            if let outcome {
                Label(outcome.sourceRemoved ? "Moved into the vault" : "Vault copy saved", systemImage: "checkmark.circle").font(.headline)
                Text(outcome.note.path).textSelection(.enabled)
                Text(outcome.sourceRemoved ? "The original Markdown file was removed. Project attachments stay in place." : "The original Markdown file and its project attachments stay in place.").foregroundStyle(.secondary)
                if let message = outcome.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if outcome.recoveryPending { Text("Pending moves in External notes keeps the original recovery bytes and the steps still to finish.").font(.caption).foregroundStyle(.secondary) }
                Button("Open vault copy") {
                    guard review?.transfer.workspaceID == workspace.workspaceID else { issue = "Reopen this copy from its destination vault."; return }
                    openCopy(outcome.note.path); dismiss()
                }.buttonStyle(.borderedProminent)
            } else if let review {
                LabeledContent("Vault", value: review.transfer.destination.root.lastPathComponent)
                LabeledContent("New note", value: review.transfer.path).textSelection(.enabled)
                LabeledContent("Attachments", value: String(review.transfer.pendingMove.map { $0.hashes.count - 1 } ?? review.transfer.assets.count))
                LabeledContent("Total size", value: ByteCountFormatter.string(fromByteCount: Int64(review.transfer.byteCount), countStyle: .file))
                Text(mode == .copy ? "The copy gets its own note identity. Local images and linked files are copied into the vault; originals stay in place." : "After verifying the vault copy, Zerus removes the reviewed original Markdown file. Its note identity is preserved. Project images and linked files stay in place.").foregroundStyle(.secondary)
                ForEach(review.transfer.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Preview Markdown") { ScrollView { Text(review.transfer.content).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180) }
                HStack {
                    Button(pending == nil ? "Change destination" : "Review again") { self.review = nil; issue = nil }
                    Spacer()
                    Button(mode == .copy ? "Copy file" : pending == nil ? "Move file" : "Remove reviewed original", role: mode == .move ? .destructive : nil) { commit(review) }.buttonStyle(.borderedProminent)
                }
            } else {
                Text(session.snapshot.entry.name).font(.headline)
                Text(mode == .copy ? "Create an independent note in the open vault, including its local images and linked files. Save changes to the original before preparing this copy." : "Move this Markdown file into the open vault. Review the destination and attachments before removing the original.").foregroundStyle(.secondary)
                LabeledContent("Vault", value: workspace.vaultTitle)
                if pending == nil {
                    Picker("Folder", selection: $folder) { ForEach(folders, id: \.self) { MacFolderLabel(path: $0.isEmpty ? "Vault root" : $0, icon: workspace.folderIcon($0)).tag($0) } }.disabled(!newFolder.isEmpty)
                    TextField("New folder (optional, e.g. Projects/Research)", text: $newFolder).textFieldStyle(.roundedBorder)
                }
                Button(mode == .copy ? "Review copy" : "Review move") { prepare() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if busy { ProgressView(committing ? "Saving transfer…" : "Preparing review…").controlSize(.small) }
        }.padding(24).frame(width: 620).disabled(busy)
        .interactiveDismissDisabled(committing)
        .onDisappear { if !committing { work?.cancel() } }
        .onChange(of: workspace.workspaceID) { _, _ in review = nil; issue = "The destination vault changed. Close this sheet and review the destination again." }
    }
    private func prepare() {
        busy = true; issue = nil
        work = Task { defer { busy = false }; do {
            if let pending { review = try await workspace.preparePendingExternalMove(pending, session: session) }
            else { review = try await workspace.prepareExternalTransfer(session, folder: destinationFolder, mode: mode) }
        } catch { issue = error.localizedDescription } }
    }
    private func commit(_ review: MacExternalTransferReview) {
        busy = true; committing = true; issue = nil
        work = Task { defer { busy = false; committing = false }; do { outcome = try await workspace.commitExternalTransfer(review, session: session) } catch { issue = error.localizedDescription } }
    }
}
