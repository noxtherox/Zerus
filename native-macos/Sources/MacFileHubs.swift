import SwiftUI
import AppKit

struct MacFileHubRequest: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let basis: VaultSnapshot
    let defaultFolder: String
    let note: NoteDocument?
    let locations: NativeFileLocations?
    let locationIssue: String?
}

extension MacWorkspace {
    func prepareFileHub(_ note: NoteDocument? = nil) async throws -> MacFileHubRequest {
        let origin = workspaceID, creationFolder = defaultNoteFolder
        guard await save(), origin == workspaceID, let io else { throw VaultFailure(message: "Save the current note before changing a document.") }
        let basis = try await io.scan()
        guard origin == workspaceID, !isDirty else { throw VaultFailure(message: "The note or vault changed. Reopen the document action.") }
        let latest = note.flatMap { expected in basis.notes.first { $0.path == expected.path } }
        guard note == nil || latest != nil else { throw VaultFailure(message: "The note moved. Open it again before changing its document.") }
        let locations: NativeFileLocations?, issue: String?
        do { locations = try await io.fileLocations(); issue = locations?.warning } catch { locations = nil; issue = error.localizedDescription }
        guard origin == workspaceID else { throw CancellationError() }
        return .init(workspaceID: origin, basis: basis, defaultFolder: creationFolder, note: latest, locations: locations, locationIssue: issue)
    }
    func saveFileHub(_ request: MacFileHubRequest, source: NativeFileLease?, storage: NativeFileStorage, title: String, folder: String, detach: Bool = false) async throws -> NoteDocument {
        guard request.workspaceID == workspaceID, await save(), request.workspaceID == workspaceID, let io, let mappings = fileMappings else { throw VaultFailure(message: "The vault changed. Reopen the document action.") }
        let reference: NativeFileHub?
        if detach { reference = nil }
        else {
            guard let source else { throw VaultFailure(message: "Choose a document first.") }
            guard source.temporaryDirectory == nil || storage == .copy else { throw VaultFailure(message: "A temporary preview must be copied into the vault.") }
            // A second note for the same physical file is never created implicitly.
            for candidate in request.basis.notes where !candidate.trashed && candidate.path != request.note?.path {
                if let hub = candidate.fileHub, let existing = try? await mappings.resolve(hub), existing.canonicalPath == source.canonicalPath {
                    guard request.workspaceID == workspaceID else { throw CancellationError() }
                    if request.note == nil {
                        let fresh = try await io.scan()
                        guard request.workspaceID == workspaceID, !isDirty, let current = fresh.notes.first(where: { $0.path == candidate.path && $0.fileHub == hub }) else { throw VaultFailure(message: "The existing document note changed. Reopen its action.") }
                        apply(fresh); await reloadCurrent(); return current
                    }
                    throw VaultFailure(message: "This document already has a note: " + candidate.title)
                }
            }
            let id = UUID().uuidString.lowercased()
            if storage == .copy { reference = .init(id: id, name: source.url.lastPathComponent, kind: .local) }
            else {
                guard let locations = request.locations else { throw VaultFailure(message: request.locationIssue ?? "Reload file locations before connecting an original.") }
                reference = try await mappings.reference(for: source, id: id, locations: locations.locations)
                if reference?.kind == .local { try await mappings.locate(reference!, source: source) }
            }
        }
        guard request.workspaceID == workspaceID else { throw CancellationError() }
        let saved = try await io.saveFileHub(basis: request.basis, note: request.note, original: request.note?.fileHub, reference: reference, title: title, folder: folder, source: source, storage: storage, locations: request.locations)
        let snapshot = try await io.scan()
        guard request.workspaceID == workspaceID else { throw CancellationError() }
        apply(snapshot); await reloadCurrent(); return saved
    }
    func locateFileHub(_ note: NoteDocument, source: NativeFileLease, workspaceID: UUID) async throws {
        guard workspaceID == self.workspaceID, let mappings = fileMappings, let hub = note.fileHub,
              notes.first(where: { $0.path == note.path })?.fileHub == hub else { throw VaultFailure(message: "The document connection changed. Reopen it before locating the file.") }
        try await mappings.locate(hub, source: source)
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        fileMappingRevision += 1
    }
    func resolveFileHub(_ note: NoteDocument, workspaceID: UUID) async throws -> NativeFileLease {
        guard workspaceID == self.workspaceID, let mappings = fileMappings, let hub = note.fileHub else { throw VaultFailure(message: "This document needs a file connection.") }
        let lease = try await mappings.resolve(hub)
        guard workspaceID == self.workspaceID else { throw CancellationError() }; return lease
    }
    func previewAttachment(_ attachment: NativeFileAttachment) async {
        let origin = workspaceID
        guard let mappings = fileMappings else { return }
        do {
            let lease = try await mappings.resolve(.init(id: "attachment:" + attachment.id, name: attachment.name, kind: .vault, path: attachment.path))
            guard origin == workspaceID else { return }; previewDocument = lease
        } catch { if origin == workspaceID { issue = error.localizedDescription } }
    }
}


