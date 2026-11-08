import SwiftUI
import ImageIO
import UIKit

extension NativeExternalTransferMode: Identifiable { var id: String { rawValue } }

struct NativeExternalTransferSheet: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var external: NativeExternalNotesModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: NativeExternalNoteSession
    let project: NativeExternalProjectFiles?
    let mode: NativeExternalTransferMode
    let workspaceID: UUID
    var pending: NativeExternalMoveRecord? = nil
    var originalRemoved: () -> Void = {}
    @State private var folder = "Inbox"
    @State private var review: NativeExternalTransferReview?
    @State private var outcome: NativeExternalTransferOutcome?
    @State private var issue: String?
    @State private var busy = false
    @State private var committing = false
    @State private var work: Task<Void, Never>?
    @State private var openedCopy: NativeOpenedNote?
    @State private var previewImages: [String: UIImage] = [:]
    @State private var limitedPreview = false
    private var title: String { pending != nil ? "Finish move" : mode == .copy ? "Copy into vault" : "Move into vault" }
    var body: some View {
        NavigationStack {
            Form {
                if let outcome {
                    Section {
                        Label(outcome.sourceRemoved ? "File moved into the vault" : "Vault copy saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(outcome.note.path).textSelection(.enabled)
                        if let message = outcome.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
                        Button("Open vault note", systemImage: "doc.text") {
                            if let note = vault.notes.first(where: { $0.path == outcome.note.path && $0.stableID == outcome.note.stableID }), let session = vault.session(for: note) {
                                openedCopy = .init(navigation: .init(vault: vault, session: session))
                            } else { issue = "Reopen the destination vault to load this copy. Its saved file is kept." }
                        }.accessibilityIdentifier("external.transfer.openCopy")
                    }
                    if outcome.recoveryPending { Section { Text("Pending moves in External notes retains the original recovery copy and the steps still to finish.") } }
                } else if let review {
                    Section("Destination") {
                        LabeledContent("Vault", value: review.destination.root.lastPathComponent)
                        Text(review.path).textSelection(.enabled).accessibilityIdentifier("external.transfer.destination")
                        LabeledContent("Attachments", value: String(review.pendingMove.map { $0.hashes.count - 1 } ?? review.assets.count))
                        LabeledContent(review.pendingMove == nil ? "Total size" : "Original file size", value: ByteCountFormatter.string(fromByteCount: Int64(review.pendingMove == nil ? review.byteCount : review.source.bytes.count), countStyle: .file))
                    }
                    Section {
                        Text(mode == .copy ? "The original Markdown file and its project attachments stay in place." : "After the vault copy is verified, the original Markdown file is removed. Existing project images and linked files stay in place.")
                        ForEach(review.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                        NavigationLink("Preview imported note") {
                            let body = NoteDocument(path: review.path, content: review.content, modified: .now).parts.body
                            VStack(spacing: 0) {
                                RevisionText(markdown: body, source: MarkdownText.requiresSource(body), images: previewImages, open: { _ in })
                                if limitedPreview { Text("Some images are available after opening the vault note.").font(.caption).foregroundStyle(.secondary).padding() }
                            }.navigationTitle("Vault copy").navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    Section {
                        Button(pending == nil ? (mode == .copy ? "Copy file" : "Move file") : "Remove reviewed original", role: mode == .move ? .destructive : nil) { commit(review) }
                            .accessibilityIdentifier("external.transfer.confirm")
                        if pending == nil { Button("Change destination") { self.review = nil }.accessibilityIdentifier("external.transfer.change") }
                    }
                } else {
                    Section {
                        Text(session.snapshot.entry.name).font(.headline)
                        Text(mode == .copy ? "Create an independent note in the open vault, including its local images and linked files." : "Move this Markdown file into the open vault after reviewing its portable copy.").foregroundStyle(.secondary)
                        if pending == nil {
                            Picker("Folder", selection: $folder) {
                                ForEach(Array(Set(["Inbox", folder] + vault.folders)).sorted(), id: \.self) { Text($0).tag($0) }
                            }.accessibilityIdentifier("external.transfer.folder")
                        }
                        Button("Review " + (mode == .copy ? "copy" : "move")) { prepare() }.accessibilityIdentifier("external.transfer.review")
                    }
                }
                if let issue { Section { Text(issue).foregroundStyle(.orange).textSelection(.enabled) } }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView(committing ? "Saving transfer…" : "Preparing review…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(outcome == nil ? "Cancel" : "Done") { work?.cancel(); dismiss() }.disabled(committing).accessibilityIdentifier("external.transfer.done") } }
            .interactiveDismissDisabled(committing)
            .task { if pending == nil { folder = NativeNoteDefaults.load(vault.activeVaultID) } }
            .task(id: review?.id) { await loadPreviewImages() }
            .fullScreenCover(item: $openedCopy) { NativeNoteNavigationView(navigation: $0.navigation) }
            .onDisappear { if !committing { work?.cancel() } }
            .onChange(of: vault.workspaceID) { _, value in if value != workspaceID { review = nil; issue = "The destination vault changed. Close this review and choose the destination again." } }
        }
    }
    private func loadPreviewImages() async {
        previewImages = [:]; limitedPreview = false
        guard let review else { return }
        let references = MarkdownText.imageReferences(NoteDocument(path: review.path, content: review.content, modified: .now).parts.body)
        var used = 0
        for asset in review.assets {
            let matching = references.filter { URL(string: $0)?.relativePath == asset.path }
            guard !matching.isEmpty else { continue }
            let bytes = asset.bytes
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 800] as CFDictionary)
            }.value
            guard !Task.isCancelled, self.review?.id == review.id else { return }
            if let image {
                let cost = image.bytesPerRow * image.height
                if used + cost <= 16 * 1024 * 1024 {
                    used += cost; let thumbnail = UIImage(cgImage: image)
                    for reference in matching { previewImages[reference] = thumbnail }
                } else { limitedPreview = true }
            }
        }
    }
    private func prepare() {
        busy = true; issue = nil
        work = Task {
            defer { busy = false }
            do {
                let value: NativeExternalTransferReview
                if let pending { value = try await vault.preparePendingExternalMove(pending, session: session, workspace: workspaceID) }
                else { value = try await vault.prepareExternalTransfer(session: session, project: project, folder: folder, mode: mode, workspace: workspaceID) }
                guard !Task.isCancelled else { return }; review = value
            } catch is CancellationError { } catch { if !Task.isCancelled { issue = error.localizedDescription } }
        }
    }
    private func commit(_ review: NativeExternalTransferReview) {
        busy = true; committing = true; issue = nil
        work = Task {
            defer { busy = false; committing = false }
            do {
                let saved = try await vault.commitExternalTransfer(review, session: session, external: external)
                outcome = saved; if saved.sourceRemoved { originalRemoved() }
            } catch { issue = error.localizedDescription }
        }
    }
}

struct NativeExternalMoveRecoveryView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var external: NativeExternalNotesModel
    @Environment(\.dismiss) private var dismiss
    let record: NativeExternalMoveRecord
    @State private var session: NativeExternalNoteSession?
    @State private var issue: String?
    @State private var busy = false
    @State private var discard = false
    @State private var exporting = false
    private var document: NativeMarkdownFileDocument { .init(data: record.sourceBytes) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(record.sourceName).font(.headline)
                    LabeledContent("Vault copy", value: record.destinationPath)
                    Text(record.phase == .removed ? "The original was removed. Finish updating its saved connection." : "A move was interrupted. The original recovery copy is kept on this device; review the current source and vault copy before removing anything.").foregroundStyle(.secondary)
                }
                Section {
                    Button("Open destination vault", systemImage: "folder") { run {
                        let destination = try record.destination()
                        await vault.open(destination.root)
                        guard vault.root?.resolvingSymlinksInPath().standardizedFileURL == destination.root.resolvingSymlinksInPath().standardizedFileURL else { throw VaultFailure(message: vault.error ?? "The destination vault could not be opened.") }
                    } }
                    if record.phase == .removed {
                        Button("Finish saved connection", systemImage: "checkmark") { run {
                            try await vault.finishPendingExternalConnection(record, external: external, workspace: vault.workspaceID); dismiss()
                        } }.accessibilityIdentifier("external.move.finish")
                    } else {
                        Button("Review original removal", systemImage: "doc.badge.arrow.up") { run {
                            guard let entry = external.entries.first(where: { $0.id == record.sourceID }) else { throw VaultFailure(message: "The original is no longer tracked. Save its recovery copy or keep the existing vault copy before discarding this record.") }
                            session = try await external.open(entry)
                        } }.accessibilityIdentifier("external.move.review")
                    }
                    if record.phase != .removed {
                        Button("Keep vault copy and close connection", systemImage: "checkmark.circle") { run {
                            try await vault.finishPendingExternalConnection(record, external: external, workspace: vault.workspaceID); dismiss()
                        } }.accessibilityIdentifier("external.move.keepCopy")
                        Text("This keeps the verified vault copy and stops tracking the original. Any original file still in Files stays untouched.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Save original recovery copy…", systemImage: "square.and.arrow.up") { exporting = true }.accessibilityIdentifier("external.move.export")
                }
                Section {
                    Button("Discard recovery record…", role: .destructive) { discard = true }.accessibilityIdentifier("external.move.discard")
                } footer: { Text("Discarding removes this saved recovery snapshot only. It keeps files in the original project and destination vault.") }
                if let issue { Text(issue).foregroundStyle(.orange).textSelection(.enabled) }
            }
            .disabled(busy).overlay { if busy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .navigationTitle("Pending move").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .sheet(item: $session, onDismiss: { Task { await external.restore(); if !external.pendingMoves.contains(where: { $0.id == record.id }) { dismiss() } } }) {
                NativeExternalTransferSheet(session: $0, project: nil, mode: .move, workspaceID: vault.workspaceID, pending: record)
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: NativeMarkdownFileDocument.contentType,
                          defaultFilename: "Recovered " + record.sourceName) { result in if case .failure(let error) = result { issue = error.localizedDescription } }
            .alert("Discard this original recovery copy?", isPresented: $discard) {
                Button("Cancel", role: .cancel) { }
                Button("Discard recovery record", role: .destructive) { run { try await external.moveStore.finish(record); await external.restore(); dismiss() } }
            } message: { Text("This removes the retained original bytes and move progress for \(record.sourceName). Original project files and vault copies are kept. Save the recovery copy first if you need it.") }
        }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; issue = nil
        Task { defer { busy = false }; do { try await action() } catch { issue = error.localizedDescription } }
    }
}
