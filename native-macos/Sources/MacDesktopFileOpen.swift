import SwiftUI
import AppKit

/// AppKit owns Finder document events; retain cold-launch events until a window exists.
@MainActor enum MacDesktopFileEvents {
    private static var waiting: [URL] = []
    static func receive(_ urls: [URL]) {
        waiting.append(contentsOf: urls.filter(\.isFileURL))
        let stores = MacWorkspace.windows.compactMap(\.value)
        let window = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let store = stores.first(where: { $0.presentationWindow === window }) ?? stores.first {
            deliver(to: store)
            Task { await store.desktopFiles.drain(in: store) }
        }
    }
    static func deliver(to workspace: MacWorkspace) {
        let urls = waiting; waiting.removeAll()
        for url in urls { workspace.desktopFiles.enqueue(url) }
    }
}

/// File events can precede vault restoration or arrive while a review is open.
/// Keep their original security-scoped URLs until the receiving window is ready.
@MainActor final class MacDesktopFileOpener: ObservableObject {
    @Published private(set) var pending: [URL] = []
    private var draining = false
    func enqueue(_ url: URL) {
        guard url.isFileURL else { return }
        let path = Data(url.resolvingSymlinksInPath().standardizedFileURL.path.utf8)
        guard !pending.contains(where: { Data($0.resolvingSymlinksInPath().standardizedFileURL.path.utf8) == path }) else { return }
        pending.append(url)
    }
    func drain(in workspace: MacWorkspace) async {
        guard !draining else { return }
        draining = true; defer { draining = false }
        let origin = workspace.workspaceID
        var opened: [MacDesktopFileTarget] = []
        while !pending.isEmpty {
            guard workspace.root != nil, !workspace.busy, !workspace.preparingToClose,
                  !workspace.editorSheetActive, !workspace.agentSettingsActive,
                  !workspace.noteMovesSaving, !workspace.schemaMaintenanceSaving,
                  !workspace.imageSaving, !workspace.externalCopySaving,
                  !workspace.external.busy, workspace.external.selected?.agentLocked != true,
                  MacAgentWorkspace.fileOperations == 0,
                  NSApp.modalWindow == nil,
                  workspace.presentationWindow?.attachedSheet == nil else { break }
            let url = pending.removeFirst()
            do {
                workspace.busy = true; defer { workspace.busy = false }
                opened.append(try await workspace.openDesktopFile(url))
            }
            catch { workspace.issue = "Could not open “\(url.lastPathComponent)”: " + error.localizedDescription }
            if workspace.workspaceID != origin { break }
        }
        // Match desktop batches: register every file, then show the first one.
        if opened.count > 1, workspace.workspaceID == origin, let first = opened.first {
            do {
                workspace.busy = true; defer { workspace.busy = false }
                try await workspace.activateDesktopFile(first)
            }
            catch { workspace.issue = error.localizedDescription }
        }
    }
}

enum MacDesktopFileTarget {
    case note(String)
    case external(UUID)
}

extension MacWorkspace {
    func openDesktopFile(_ url: URL) async throws -> MacDesktopFileTarget {
        guard url.isFileURL, let root, !preparingToClose else { throw VaultFailure(message: "Open a vault before opening desktop files.") }
        let origin = workspaceID
        guard await save() else { throw VaultFailure(message: "Save or recover the current note before opening another file.") }
        if let session = external.selected, !(await session.checkpoint()) { throw VaultFailure(message: "Keep the current external draft before opening another file.") }
        guard origin == workspaceID else { throw VaultFailure(message: "The vault changed while opening this file. Open it again in the intended vault.") }
        let lease = try NativeFileLease(scope: url)
        let prefix = Data((root.resolvingSymlinksInPath().standardizedFileURL.path + "/").utf8)
        let absolute = Data(lease.canonicalPath.utf8)
        if absolute.starts(with: prefix), let path = String(data: absolute.dropFirst(prefix.count), encoding: .utf8),
           notes.contains(where: { $0.path.utf8.elementsEqual(path.utf8) }) {
            await openNote(path)
            guard selection == path else { throw VaultFailure(message: issue ?? "The vault note could not be opened.") }
            return .note(path)
        }
        if ["md", "markdown"].contains(url.pathExtension.lowercased()) {
            await external.open(url)
            guard origin == workspaceID, external.issue == nil, let selected = external.selected else { throw VaultFailure(message: external.issue ?? "The vault changed while connecting this original.") }
            await openCollection("External Notes")
            return .external(selected.id)
        }
        let request = try await prepareFileHub()
        let note = try await saveFileHub(request, source: lease, storage: .external,
                                         title: url.deletingPathExtension().lastPathComponent, folder: request.defaultFolder)
        await openNote(note.path)
        return .note(note.path)
    }
    func activateDesktopFile(_ target: MacDesktopFileTarget) async throws {
        if let session = external.selected, !(await session.checkpoint()) { throw VaultFailure(message: "Keep the current external draft before changing files.") }
        switch target {
        case .note(let path): await openNote(path)
        case .external(let id):
            guard let entry = external.entries.first(where: { $0.id == id }) else { throw VaultFailure(message: "This external connection changed. Reopen its file.") }
            await external.open(entry)
            guard external.issue == nil else { throw VaultFailure(message: external.issue!) }
            await openCollection("External Notes")
        }
    }
}

struct MacPendingDesktopFiles: View {
    @ObservedObject var opener: MacDesktopFileOpener
    var body: some View {
        if !opener.pending.isEmpty {
            Text("Open a vault to finish opening \(opener.pending.count) desktop \(opener.pending.count == 1 ? "file" : "files").")
                .macFont(.callout).foregroundStyle(.secondary)
        }
    }
}