struct MacFileLocationsSnapshot {
    let workspaceID: UUID
    let definitions: NativeFileLocations
    let labels: [String: String]
    let mappingIssues: [String: String]
    let usages: [String: Int]
}

extension MacWorkspace {
    func fileLocationsSnapshot(workspaceID: UUID) async throws -> MacFileLocationsSnapshot {
        guard workspaceID == self.workspaceID, let io, let mappings = fileMappings else { throw VaultFailure(message: "The vault changed. Reopen File locations.") }
        let definitions = try await io.fileLocations(), basis = try await io.scan()
        var labels: [String: String] = [:], issues: [String: String] = [:], usages: [String: Int] = [:]
        for location in definitions.locations {
            guard workspaceID == self.workspaceID else { throw CancellationError() }
            do { labels[location.id] = try await mappings.locationLabel(location.id) } catch { issues[location.id] = error.localizedDescription }
            usages[location.id] = basis.notes.filter { note in
                NativeFrontmatter(note.content).entries.contains { $0.key.lowercased() == "zerus-file-location" && ($0.value == nil || $0.value?.display == location.id) }
            }.count
        }
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        return .init(workspaceID: workspaceID, definitions: definitions, labels: labels, mappingIssues: issues, usages: usages)
    }
    func changeFileLocation(_ change: NativeFileLocationChange, workspaceID: UUID) async throws {
        guard workspaceID == self.workspaceID, await save(), workspaceID == self.workspaceID, let io else { throw VaultFailure(message: "The vault changed or saving is blocked. Reopen File locations.") }
        _ = try await io.changeFileLocation(change)
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        fileMappingRevision += 1
    }
    func mapFileLocation(_ location: NativeFileLocation, folder: URL?, workspaceID: UUID) async throws {
        guard workspaceID == self.workspaceID, let io, let mappings = fileMappings else { throw VaultFailure(message: "The vault changed. Reopen File locations.") }
        let definitions = try await io.fileLocations()
        guard workspaceID == self.workspaceID, definitions.locations.contains(location) else { throw VaultFailure(message: "This location changed. Refresh before choosing its folder.") }
        try await mappings.mapLocation(location.id, url: folder)
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        fileMappingRevision += 1
    }
    func useFolderMapping(_ note: NoteDocument, workspaceID: UUID) async throws {
        guard workspaceID == self.workspaceID, let mappings = fileMappings, let reference = note.fileHub, reference.kind == .location,
              notes.first(where: { $0.path == note.path })?.fileHub == reference else { throw VaultFailure(message: "This document changed. Reopen its actions.") }
        try await mappings.set("file:" + reference.id, url: nil)
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        fileMappingRevision += 1
    }
}
