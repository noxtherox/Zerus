import SwiftUI
import Combine
import CryptoKit

@MainActor
final class VaultStore: ObservableObject {
    @Published var notes: [NoteDocument] = []
    @Published var files: [String] = []
    @Published private(set) var fileDates: [String: NativeFileDates] = [:]
    @Published private(set) var folderPaths: [String] = []
    @Published private(set) var folderIcons: [String: String] = [:]
    @Published private(set) var folderIssue: String?
    @Published private(set) var folderOrder: [String] = []
    @Published private(set) var resourceRevision = 0
    @Published private(set) var root: URL?
    @Published private(set) var savedVaults: [NativeSavedVault] = []
    @Published private(set) var savedVaultIssue: String?
    @Published private(set) var activeVaultID: UUID?
    @Published private(set) var chatStorageReady = false
    @Published private(set) var chatStorageIssue: String?
    private(set) var previousVaultRoots: [URL] = []
    @Published private(set) var workspaceID = UUID()
    @Published private(set) var switchingVault = false
    @Published var loading = false
    @Published private(set) var restoringVault = false
    @Published private(set) var restorationIssue: String?
    @Published private(set) var driveSelection: NativeDriveFolder?
    @Published private(set) var driveStatus: String?
    @Published private(set) var driveSyncing = false
    @Published private(set) var driveConflict: NativeDriveConflictReview?
    private var driveConnections: [URL: NativeDriveVault] = [:]
    private var activeDrive: NativeDriveVault?
    private var driveSyncTask: Task<Void, Never>?
    private var driveRetryAfterSave = false
    @Published var error: String?
    @Published private(set) var historyWarning: String?
    @Published var tasks: [NativeTask] = []
    @Published var taskLists: [NativeTaskList] = []
    @Published private(set) var generalTaskListName = "General"
    @Published private(set) var taskIssue: String?
    @Published private(set) var taskDraftStore: NativeTaskDraftStore?
    @Published private(set) var taskDraftIssue: String?
    @Published var taskCategories: [String] = []
    @Published private(set) var fileLocations: [NativeFileLocation] = []
    @Published private(set) var fileLocationIssue: String?
    private var fileMappingWorkers: [URL: NativeFileMappings] = [:]
    @Published private(set) var searchRevision = 0 { didSet { scheduleDriveSync() } }
    @Published private(set) var schemaRevision = 0
    @Published private(set) var schemaSaving = false
    @Published private(set) var recovery: VaultRecoveryReview?
    @Published private(set) var recoverySaving = false
    @Published private(set) var recoveryError: String?
    @Published private(set) var recoveryDrafts: [VaultRecoveryDraft] = []
    private var recoveryIO: VaultFiles?
    private var recoveryRoot: URL?
    private var recoveryScope: URL?
    private var recoveryRegistrationID: UUID?
    private var io: VaultFiles?
    private var scopedURL: URL?
    private var taskRevision = 0
    private var pendingTaskChanges = 0
    private var taskWriteInFlight = false
    private var taskPipeline: Task<Bool, Never>?
    private var sessions: [String: NoteSession] = [:]
    private let bookmarkKey = "zerus.native.vault.bookmark"
    private var openGeneration = UUID()
    private var foregroundRefresh: Task<Void, Never>?
    var folders: [String] { NativeFolderOrder.sorted(Set(folderPaths).union(notes.filter { $0.regularCollectionNote }.map(\.folder)), order: folderOrder) }
    var searchableNotes: [NoteDocument] {
        notes.map { note in sessions.values.first(where: { $0.dirty && $0.document.workspaceID == workspaceID && $0.document.path == note.path })?.document ?? note }
    }
    func searchSources() -> NativeSearchSources {
        .init(workspaceID: workspaceID, notes: searchableNotes, drafts: Set(sessions.values.filter { $0.dirty }.map { $0.document.path }), tasks: tasks.map { task in
            .init(id: task.id, title: task.title, category: task.category, list: taskLists.first { $0.id == task.listID }?.name ?? generalTaskListName, priority: task.priority, scheduled: task.date, due: task.dueDate, completed: task.completed, modified: (task.raw["updatedAt"] as? String).flatMap(NativeRevisionIndex.date) ?? task.createdAt)
        })
    }
    func exportNote(_ note: NoteDocument, format: NativeExportFormat, includeProperties: Bool) async throws -> NativeExportArtifact {
        guard let origin = note.workspaceID, origin == workspaceID, let io, !switchingVault,
              notes.contains(where: { $0.path == note.path && $0.stableID == note.stableID }) else { throw VaultFailure(message: "The note or vault changed. Reopen Export.") }
        let document = try await io.exportDocument(note, includeProperties: includeProperties)
        guard origin == workspaceID, !switchingVault else { throw CancellationError() }
        let job = Task.detached(priority: .userInitiated) { try NativeNoteExport.artifact(document, format: format) }
        let artifact = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
        guard !Task.isCancelled, origin == workspaceID, !switchingVault else {
            try? FileManager.default.removeItem(at: artifact.url.deletingLastPathComponent()); throw CancellationError()
        }
        return artifact
    }
    init() { reloadSavedVaults() }
    private func reloadSavedVaults() {
        do { savedVaults = try NativeVaultRegistry().entries; savedVaultIssue = nil }
        catch { savedVaults = []; savedVaultIssue = error.localizedDescription }
    }
    var vaultName: String { savedVaults.first { $0.id == activeVaultID }?.title ?? driveSelection?.name ?? root?.lastPathComponent ?? "Your library" }

    func renameSavedVault(_ id: UUID, to name: String) {
        guard !switchingVault else { return }
        do { var registry = try NativeVaultRegistry(); try registry.rename(id, to: name); reloadSavedVaults() }
        catch { self.error = error.localizedDescription }
    }
    func removeSavedVault(_ id: UUID) {
        guard !switchingVault else { return }
        do {
            var registry = try NativeVaultRegistry(); try registry.remove(id)
            if activeVaultID == id {
                // The current session stays open. A removed vault is not reopened
                // automatically on the next launch, and its files are untouched.
                activeVaultID = nil; UserDefaults.standard.removeObject(forKey: bookmarkKey)
            }
            reloadSavedVaults()
        } catch { self.error = error.localizedDescription }
    }
    private func restoredDriveConnection(for url: URL, registered selection: NativeDriveFolder? = nil) async throws -> NativeDriveVault? {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        if let connection = driveConnections[canonical] { return connection }
        let drive: NativeDriveFolder?
        if let selection { drive = selection } else { drive = try await NativeDriveVault.savedSelection(for: url) }
        guard let drive else { return nil }
        let connection = try NativeDriveVault(selection: drive, directory: canonical.deletingLastPathComponent()) { try await NativeDriveAccount.shared.files(account: drive.accountID) }
        guard connection.root.resolvingSymlinksInPath().standardizedFileURL == canonical else { throw VaultFailure(message: "The saved Google Drive working-copy location changed. Open its original Drive folder again; cached files are kept.") }
        return connection
    }
    func openSavedVault(_ id: UUID) async {
        guard !schemaSaving, !recoverySaving, !switchingVault else { return }
        guard let record = savedVaults.first(where: { $0.id == id }) else { return }
        let generation = UUID(); openGeneration = generation; loading = true; switchingVault = true
        defer { if generation == openGeneration { loading = false; switchingVault = false } }
        do {
            let url = try await Task.detached {
                var stale = false
                return try URL(resolvingBookmarkData: record.bookmark, options: [], bookmarkDataIsStale: &stale)
            }.value
            guard generation == openGeneration else { return }
            let connection = try await restoredDriveConnection(for: url, registered: record.drive)
            guard generation == openGeneration else { return }
            if let connection { await openDrive(connection, registeredID: id) }
            else { await open(url, registeredID: id) }
        } catch {
            guard generation == openGeneration else { return }
            self.error = error is VaultFailure ? "Couldn’t open \(record.title). \(error.localizedDescription)" : "Couldn’t open \(record.title). Open its folder again in Files to renew access. \(error.localizedDescription)"
        }
    }
    var canReturnFromRecovery: Bool { root != nil && root?.standardizedFileURL != recoveryRoot?.standardizedFileURL }

    func restore() async {
        guard root == nil, !restoringVault, recovery == nil else { return }
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        let generation = openGeneration
        restoringVault = true; restorationIssue = nil
        defer { restoringVault = false }
        do {
            // File-provider bookmark resolution can involve IPC. Keep it off
            // the UI actor so Files selection remains available while waiting.
            let url = try await Task.detached {
                var stale = false
                return try URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale)
            }.value
            guard root == nil, generation == openGeneration else { return }
            let registry = try? NativeVaultRegistry()
            let matches = registry?.entries.filter { $0.bookmark == bookmark } ?? []
            let registration = matches.first { $0.id == registry?.activeID } ?? (matches.count == 1 ? matches.first : nil)
            let connection = try await restoredDriveConnection(for: url, registered: registration?.drive)
            guard root == nil, generation == openGeneration else { return }
            if let connection { await openDrive(connection, registeredID: registration?.id) }
            else { await open(url, registeredID: registration?.id) }
        } catch {
            guard root == nil, generation == openGeneration else { return }
            restorationIssue = error is VaultFailure ? error.localizedDescription : "Choose your vault again in Files. \(error.localizedDescription)"
        }
    }

    func open(_ url: URL, registeredID: UUID? = nil) async {
        guard !Task.isCancelled else { return }
        guard !schemaSaving, !recoverySaving else { error = "Wait for the current file change to finish before switching vaults."; return }
        let generation = UUID()
        openGeneration = generation; loading = true; switchingVault = true
        defer { if generation == openGeneration { loading = false; switchingVault = false } }
        await flush()
        guard generation == openGeneration else { return }
        guard !sessions.values.contains(where: { $0.dirty }) else {
            error = "Save or share your unsaved drafts before switching vaults."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        let worker = driveConnections[url.resolvingSymlinksInPath().standardizedFileURL]?.io ?? VaultFiles(root: url)
        do {
            if driveConnections[url.resolvingSymlinksInPath().standardizedFileURL] == nil {
                let connection = try await restoredDriveConnection(for: url)
                guard generation == openGeneration, !Task.isCancelled else { if scoped { url.stopAccessingSecurityScopedResource() }; return }
                if let connection {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    await openDrive(connection, registeredID: registeredID); return
                }
            }
            let snapshot = try await worker.scan()
            try Task.checkCancellation()
            let activated = try await activate(url, worker: worker, snapshot: snapshot, scoped: scoped, generation: generation, registeredID: registeredID)
            if !activated {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        } catch {
            guard generation == openGeneration else { if scoped { url.stopAccessingSecurityScopedResource() }; return }
            if error is CancellationError || Task.isCancelled { if scoped { url.stopAccessingSecurityScopedResource() }; return }
            if let required = error as? VaultRecoveryRequired {
                if root?.standardizedFileURL != url.standardizedFileURL && sessions.values.contains(where: { $0.dirty }) {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    self.error = "Save or share your unsaved drafts before switching vaults."
                } else { showRecovery(required.review, worker: worker, url: url, scoped: scoped, registeredID: registeredID) }
            } else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                if root == nil { restorationIssue = error.localizedDescription }
                else { self.error = error.localizedDescription }
            }
        }
    }

    private func activate(_ url: URL, worker: VaultFiles, snapshot: VaultSnapshot, scoped: Bool, generation: UUID, preserveSessions: Bool = false, registeredID: UUID? = nil) async throws -> Bool {
        let (bookmark, canonical, resolvedID) = try await Task.detached {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            let registry = try? NativeVaultRegistry()
            let resolvedID = try registeredID ?? registry?.registrationID(for: canonical)
            return (try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), canonical, resolvedID)
        }.value
        guard generation == openGeneration else { return false }
        guard preserveSessions || !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or share your unsaved drafts before switching vaults.") }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        if !preserveSessions {
            for session in sessions.values { session.deactivate() }
            workspaceID = UUID()
        }
        chatStorageReady = false; chatStorageIssue = nil; previousVaultRoots = []
        root = url; io = worker
        driveSyncTask?.cancel(); driveSyncing = false; driveRetryAfterSave = false
        activeDrive = driveConnections[url.resolvingSymlinksInPath().standardizedFileURL]
        driveSelection = activeDrive?.selection; driveConflict = nil
        driveStatus = activeDrive == nil ? nil : "Saved on this iPhone · Drive sync pending"
        fileLocations = []; fileLocationIssue = nil
        if preserveSessions {
            let byPath = Dictionary(uniqueKeysWithValues: snapshot.notes.map { var note = $0; note.workspaceID = workspaceID; return (note.path, note) })
            for session in sessions.values { session.finishRecovery(with: byPath[session.document.path]) }
        }
        else { sessions.removeAll() }
        publish(snapshot)
        tasks = []; taskLists = []; taskCategories = []; generalTaskListName = "General"; taskIssue = nil
        taskPipeline = nil; pendingTaskChanges = 0; taskWriteInFlight = false; taskRevision += 1
        restorationIssue = nil; error = nil; historyWarning = nil
        clearRecovery()
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        do {
            var registry = try NativeVaultRegistry()
            previousVaultRoots = registry.entries.filter { $0.id == resolvedID }.compactMap { URL(string: $0.location) }
            activeVaultID = try registry.activate(url: url, canonical: canonical, bookmark: bookmark, registeredID: resolvedID, drive: driveSelection)
            reloadSavedVaults()
        } catch { activeVaultID = nil; savedVaultIssue = error.localizedDescription }
        folderOrder = activeVaultID.map { NativeFolderOrder.load(vault: $0) } ?? []
        await prepareChatStorage()
        guard generation == openGeneration else { return false }
        do { taskDraftStore = try NativeTaskDraftStore(vaultRoot: url, vaultID: activeVaultID); taskDraftIssue = nil }
        catch { taskDraftStore = nil; taskDraftIssue = error.localizedDescription }
        do { try await loadTasks() } catch { if generation == openGeneration { self.error = error.localizedDescription } }
        await refreshFileLocations()
        return true
    }

    func prepareChatStorage() async {
        guard let root else { return }
        let workspace = workspaceID, id = activeVaultID, previous = previousVaultRoots
        chatStorageReady = false; chatStorageIssue = nil
        do {
            _ = try await Task.detached { try NativeChatStorage.bind(root: root, vaultID: id, previousRoots: previous) }.value
            guard workspaceID == workspace, self.root == root else { return }
            chatStorageReady = true
        } catch { if workspaceID == workspace, self.root == root { chatStorageIssue = error.localizedDescription } }
    }

    private func showRecovery(_ review: VaultRecoveryReview, worker: VaultFiles, url: URL, scoped: Bool, registeredID: UUID?) {
        recoveryRegistrationID = registeredID
        recoveryScope?.stopAccessingSecurityScopedResource()
        recoveryScope = scoped ? url : nil
        recoveryRoot = url; recoveryIO = worker
        if root?.standardizedFileURL == url.standardizedFileURL {
            for session in sessions.values { session.pauseForRecovery() }
            recoveryDrafts = sessions.values.filter(\.dirty).map { VaultRecoveryDraft(path: $0.document.path, data: Data($0.document.content.utf8)) }.sorted { $0.path < $1.path }
        } else { recoveryDrafts = [] }
        recovery = review; recoveryError = nil; restorationIssue = nil
    }

    private func clearRecovery() {
        recoveryScope?.stopAccessingSecurityScopedResource()
        recoveryScope = nil; recoveryRoot = nil; recoveryIO = nil; recoveryRegistrationID = nil
        recovery = nil; recoveryError = nil; recoveryDrafts = []
    }

    func returnFromRecovery() {
        guard canReturnFromRecovery, !recoverySaving, !loading else { return }
        clearRecovery()
    }

    func resolveRecovery(choices: [String: VaultRecoveryChoice]) async {
        guard !recoverySaving, let review = recovery, let worker = recoveryIO, let url = recoveryRoot else { return }
        recoverySaving = true; recoveryError = nil
        defer { recoverySaving = false }
        do {
            _ = try await worker.resolveRecovery(review, choices: choices, drafts: recoveryDrafts)
            await continueAfterRecovery(worker: worker, url: url)
        } catch { recoveryError = error.localizedDescription }
    }

    func reloadRecovery() async {
        guard !recoverySaving, let worker = recoveryIO, let url = recoveryRoot else { return }
        recoverySaving = true; recoveryError = nil
        defer { recoverySaving = false }
        // Scanning can finish an already confirmed recovery or safely restore
        // a now-uncontested interrupted write. A remaining conflict gets a new
        // byte snapshot rather than silently reusing the old choices.
        await continueAfterRecovery(worker: worker, url: url)
    }

    private func continueAfterRecovery(worker: VaultFiles, url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource(), generation = openGeneration
        do {
            let snapshot = try await worker.scan()
            let preserve = root?.standardizedFileURL == url.standardizedFileURL
            let activated = try await activate(url, worker: worker, snapshot: snapshot, scoped: scoped, generation: generation, preserveSessions: preserve, registeredID: recoveryRegistrationID)
            if !activated {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            schemaRevision += 1
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if let required = error as? VaultRecoveryRequired { recovery = required.review; recoveryError = "The files were refreshed. Review these versions before continuing." }
            else { recoveryError = error.localizedDescription }
        }
    }

    func recoveryCopies() async throws -> [VaultRecoveryCopy] {
        guard let io else { return [] }
        let origin = workspaceID, copies = try await io.recoveryCopies()
        guard workspaceID == origin else { throw CancellationError() }
        return copies
    }

    func recoveryCopy(_ path: String) async throws -> VaultRecoveryArchive {
        guard let io, path.hasPrefix(".zerus/native-recovery/"), path.hasSuffix(".json") else { throw VaultFailure(message: "Choose a recovery copy from this vault.") }
        let origin = workspaceID, bytes = try await io.read(path)
        guard workspaceID == origin else { throw CancellationError() }
        let archive = try JSONDecoder().decode(VaultRecoveryArchive.self, from: bytes)
        guard archive.version == 1 else { throw VaultFailure(message: "This recovery copy was made by a newer version of Zerus.") }
        return archive
    }

    func createLocal(name: String? = nil) async {
        guard !switchingVault, !schemaSaving, !recoverySaving else { return }
        let generation = UUID(); openGeneration = generation; loading = true; switchingVault = true
        defer { if generation == openGeneration { loading = false; switchingVault = false } }
        await flush()
        guard generation == openGeneration else { return }
        guard !sessions.values.contains(where: { $0.dirty }) else { error = "Save or share your unsaved drafts before switching vaults."; return }
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url: URL
            if let name {
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 80, title != ".", title != "..",
                      !title.hasPrefix("."), title.range(of: #"[/\\:\x00-\x1F]"#, options: .regularExpression) == nil else { throw VaultFailure(message: "Use a vault name of up to 80 characters without slashes, a leading dot or line breaks.") }
                url = documents.appendingPathComponent("Vaults", isDirectory: true).appendingPathComponent(title, isDirectory: true)
                guard !FileManager.default.fileExists(atPath: url.path) else { throw VaultFailure(message: "A vault with this name already exists on this iPhone. Choose another name, or open its folder in Files.") }
            } else { url = documents.appendingPathComponent("Zerus", isDirectory: true) }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let worker = VaultFiles(root: url)
            if !FileManager.default.fileExists(atPath: url.appendingPathComponent("Welcome to Zerus.md").path) {
                let welcome = "---\nzerus-id: \(UUID().uuidString.lowercased())\nzerus-pinned: true\n---\n# Welcome to Zerus\n\nA little space for everything on your mind.\n\n## Make yourself at home\n\nCapture an idea, connect your notes, or plan your day. Your writing stays in ordinary Markdown files.\n\n- Choose a vault in Files to open your existing notes\n- Tap the compose button to start something new\n- Select text to make it **bold**, *italic*, or a link\n\n> Good ideas begin with a small note.\n"
                try await worker.write("Welcome to Zerus.md", data: Data(welcome.utf8), expected: nil)
            }
            guard generation == openGeneration else { return }
            await open(url)
        } catch { if generation == openGeneration { self.error = error.localizedDescription } }
    }

    func startForegroundRefresh() {
        guard foregroundRefresh == nil else { return }
        foregroundRefresh = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
                guard !Task.isCancelled, let self else { break }
                await self.refresh()
            }
        }
    }
    func stopForegroundRefresh() { foregroundRefresh?.cancel(); foregroundRefresh = nil }

    func refresh() async {
        guard let io, !loading, !schemaSaving, !switchingVault, recovery == nil, !recoverySaving else { return }
        if activeDrive != nil { await syncDrive() }
        let generation = openGeneration, origin = workspaceID, basis = notes
        func sameBasis() -> Bool {
            Dictionary(uniqueKeysWithValues: notes.map { ($0.path, $0.content) }) == Dictionary(uniqueKeysWithValues: basis.map { ($0.path, $0.content) })
        }
        loading = true
        defer { if generation == openGeneration { loading = false } }
        do {
            let snapshot = try await io.scan()
            guard generation == openGeneration, origin == workspaceID, sameBasis(), !schemaSaving, !switchingVault else { return }
            let result = try await io.reconcileExternalHistory(previous: basis, scanned: snapshot)
            guard generation == openGeneration, origin == workspaceID, sameBasis(), !schemaSaving, !switchingVault else { return }
            publish(result.snapshot)
            historyWarning = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
            // Keep an open editor attached across an unambiguous external move.
            // The old key remains an alias for presentations holding its path.
            for session in Array(sessions.values) {
                let matching = notes.filter { $0.stableID != nil && $0.stableID == session.document.stableID }
                if let note = notes.first(where: { $0.path == session.document.path }) {
                    session.reconcile(note)
                } else if matching.count == 1, !session.dirty, !session.saving {
                    session.reconcile(matching[0]); sessions[matching[0].path] = session
                }
            }
            let changed = Dictionary(uniqueKeysWithValues: basis.map { ($0.path, $0.content) }) != Dictionary(uniqueKeysWithValues: notes.map { ($0.path, $0.content) })
            if changed || result.addedVersions > 0 { schemaRevision += 1 }
            if !taskWriteInFlight { try await loadTasks() }
            guard origin == workspaceID else { return }
            await refreshFileLocations()
        } catch {
            if generation == openGeneration, origin == workspaceID {
                if let required = error as? VaultRecoveryRequired, let root { showRecovery(required.review, worker: io, url: root, scoped: false, registeredID: activeVaultID) }
                else { self.error = error.localizedDescription }
            }
        }
    }

    private func publish(_ snapshot: VaultSnapshot) {
        // Writing a note or task alone must not restart its image downloads.
        // A changed resource snapshot invalidates previews in open editors.
        if fileDates != snapshot.fileDates { resourceRevision += 1 }
        notes = snapshot.notes.map { var note = $0; note.workspaceID = workspaceID; return note }
        files = snapshot.files; fileDates = snapshot.fileDates
        folderPaths = snapshot.folders; folderIcons = snapshot.folderIcons; folderIssue = snapshot.folderIssue
        searchRevision += 1
    }
    private func current(_ note: NoteDocument) -> Bool { root != nil && note.workspaceID == workspaceID }
    func session(for requested: NoteDocument) -> NoteSession? {
        guard current(requested), let root, let io else { return nil }
        let matches = notes.filter { requested.stableID == nil ? $0.path == requested.path : $0.stableID == requested.stableID }
        guard matches.count == 1 else { return nil }
        let note = matches[0]
        guard note.trashed == requested.trashed else { return nil }
        if let id = note.stableID, let existing = sessions.values.first(where: { $0.document.stableID == id }) { return existing }
        if let existing = sessions[note.path], existing.document.path == note.path { return existing }
        let origin = workspaceID
        let session = NoteSession(note: note, root: root, io: io, vaultID: activeVaultID) { [weak self] updated in
            guard let self, self.workspaceID == origin else { return }
            if let index = self.notes.firstIndex(where: { $0.path == updated.path }) { self.notes[index] = updated; self.searchRevision += 1 }
        }
        sessions[note.path] = session
        return session
    }

    private func discardSession(_ session: NoteSession) {
        // Foreground moves retain old path aliases. Deactivating one editor
        // must retire every alias, or reopening can return its removed path.
        session.deactivate()
        sessions = sessions.filter { $0.value !== session }
    }

    func flush() async {
        _ = await taskPipeline?.value
        for session in sessions.values { await session.save() }
    }

    @discardableResult func openDrive(_ selection: NativeDriveFolder, registeredID: UUID? = nil) async -> Bool {
        do {
            let directory = NativeDriveVault.directory(for: selection)
            let connection = try driveConnections[directory.appendingPathComponent("Vault").resolvingSymlinksInPath().standardizedFileURL] ?? NativeDriveVault(selection: selection, directory: directory) { try await NativeDriveAccount.shared.files(account: selection.accountID) }
            return await openDrive(connection, registeredID: registeredID)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func openDrive(_ connection: NativeDriveVault, registeredID: UUID? = nil) async -> Bool {
        guard !Task.isCancelled, !schemaSaving, !recoverySaving else { return false }
        let generation = UUID(); openGeneration = generation; loading = true; switchingVault = true
        defer { if generation == openGeneration { loading = false; switchingVault = false } }
        do {
            await flush()
            try Task.checkCancellation()
            guard !sessions.values.contains(where: \.dirty), generation == openGeneration else { throw VaultFailure(message: "Save or share your drafts before opening another vault.") }
            try await connection.prepare()
            try Task.checkCancellation()
            guard generation == openGeneration else { return false }
            driveConnections[connection.root.resolvingSymlinksInPath().standardizedFileURL] = connection
            await open(connection.root, registeredID: registeredID)
            scheduleDriveSync()
            return activeDrive === connection
        } catch { if !Task.isCancelled, !(error is CancellationError), generation == openGeneration { self.error = error.localizedDescription; restorationIssue = error.localizedDescription }; return false }
    }
    private func scheduleDriveSync() {
        guard activeDrive != nil else { return }
        driveStatus = "Saved on this iPhone · Drive sync pending"
        if driveSyncing { driveRetryAfterSave = true; return }
        driveSyncTask?.cancel()
        driveSyncTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() } catch { return }
            await self?.syncDrive()
        }
    }
    func syncDrive() async {
        guard let connection = activeDrive, !driveSyncing, !switchingVault, recovery == nil else { return }
        let origin = workspaceID
        driveSyncing = true; driveStatus = "Syncing Google Drive…"; driveRetryAfterSave = false
        defer {
            if origin == workspaceID {
                driveSyncing = false
                if driveRetryAfterSave, driveConflict == nil { scheduleDriveSync() }
            }
        }
        do {
            let pending = try await connection.sync()
            guard origin == workspaceID else { return }
            driveConflict = nil; driveStatus = pending ? "Saved on this iPhone · More changes waiting for Drive" : "Synced with Google Drive"
        } catch {
            guard origin == workspaceID else { return }
            if let conflict = error as? NativeDriveConflictRequired { driveConflict = conflict.review }
            driveStatus = "Saved on this iPhone · " + error.localizedDescription
        }
    }
    func resolveDrive(_ review: NativeDriveConflictReview, keepLocal: Set<String>) async throws {
        guard let activeDrive, driveConflict?.id == review.id, !driveSyncing else { throw CancellationError() }
        let origin = workspaceID
        try await activeDrive.resolve(review, keepLocal: keepLocal)
        guard origin == workspaceID else { throw CancellationError() }
        driveConflict = nil; await syncDrive(); await refresh()
    }

    func targets(for reference: NoteReference, includeTrash: Bool = false) -> [NoteDocument] {
        reference.targets(in: notes, includeTrash: includeTrash, includeHeadingFragments: true)
    }

    func createNote(title: String = "Untitled", folder: String = "Inbox", body: String = "", stableID: String? = nil, workspace expected: UUID? = nil) async -> NoteDocument? {
        guard let io, !switchingVault, recovery == nil, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        if let stableID {
            guard stableID.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else { error = "This note link has an invalid identifier."; return nil }
            guard !notes.contains(where: { $0.stableID == stableID }) else { error = "That note already exists. Check Recently Deleted if it is not visible."; return nil }
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = (clean.isEmpty ? "Untitled" : clean).replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
        let parent = folder == "Inbox" ? "" : folder + "/"
        var path = parent + filename + ".md"
        var index = 2
        while notes.contains(where: { $0.path == path }) { path = parent + filename + " \(index).md"; index += 1 }
        let content = "---\nzerus-id: \(stableID ?? UUID().uuidString.lowercased())\n---\n# \(clean.isEmpty ? "Untitled" : clean)\n\n" + body
        do {
            try await io.write(path, data: Data(content.utf8), expected: nil)
            guard workspaceID == origin else { return nil }
            let now = Date()
            var note = NoteDocument(path: path, content: content, modified: now, created: now); note.workspaceID = origin
            notes.insert(note, at: 0)
            return note
        } catch { if workspaceID == origin { self.error = error.localizedDescription }; return nil }
    }

    func duplicate(_ note: NoteDocument) async {
        guard let io, !switchingVault, recovery == nil, !recoverySaving, current(note), let session = session(for: note) else { return }
        let origin = workspaceID
        await session.save()
        guard workspaceID == origin else { return }
        guard !session.dirty else { error = session.failure; return }
        let title = session.document.title + " copy"
        var body = session.document.parts.body
        if let heading = body.range(of: #"(?m)^# [^\r\n]*"#, options: .regularExpression) { body.replaceSubrange(heading, with: "# " + title) }
        else { body = "# " + title + "\n\n" + body }
        var copy = session.document
        copy.content = copy.replacingBody(body)
        let filename = title.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
        let parent = (note.path as NSString).deletingLastPathComponent
        let prefix = parent.isEmpty ? "" : parent + "/"
        var path = prefix + filename + ".md", index = 2
        while notes.contains(where: { $0.path == path }) { path = prefix + filename + " \(index).md"; index += 1 }
        do {
            let copiedID = UUID().uuidString.lowercased()
            copy.content = try copy.setting("zerus-id", to: copiedID)
            if copy.savedLink != nil { copy.content = try copy.setting("zerus-link-id", to: copiedID) }
            if copy.fileHub?.managed == true { copy.content = try NativeFrontmatter(copy.content).setting("zerus-file-managed", value: nil) }
            copy.content = try copy.setting("zerus-archived", to: "false")
            try await io.write(path, data: Data(copy.content.utf8), expected: nil)
            guard workspaceID == origin else { return }
            copy.path = path; copy.modified = Date(); notes.insert(copy, at: 0)
        } catch { if workspaceID == origin { self.error = error.localizedDescription } }
    }

    func createSavedLink(address: String, title: String, workspace expected: UUID) async throws -> NoteDocument {
        guard let io, expected == workspaceID, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reopen Saved links.") }
        schemaSaving = true
        defer { schemaSaving = false }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before adding a link.") }
        let created = try await io.createSavedLink(address: address, title: title)
        let snapshot = try await io.scan()
        guard expected == workspaceID else { throw CancellationError() }
        publish(snapshot); schemaRevision += 1
        guard let note = notes.first(where: { $0.path == created.path }) else { throw VaultFailure(message: "The link changed after saving. Refresh Saved links.") }
        return note
    }

    func updateSavedLink(session: NoteSession, address: String, originalAddress: String, workspace expected: UUID) async throws {
        guard let io, expected == workspaceID, session.document.workspaceID == expected, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or another file change is saving. Reopen this link.") }
        schemaSaving = true
        defer { schemaSaving = false }
        await session.save()
        guard expected == workspaceID, !session.dirty, session.document.savedLink?.address == originalAddress else { throw VaultFailure(message: "This link or its draft changed. Reopen the address editor before saving.") }
        session.holdForMutation(true)
        defer { session.holdForMutation(false) }
        let saved = try await io.updateSavedLink(session.document, address: address)
        guard expected == workspaceID else { throw CancellationError() }
        publish(saved); for note in notes { sessions[note.path]?.reconcile(note) }; schemaRevision += 1
    }

    func setFlag(_ key: String, note: NoteDocument, value: Bool) async {
        guard !switchingVault, recovery == nil, !recoverySaving, current(note), let editor = session(for: note) else { return }
        let origin = workspaceID
        do {
            editor.updateContent(try editor.document.setting(key, to: value ? "true" : "false"))
            await editor.save()
            guard workspaceID == origin else { return }
            if let error = editor.failure { self.error = error }
        } catch { if workspaceID == origin { self.error = error.localizedDescription } }
    }

    @discardableResult
    func move(_ note: NoteDocument, folder: String? = nil, trash: Bool = false, restore: Bool = false) async -> Bool {
        guard let io, !switchingVault, recovery == nil, !recoverySaving, current(note), let session = session(for: note) else { return false }
        let origin = workspaceID
        await session.save()
        guard workspaceID == origin else { return false }
        guard !session.dirty else { error = session.failure ?? "Save the draft before moving it."; return false }
        let path: String
        if restore { path = String(note.path.dropFirst(".trash/".count)) }
        else if trash { path = ".trash/" + note.path }
        else { path = (folder == "Inbox" ? "" : (folder ?? "") + "/") + (note.path as NSString).lastPathComponent }
        guard path != note.path else { return false }
        do {
            if !trash && !restore {
                let snapshot = try await relationDefinitionSnapshot()
                let plan = try await prepareMove(snapshot, source: note.path, destination: path)
                try await saveRelationMaintenance(plan)
                return true
            }
            try await io.move(note.path, to: path, expected: Data(session.document.content.utf8))
            guard workspaceID == origin else { return false }
            discardSession(session)
            await refresh()
            return workspaceID == origin
        } catch { if workspaceID == origin { self.error = error.localizedDescription }; return false }
    }

    func importFile(_ source: URL, workspace expected: UUID? = nil) async -> String? {
        guard let io, !switchingVault, recovery == nil, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try await Task.detached {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose a file smaller than 50 MB.") }
                return try Data(contentsOf: source, options: .mappedIfSafe)
            }.value
            guard bytes.count <= 50 * 1024 * 1024 else { throw VaultFailure(message: "Choose a file smaller than 50 MB.") }
            guard workspaceID == origin else { return nil }
            return try await storeAsset(bytes, name: source.lastPathComponent, io: io, origin: origin)
        } catch { if workspaceID == origin { self.error = error.localizedDescription }; return nil }
    }
    func importImage(_ bytes: Data, workspace expected: UUID? = nil) async -> String? {
        guard let io, !switchingVault, recovery == nil, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        do { return try await storeAsset(bytes, name: "Image.png", io: io, origin: origin) }
        catch { if workspaceID == origin { self.error = error.localizedDescription }; return nil }
    }
    func clipboardProvider(notePath: String) -> (String) async throws -> NativeClipboardFragment {
        let original = io
        return { markdown in
            guard let original else { throw VaultFailure(message: "Choose a vault before copying its attachments.") }
            return try await original.clipboardFragment(markdown, notePath: notePath)
        }
    }
    func importClipboard(_ fragment: NativeClipboardFragment, workspace expected: UUID? = nil) async throws -> String {
        guard let io, !switchingVault, recovery == nil, expected == nil || expected == workspaceID else { throw CancellationError() }
        let origin = workspaceID
        let markdown = try await io.importClipboard(fragment)
        guard workspaceID == origin else { throw CancellationError() }
        if !fragment.resources.isEmpty { await refresh() }
        return markdown
    }
    private func storeAsset(_ bytes: Data, name: String, io: VaultFiles, origin: UUID) async throws -> String {
        let safe = name.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
        let path = "assets/" + UUID().uuidString.lowercased() + "-" + safe
        try await io.write(path, data: bytes, expected: nil)
        guard workspaceID == origin else { throw CancellationError() }
        files.append(path); searchRevision += 1
        return path
    }
    func assetURL(_ reference: String, notePath: String, workspace expected: UUID? = nil) async -> URL? {
        guard let io, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        let location = try? await io.resolveResource(reference, notePath: notePath)
        return workspaceID == origin ? location : nil
    }
    func linkedNote(_ reference: String, notePath: String, workspace expected: UUID? = nil) async -> NoteDocument? {
        guard let io, let originalRoot = root, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        guard let location = try? await io.resolveResource(reference, notePath: notePath), workspaceID == origin else { return nil }
        let prefix = originalRoot.standardizedFileURL.path + "/"
        guard location.path.hasPrefix(prefix) else { return nil }
        let path = String(location.path.dropFirst(prefix.count))
        return notes.first { $0.path == path && !$0.trashed }
    }
    func imageData(_ reference: String, notePath: String, workspace expected: UUID? = nil) async throws -> Data? {
        guard let io, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        do {
            let data = try await io.imagePreviewData(reference, notePath: notePath)
            return workspaceID == origin ? data : nil
        } catch NativeCoordinatedReadFailure.timedOut { throw NativeCoordinatedReadFailure.timedOut }
        catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
    func fileURL(_ path: String, workspace expected: UUID? = nil) async -> URL? {
        guard let io, expected == nil || expected == workspaceID else { return nil }
        let origin = workspaceID
        do { let location = try await io.url(for: path); return workspaceID == origin ? location : nil }
        catch { if workspaceID == origin { self.error = error.localizedDescription }; return nil }
    }

    func propertyDefinitions(notePath: String, workspace expected: UUID? = nil) async throws -> [NativePropertyDefinition] {
        guard let io, expected == nil || expected == workspaceID else { throw CancellationError() }
        let origin = workspaceID, definitions = try await io.propertyDefinitions(notePath: notePath)
        guard workspaceID == origin else { throw CancellationError() }
        return definitions
    }
    private func bound(_ schema: NativeSchemaSnapshot) -> NativeSchemaSnapshot {
        var schema = schema; schema.workspaceID = workspaceID; return schema
    }
    func revisionTrashSnapshot(workspace expected: UUID) async throws -> NativeRevisionTrashSnapshot {
        guard expected == workspaceID, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen Recently Deleted.") }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before reviewing discarded revisions.") }
        var snapshot = try await io.revisionTrashSnapshot()
        guard expected == workspaceID else { throw CancellationError() }
        snapshot.workspaceID = expected
        return snapshot
    }
    func prepareRevisionTrashPurge(_ snapshot: NativeRevisionTrashSnapshot) async throws -> NativeRevisionTrashPlan {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reload Recently Deleted.") }
        let plan = try await io.prepareRevisionTrashPurge(snapshot)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func saveRevisionTrashPurge(_ plan: NativeRevisionTrashPlan) async throws {
        guard plan.snapshot.workspaceID == workspaceID, plan.snapshot.root == root, let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or another file change is saving. Reload this cleanup.") }
        schemaSaving = true
        defer { schemaSaving = false }
        await flush()
        guard plan.snapshot.workspaceID == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before permanent revision cleanup.") }
        let editors = Array(sessions.values)
        editors.forEach { $0.holdForMutation(true) }
        defer { editors.forEach { $0.holdForMutation(false) } }
        let saved = try await io.applyRevisionTrashPurge(plan)
        guard plan.snapshot.workspaceID == workspaceID else { throw CancellationError() }
        publish(saved); schemaRevision += 1
        for note in notes { sessions[note.path]?.reconcile(note) }
    }

    func prepareNoteTrashPurge(_ snapshot: NativeRevisionTrashSnapshot, paths: Set<String>) async throws -> NativeNoteTrashPlan {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reload Recently Deleted.") }
        let plan = try await io.prepareNoteTrashPurge(snapshot, paths: paths)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func saveNoteTrashPurge(_ plan: NativeNoteTrashPlan) async throws {
        guard plan.snapshot.workspaceID == workspaceID, plan.snapshot.root == root, let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or another change is saving. Reload the note cleanup.") }
        schemaSaving = true; defer { schemaSaving = false }
        await flush()
        guard plan.snapshot.workspaceID == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before permanent note cleanup.") }
        let editors = Array(sessions.values); editors.forEach { $0.holdForMutation(true) }
        defer { editors.forEach { $0.holdForMutation(false) } }
        let saved = try await io.applyNoteTrashPurge(plan)
        guard plan.snapshot.workspaceID == workspaceID else { throw CancellationError() }
        for note in plan.deleted { if let session = sessions[note.path] { discardSession(session) } }
        publish(saved); schemaRevision += 1
        for note in notes { sessions[note.path]?.reconcile(note) }
    }

    func historySnapshot(note: NoteDocument) async throws -> NativeHistorySnapshot {
        guard current(note), let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Wait for the current change, then reopen history.") }
        let origin = workspaceID
        await sessions[note.path]?.save()
        guard origin == workspaceID, sessions[note.path]?.dirty != true else { throw VaultFailure(message: "Save or keep the draft before opening history.") }
        var snapshot = try await io.historySnapshot(notePath: note.path)
        guard origin == workspaceID else { throw CancellationError() }
        snapshot.workspaceID = origin; return snapshot
    }
    func historyPreview(_ version: NativeHistoryVersion, snapshot: NativeHistorySnapshot) async throws -> String {
        guard snapshot.workspaceID == workspaceID, let io else { throw CancellationError() }
        let content = try await io.historyPreview(version)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return content
    }
    func prepareHistory(_ snapshot: NativeHistorySnapshot, action: NativeHistoryAction) async throws -> NativeHistoryPlan {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen history.") }
        await sessions[snapshot.note.path]?.save()
        guard snapshot.workspaceID == workspaceID, sessions[snapshot.note.path]?.dirty != true else { throw VaultFailure(message: "Save or keep the draft before changing history.") }
        let plan = try await io.prepareHistory(snapshot, action: action)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func saveHistory(_ plan: NativeHistoryPlan) async throws {
        guard plan.snapshot.workspaceID == workspaceID, plan.snapshot.root == root, let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reopen history.") }
        schemaSaving = true; defer { schemaSaving = false }
        let session = sessions[plan.snapshot.note.path]
        await session?.save()
        guard plan.snapshot.workspaceID == workspaceID, session?.dirty != true else { throw VaultFailure(message: "Save or keep the draft before changing history.") }
        session?.holdForMutation(true); defer { session?.holdForMutation(false) }
        let saved = try await io.applyHistory(plan)
        guard plan.snapshot.workspaceID == workspaceID else { throw CancellationError() }
        publish(saved); for note in notes { sessions[note.path]?.reconcile(note) }; schemaRevision += 1
    }
    func historyMaintenanceSnapshot(workspace expected: UUID) async throws -> NativeHistoryMaintenanceSnapshot {
        guard expected == workspaceID, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen history settings.") }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before reviewing history.") }
        var snapshot = try await io.historyMaintenanceSnapshot()
        guard expected == workspaceID else { throw CancellationError() }
        snapshot.workspaceID = expected; return snapshot
    }
    func prepareHistoryMaintenance(_ snapshot: NativeHistoryMaintenanceSnapshot, intent: NativeHistoryMaintenanceIntent) async throws -> NativeHistoryMaintenancePlan {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen history settings.") }
        let plan = try await io.prepareHistoryMaintenance(snapshot, intent: intent)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func saveHistoryMaintenance(_ plan: NativeHistoryMaintenancePlan) async throws {
        guard plan.snapshot.workspaceID == workspaceID, plan.snapshot.root == root, let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or another file change is saving. Reload this review.") }
        schemaSaving = true; defer { schemaSaving = false }
        await flush()
        guard plan.snapshot.workspaceID == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before changing history.") }
        let editors = Array(sessions.values); editors.forEach { $0.holdForMutation(true) }
        defer { editors.forEach { $0.holdForMutation(false) } }
        let saved = try await io.applyHistoryMaintenance(plan)
        guard plan.snapshot.workspaceID == workspaceID else { throw CancellationError() }
        publish(saved); for note in notes { sessions[note.path]?.reconcile(note) }; schemaRevision += 1
    }

    func revisionSnapshot(note: NoteDocument) async throws -> NativeRevisionSnapshot {
        guard current(note), let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Wait for the current file change, then reopen revisions.") }
        let origin = workspaceID
        await sessions[note.path]?.save()
        guard workspaceID == origin, sessions[note.path]?.dirty != true else { throw VaultFailure(message: "Save or keep this note’s draft before opening revisions.") }
        var snapshot = try await io.revisionSnapshot(notePath: note.path)
        guard workspaceID == origin else { throw CancellationError() }
        snapshot.workspaceID = origin
        return snapshot
    }
    func prepareRevision(_ snapshot: NativeRevisionSnapshot, action: NativeRevisionAction) async throws -> NativeRevisionPlan {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen revisions.") }
        await sessions[snapshot.note.path]?.save()
        guard snapshot.workspaceID == workspaceID, sessions[snapshot.note.path]?.dirty != true else { throw VaultFailure(message: "Save or keep this note’s draft before changing revisions.") }
        let plan = try await io.prepareRevision(snapshot, action: action)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func saveRevision(_ plan: NativeRevisionPlan) async throws {
        let snapshot = plan.snapshot
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reopen revisions.") }
        schemaSaving = true
        defer { schemaSaving = false }
        let session = sessions[snapshot.note.path]
        await session?.save()
        guard snapshot.workspaceID == workspaceID, session?.dirty != true else { throw VaultFailure(message: "Save or keep this note’s draft before changing revisions.") }
        session?.holdForMutation(true)
        defer { session?.holdForMutation(false) }
        let saved = try await io.applyRevision(plan)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        publish(saved)
        for note in notes { sessions[note.path]?.reconcile(note) }
        schemaRevision += 1
    }

    func bulkSnapshot(workspace expected: UUID) async throws -> NativeBulkSnapshot {
        guard expected == workspaceID, let io, !schemaSaving, !switchingVault, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is still saving. Reopen bulk actions.") }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your unsaved drafts before reviewing bulk actions.") }
        let value = try await io.bulkSnapshot()
        guard expected == workspaceID else { throw CancellationError() }
        return .init(source: .init(schema: bound(value.source.schema), notes: value.source.notes), historyBytes: value.historyBytes, records: value.records)
    }
    func saveBulk(_ plan: NativeBulkPlan) async throws {
        let expected = plan.snapshot.source.schema.workspaceID
        guard expected == workspaceID, root == plan.snapshot.source.schema.root, let io, !schemaSaving, !loading, !switchingVault, recovery == nil, !recoverySaving else { throw VaultFailure(message: "The vault changed or another file change is saving. Reopen this review.") }
        schemaSaving = true
        defer { schemaSaving = false }
        let editors = Array(sessions.values); editors.forEach { $0.holdForMutation(true) }
        defer { editors.forEach { $0.holdForMutation(false) } }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "A draft is unsaved. Save or keep it before applying this review.") }
        let saved = try await io.applyBulk(plan)
        guard expected == workspaceID else { throw CancellationError() }
        publish(saved); for note in notes { sessions[note.path]?.reconcile(note) }; schemaRevision += 1
    }

    func schemaSnapshot() async throws -> NativeSchemaSnapshot {
        guard let io else { throw VaultFailure(message: "Choose a vault first.") }
        let origin = workspaceID, snapshot = try await io.schemaSnapshot()
        guard workspaceID == origin else { throw CancellationError() }
        return bound(snapshot)
    }
    func relationSnapshot(notePath: String, name: String) async throws -> NativeRelationSnapshot {
        guard let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Wait for the current file change to finish, then reopen this relation.") }
        let origin = workspaceID
        await flush()
        guard workspaceID == origin, !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your unsaved drafts before changing relations.") }
        let snapshot = try await io.relationSnapshot(notePath: notePath, name: name)
        guard workspaceID == origin else { throw CancellationError() }
        return NativeRelationSnapshot(schema: bound(snapshot.schema), notes: snapshot.notes, sourcePath: snapshot.sourcePath, name: snapshot.name)
    }

    func saveRelation(_ plan: NativeRelationPlan) async throws {
        guard !schemaSaving, !loading, !switchingVault, !recoverySaving, recovery == nil, let io, root == plan.snapshot.schema.root, plan.snapshot.schema.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed or another file change is still saving. Reload this relation.") }
        schemaSaving = true
        defer { schemaSaving = false }
        await flush()
        guard !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your unsaved drafts before changing relations.") }
        let current = try await io.applyRelation(plan)
        publish(current)
        for note in notes { sessions[note.path]?.reconcile(note) }
        schemaRevision += 1
    }
    func relationDefinitionSnapshot() async throws -> NativeRelationDefinitionSnapshot {
        guard let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Wait for the current file change to finish, then reopen folder properties.") }
        let origin = workspaceID
        await flush()
        guard workspaceID == origin, !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your unsaved drafts before changing relation definitions.") }
        let snapshot = try await io.relationDefinitionSnapshot()
        guard workspaceID == origin else { throw CancellationError() }
        return NativeRelationDefinitionSnapshot(schema: bound(snapshot.schema), notes: snapshot.notes)
    }
    func saveRelationDefinition(_ plan: NativeRelationDefinitionPlan) async throws {
        guard !schemaSaving, !loading, !switchingVault, !recoverySaving, recovery == nil, let io, root == plan.snapshot.schema.root, plan.snapshot.schema.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed or another file change is still saving. Reload this definition.") }
        schemaSaving = true
        defer { schemaSaving = false }
        await flush()
        guard !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your unsaved drafts before changing relation definitions.") }
        let current = try await io.applyRelationDefinition(plan)
        publish(current)
        for note in notes { sessions[note.path]?.reconcile(note) }
        schemaRevision += 1
    }
    func prepareMove(_ snapshot: NativeRelationDefinitionSnapshot, source: String, destination: String) async throws -> NativeRelationMaintenancePlan {
        guard let io, root == snapshot.schema.root, snapshot.schema.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed. Reopen this move.") }
        let plan = try await io.prepareMove(snapshot, source: source, destination: destination)
        guard root == snapshot.schema.root, snapshot.schema.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func prepareRename(_ snapshot: NativeRelationDefinitionSnapshot, source: String, title: String, renameFile: Bool) async throws -> NativeNoteRenamePlan {
        guard let io, root == snapshot.schema.root, snapshot.schema.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed. Reopen Rename.") }
        let plan = try await io.prepareRename(snapshot, source: source, title: title, renameFile: renameFile)
        guard root == snapshot.schema.root, snapshot.schema.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func saveRelationMaintenance(_ plan: NativeRelationMaintenancePlan) async throws {
        guard !schemaSaving, !loading, !switchingVault, !recoverySaving, recovery == nil, let io, root == plan.snapshot.schema.root, plan.snapshot.schema.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed or another file change is saving. Reload this review.") }
        schemaSaving = true
        defer { schemaSaving = false }
        let editors = Array(sessions.values); editors.forEach { $0.holdForMutation(true) }
        defer { editors.forEach { $0.holdForMutation(false) } }
        await flush()
        guard root == plan.snapshot.schema.root, !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "The vault changed or a draft is unsaved. Reopen this review.") }
        let current = try await io.applyRelationMaintenance(plan)
        guard root == plan.snapshot.schema.root else { throw VaultFailure(message: "The change was saved in the previous vault. Reopen that vault to see it.") }
        let movedEditor = plan.sourcePath != plan.destination ? plan.sourcePath.flatMap { sessions.removeValue(forKey: $0) } : nil
        publish(current)
        if let editor = movedEditor, let destination = plan.destination, let updated = notes.first(where: { $0.path == destination }) {
            editor.reconcile(updated); sessions[destination] = editor
        }
        for note in notes { sessions[note.path]?.reconcile(note) }
        if plan.changes.contains(where: { $0.path == ".zerus/tasks.json" }) { try await loadTasks() }
        schemaRevision += 1
    }
    func saveSchema(snapshot: NativeSchemaSnapshot, owner: String, originalName: String?, definition: NativePropertyDefinition?) async throws {
        guard !schemaSaving, !switchingVault, !recoverySaving, recovery == nil, let io, root == snapshot.root, snapshot.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed or another definition is still saving. Reopen folder properties.") }
        schemaSaving = true
        defer { schemaSaving = false }
        await flush()
        guard !sessions.values.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or resolve your unsaved drafts before changing folder definitions.") }
        let current = try await io.applySchemaChange(snapshot: snapshot, owner: owner, originalName: originalName, definition: definition)
        guard root == snapshot.root else { throw VaultFailure(message: "Reopen the original vault to see the saved definition.") }
        publish(current)
        for note in notes { sessions[note.path]?.reconcile(note) }
        schemaRevision += 1
    }

    private func publishTasks(_ data: NativeTaskData) {
        tasks = data.tasks.map { var task = $0; task.workspaceID = workspaceID; return task }
        taskLists = data.lists; taskCategories = data.categories; generalTaskListName = data.generalName; taskIssue = data.warning; searchRevision += 1
    }
    private func loadTasks() async throws {
        guard let io, !taskWriteInFlight else { return }
        let origin = workspaceID, revision = taskRevision
        let data = try await io.taskData()
        guard origin == workspaceID, revision == taskRevision, !taskWriteInFlight else { return }
        publishTasks(data)
    }
    func newTask(title: String = "") -> NativeTask {
        var task = NativeTask(title: title); task.workspaceID = workspaceID; return task
    }
    func reloadTask(id: String, workspace expected: UUID?) async throws -> NativeTask {
        guard let io, expected == workspaceID, !switchingVault, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen the task.") }
        _ = await taskPipeline?.value
        guard expected == workspaceID, !taskWriteInFlight else { throw VaultFailure(message: "Wait for the current task change, then reload.") }
        let revision = taskRevision, data = try await io.taskData()
        guard expected == workspaceID, revision == taskRevision, !taskWriteInFlight else { throw VaultFailure(message: "Tasks changed again. Reload once the current change finishes.") }
        publishTasks(data)
        guard let task = tasks.first(where: { $0.id == id }) else { throw VaultFailure(message: "This task was removed or its identity is ambiguous. Share your draft before closing.") }
        return task
    }
    @discardableResult
    func saveTask(_ task: NativeTask, delete: Bool = false) async -> Bool {
        guard task.workspaceID == workspaceID else { return false }
        return await changeTasks(.save(task, delete: delete), workspace: workspaceID)
    }
    @discardableResult
    func changeTasks(_ change: NativeTaskChange, workspace expected: UUID) async -> Bool {
        guard !switchingVault, !schemaSaving, !recoverySaving, recovery == nil, expected == workspaceID else { return false }
        let origin = workspaceID, previous = taskPipeline
        taskRevision += 1; pendingTaskChanges += 1; taskWriteInFlight = true
        let operation = Task { [weak self] in
            _ = await previous?.value
            guard let self, self.workspaceID == origin, let io = self.io else { return false }
            defer { if self.workspaceID == origin { self.pendingTaskChanges -= 1; self.taskWriteInFlight = self.pendingTaskChanges > 0 } }
            do {
                let saved = try await io.changeTasks(change)
                guard self.workspaceID == origin else { return false }
                self.publishTasks(saved)
                return true
            } catch { if self.workspaceID == origin { self.error = error.localizedDescription }; return false }
        }
        taskPipeline = operation
        return await operation.value
    }

    private func acquireAgentFiles(workspace expected: UUID) async throws -> VaultFiles {
        guard expected == workspaceID, let io, !switchingVault, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen the AI run in its original vault.") }
        // A model response can arrive during an ordinary foreground scan or
        // another coordinated save. Wait for admission instead of losing it.
        for await _ in Publishers.CombineLatest3($loading, $schemaSaving, $switchingVault).values {
            try Task.checkCancellation()
            guard expected == workspaceID, !switchingVault, !recoverySaving, recovery == nil else { throw CancellationError() }
            if !loading && !schemaSaving {
                schemaSaving = true
                return io
            }
        }
        throw CancellationError()
    }
    private func agentOperation<T: Sendable>(workspace expected: UUID, flushDrafts: Bool = true, _ operation: @Sendable (VaultFiles) async throws -> T) async throws -> T {
        let io = try await acquireAgentFiles(workspace: expected)
        defer { schemaSaving = false }
        try Task.checkCancellation()
        let editors = flushDrafts ? Array(sessions.values) : []
        editors.forEach { $0.holdForMutation(true) }; defer { editors.forEach { $0.holdForMutation(false) } }
        if flushDrafts { await flush() }
        try Task.checkCancellation()
        guard expected == workspaceID, !flushDrafts || !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Keep or resolve your unsaved note drafts before continuing this AI run.") }
        let value = try await operation(io)
        guard expected == workspaceID else { throw CancellationError() }; return value
    }
    // Journal reads share the file actor's ordering without taking the mutation
    // lock. Opening the run list must not interrupt a tool result or review.
    private func agentRead<T: Sendable>(workspace expected: UUID, _ operation: @Sendable (VaultFiles) async throws -> T) async throws -> T {
        guard expected == workspaceID, let io, !switchingVault, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen its AI runs after it finishes opening.") }
        let value = try await operation(io)
        guard expected == workspaceID else { throw CancellationError() }; return value
    }
    func exportAgentJournal(_ path: String, workspace expected: UUID) async throws -> URL {
        guard path.hasPrefix(NativeAgentJournal.directory + "/"), path.split(separator: "/").count == 4, path.hasSuffix(".json") else { throw VaultFailure(message: "This is not an AI run journal.") }
        let bytes = try await agentRead(workspace: expected) { try await $0.read(path) }
        guard bytes.count <= 8_000_000 else { throw VaultFailure(message: "This journal is too large to prepare for sharing. Its original file is preserved.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NativeAIExports/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent((path as NSString).lastPathComponent)
        try bytes.write(to: target, options: .atomic); return target
    }
    func agentRuns(workspace expected: UUID) async throws -> NativeAgentRuns {
        try await agentRead(workspace: expected) { try await $0.agentRuns() }
    }
    func agentWorkflows(workspace expected: UUID) async throws -> NativeAgentWorkflowCatalog {
        try await agentRead(workspace: expected) { try await $0.agentWorkflows() }
    }
    func agentWorkflowDocument(_ id: String, workspace expected: UUID) async throws -> NativeAgentWorkflowDocument {
        try await agentRead(workspace: expected) { try await $0.agentWorkflowDocument(id) }
    }
    func newAgentWorkflow(title: String, workspace expected: UUID) async throws -> NativeAgentWorkflowDocument {
        try await agentRead(workspace: expected) { try await $0.newAgentWorkflow(title: title) }
    }
    func saveAgentWorkflowSelection(_ id: String, expected snapshot: NativeAgentWorkflowCatalog, workspace expected: UUID) async throws -> NativeAgentWorkflowCatalog {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.saveAgentWorkflowSelection(id, expected: snapshot) }
    }
    func saveAgentWorkflow(_ source: String, expected snapshot: NativeAgentWorkflowDocument, workspace expected: UUID) async throws -> NativeAgentWorkflowDocument {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.saveAgentWorkflow(source, expected: snapshot) }
    }
    func agentGuidance(workspace expected: UUID) async throws -> NativeAgentGuidanceSnapshot {
        try await agentRead(workspace: expected) { try await $0.agentGuidance() }
    }
    func agentLimits(workspace expected: UUID) async throws -> NativeAgentLimitsSnapshot {
        try await agentRead(workspace: expected) { try await $0.agentLimits() }
    }
    func saveAgentLimits(_ value: NativeAgentLimits, expected snapshot: NativeAgentLimitsSnapshot, workspace expected: UUID) async throws -> NativeAgentLimitsSnapshot {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.saveAgentLimits(value, expected: snapshot) }
    }
    func agentElapsed(_ record: NativeAgentRecord, owner: String, seconds: Double, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.agentElapsed(record, owner: owner, seconds: seconds) }
    }
    func agentReserveRequest(_ record: NativeAgentRecord, owner: String, input: Int, output: Int, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.agentReserveRequest(record, owner: owner, input: input, output: output) }
    }
    func saveAgentGuidance(_ value: NativeAgentGuidance, expected snapshot: NativeAgentGuidanceSnapshot, workspace expected: UUID) async throws -> NativeAgentGuidanceSnapshot {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.saveAgentGuidance(value, expected: snapshot) }
    }
    func startAgent(objective: String, mode: NativeAgentMode, scope: NativeAgentScope, chatID: String, owner: String, history: String, reference: String, attachments: [NativeChatAttachment] = [], imageIDs: [String] = [], workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected) { try await $0.agentStart(objective: objective, mode: mode, scope: scope, chatID: chatID, owner: owner, history: history, reference: reference, attachments: attachments, imageIDs: imageIDs) }
    }
    func agentResponse(_ record: NativeAgentRecord, owner: String, content: String, calls: [NativeAgentCall], input: Int, output: Int, seconds: Double, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected) { try await $0.agentResponse(record, owner: owner, content: content, calls: calls, input: input, output: output, seconds: seconds) }
    }
    func agentTool(_ record: NativeAgentRecord, owner: String, call: NativeAgentCall, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected) { try await $0.agentTool(record, owner: owner, call: call) }
    }
    func agentPause(_ record: NativeAgentRecord, owner: String, reason: String, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected, flushDrafts: false) { try await $0.agentPause(record, owner: owner, reason: reason) }
    }
    func agentResume(_ record: NativeAgentRecord, owner: String, answer: String?, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected) { try await $0.agentResume(record, owner: owner, answer: answer) }
    }
    func agentReject(_ record: NativeAgentRecord, owner: String, proposalID: UUID, workspace expected: UUID) async throws -> NativeAgentRecord {
        try await agentOperation(workspace: expected) { try await $0.agentReject(record, owner: owner, proposalID: proposalID) }
    }
    func agentReview(_ record: NativeAgentRecord, owner: String, ids: Set<UUID>, automatic: Bool = false, workspace expected: UUID) async throws -> NativeAgentReview {
        var plan = try await agentOperation(workspace: expected) { try await $0.agentReview(record, owner: owner, ids: ids, automatic: automatic) }
        plan.workspaceID = expected; return plan
    }
    func agentUndoReview(_ record: NativeAgentRecord, owner: String, receiptID: UUID, workspace expected: UUID) async throws -> NativeAgentReview {
        var plan = try await agentOperation(workspace: expected) { try await $0.agentUndoReview(record, owner: owner, receiptID: receiptID) }
        plan.workspaceID = expected; return plan
    }
    func applyAgent(_ plan: NativeAgentReview, owner: String) async throws -> NativeAgentRecord {
        guard let expected = plan.workspaceID, plan.root == root else { throw VaultFailure(message: "This AI review belongs to another vault.") }
        let (record, snapshot) = try await agentOperation(workspace: expected) { try await $0.agentApply(plan, owner: owner) }
        publish(snapshot); for note in notes { sessions[note.path]?.reconcile(note) }; schemaRevision += 1
        return record
    }

}

struct NativeTask: Identifiable {
    var raw: [String: Any]
    let baseline: [String: Any]?
    var workspaceID: UUID? = nil
    var id: String { raw["id"] as? String ?? "" }
    var title: String { get { raw["title"] as? String ?? "" } set { raw["title"] = newValue; touch() } }
    var completed: Bool { get { raw["completed"] as? Bool ?? false } set { raw["completed"] = newValue; raw["completedAt"] = newValue ? ISO8601DateFormatter().string(from: Date()) : NSNull(); touch() } }
    var priority: String { get { raw["priority"] as? String ?? "none" } set { raw["priority"] = newValue; touch() } }
    var category: String { get { (raw["category"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) } set { raw["category"] = newValue.isEmpty ? NSNull() : newValue as Any; touch() } }
    var listID: String { get { raw["listId"] as? String ?? "" } set { raw["listId"] = newValue.isEmpty ? NSNull() : newValue as Any; touch() } }
    var linkedNoteIDs: [String] { get { raw["linkedNoteIds"] as? [String] ?? [] } set { raw["linkedNoteIds"] = newValue; touch() } }
    var dueDate: String { get { raw["dueDate"] as? String ?? "" } set { raw["dueDate"] = newValue.isEmpty ? NSNull() : newValue as Any; touch() } }
    var date: String { get { (raw["date"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Self.day(createdAt) } set { raw["date"] = newValue; touch() } }
    var createdAt: Date { (raw["createdAt"] as? String).flatMap(NativeRevisionIndex.date) ?? Date(timeIntervalSince1970: 0) }
    var completedAt: Date? { (raw["completedAt"] as? String).flatMap(NativeRevisionIndex.date) }
    init?(_ raw: [String: Any]) {
        guard Self.supports(raw) else { return nil }; self.raw = raw; baseline = raw
    }
    init?(restoring raw: [String: Any], baseline: [String: Any]?, workspace: UUID? = nil) {
        guard Self.supports(raw), baseline == nil || Self.supports(baseline!), baseline == nil || (baseline?["id"] as? String == raw["id"] as? String && NativeTaskData.equal(baseline?["createdAt"], raw["createdAt"])) else { return nil }
        self.raw = raw; self.baseline = baseline; workspaceID = workspace
    }
    static func supports(_ raw: [String: Any]) -> Bool {
        guard let id = raw["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, raw["title"] is String else { return false }
        for key in ["priority", "date", "dueDate", "listId", "category", "createdAt", "updatedAt", "completedAt"] where raw[key] != nil && !(raw[key] is NSNull) {
            guard raw[key] is String else { return false }
        }
        if let value = raw["completed"], !(value is NSNull) { guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false } }
        if let value = raw["linkedNoteIds"], !(value is [String]) { return false }
        return true
    }
    init(title: String) {
        baseline = nil
        raw = ["id": UUID().uuidString.lowercased(), "title": title, "completed": false, "priority": "none", "date": Self.day(Date()), "createdAt": ISO8601DateFormatter().string(from: Date()), "linkedNoteIds": [String]()]
    }
    mutating func touch() { raw["updatedAt"] = ISO8601DateFormatter().string(from: Date()) }
    static func parseDay(_ value: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }; return date
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}

@MainActor
final class NoteSession: ObservableObject {
    @Published var document: NoteDocument
    @Published var dirty = false
    @Published var saving = false
    @Published var failure: String?
    private var baseline: String
    private let io: VaultFiles
    private var draftURL: URL
    private let vaultID: UUID?
    private var draftNoteID: String?
    private var retainedDrafts: [(url: URL, bytes: Data)] = []
    private var requiresDraftReview = false
    private let root: URL
    private var pending: Task<Void, Never>?
    private var pausedForRecovery = false
    private var active = true
    private var mutationHeld = false
    private var saveOperation: (id: UUID, task: Task<Void, Never>)?
    private let onSave: (NoteDocument) -> Void

    init(note: NoteDocument, root: URL, io: VaultFiles, vaultID: UUID? = nil, onSave: @escaping (NoteDocument) -> Void) {
        document = note; baseline = note.content; self.io = io; self.onSave = onSave; self.root = root
        self.vaultID = vaultID; draftNoteID = note.stableID
        draftURL = Self.draftLocation(root: root, path: note.path, vaultID: vaultID, noteID: note.stableID)
        let candidates = [draftURL,
            Self.draftLocation(root: root, path: note.path, vaultID: vaultID, noteID: nil),
            Self.draftLocation(root: root, path: note.path)]
        for url in candidates {
            guard let data = try? Data(contentsOf: url), let draft = try? JSONDecoder().decode(Draft.self, from: data),
                  draft.vaultID == nil || draft.vaultID == vaultID,
                  draft.noteID == nil || draft.noteID == note.stableID else { continue }
            if url != draftURL { retainedDrafts.append((url, data)) }
            // A completed write may leave its old private record behind. Never
            // replace a newer canonical file with a clean, obsolete baseline.
            if draft.content == draft.baseline || draft.content == note.content {
                retireDrafts(); break
            }
            document.content = draft.content; baseline = draft.baseline; dirty = true
            let trusted = vaultID != nil && draft.vaultID == vaultID && note.stableID != nil && draft.noteID == note.stableID
            if draft.baseline != note.content {
                requiresDraftReview = true
                failure = "A recovered draft differs from the file. Share the draft or keep it as a new note before reloading the current file."
            } else if !trusted {
                requiresDraftReview = true
                failure = "A draft was recovered. Review its text, then choose Try saving again to save it to this note."
            } else { scheduleSave() }
            break
        }
    }
    func deactivate() { active = false; pending?.cancel() }
    func holdForMutation(_ held: Bool) { mutationHeld = held; if held { pending?.cancel() } }
    private static func draftLocation(root: URL, path: String, vaultID: UUID? = nil, noteID: String? = nil) -> URL {
        let identity = vaultID.map { "vault:" + $0.uuidString.lowercased() + "|" + (noteID.map { "note:" + $0 } ?? "path:" + path) } ?? root.absoluteString + "|" + path
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeDrafts/\(key).json")
    }
    private func retireDrafts() {
        try? FileManager.default.removeItem(at: draftURL)
        for source in retainedDrafts where (try? Data(contentsOf: source.url)) == source.bytes {
            try? FileManager.default.removeItem(at: source.url)
        }
        retainedDrafts.removeAll()
    }
    private func locateDraft(for note: NoteDocument) {
        let next = Self.draftLocation(root: root, path: note.path, vaultID: vaultID, noteID: note.stableID)
        if next != draftURL, let bytes = try? Data(contentsOf: draftURL) { retainedDrafts.append((draftURL, bytes)) }
        draftURL = next; draftNoteID = note.stableID
    }
    func reconcile(_ note: NoteDocument) {
        guard active else { return }
        if dirty || saving {
            if note.content != baseline && !saving {
                pending?.cancel(); pausedForRecovery = true
                failure = "This note changed in another editor. Your draft is kept on this device. Share it or keep it as a new note, then reload the current file."
            }
            return
        }
        if document.path != note.path || draftNoteID != note.stableID {
            retireDrafts(); locateDraft(for: note)
        }
        document = note; baseline = note.content
    }

    func pauseForRecovery() {
        pausedForRecovery = true; pending?.cancel()
        if dirty { failure = "An interrupted file change needs review. Your unsaved draft is kept on this device." }
    }
    func finishRecovery(with note: NoteDocument?) {
        if dirty {
            // The chosen file may equal the old baseline. Retrying an old
            // autosave would silently replace the user's confirmed choice.
            failure = "Your unsaved draft is kept on this device. Share it or keep it as a new note, then reload the chosen file."
        } else {
            pausedForRecovery = false; failure = nil
            if let note { reconcile(note) }
        }
    }
    func reload() async {
        guard active, !saving else { return }
        do {
            let bytes = try await io.read(document.path)
            guard active else { return }
            guard let content = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "This file is not UTF-8 Markdown.") }
            pending?.cancel(); pausedForRecovery = false; requiresDraftReview = false
            baseline = content; document.content = content; dirty = false; failure = nil
            retireDrafts(); locateDraft(for: document)
            onSave(document)
        } catch { failure = error.localizedDescription }
    }
    private struct Draft: Codable {
        let content: String
        let baseline: String
        let vaultID: UUID?
        let noteID: String?
    }
    @discardableResult private func keepDraft() -> Bool {
        do {
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Draft(content: document.content, baseline: baseline, vaultID: vaultID, noteID: draftNoteID)).write(to: draftURL, options: .atomic)
            return true
        } catch { failure = "Could not keep a recovery draft: \(error.localizedDescription)"; return false }
    }
    func retrySave() async {
        guard active, !pausedForRecovery, !mutationHeld else { return }
        guard keepDraft() else { return }
        requiresDraftReview = false
        await save()
    }
    func updateBody(_ body: String) { updateContent(document.replacingBody(body)) }
    func updateContent(_ text: String) {
        guard active, !mutationHeld else { return }
        document.content = text; dirty = text != baseline; requiresDraftReview = false
        keepDraft()
        scheduleSave()
    }
    private func scheduleSave() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)); await self?.save() } catch {}
        }
    }
    func save() async {
        while active && dirty && !pausedForRecovery && !requiresDraftReview {
            let operation: (id: UUID, task: Task<Void, Never>)
            if let current = saveOperation { operation = current }
            else {
                operation = (UUID(), Task<Void, Never> { [weak self] in await self?.performSave() })
                saveOperation = operation
            }
            // Every waiter owns the same completed operation; an older waiter
            // cannot clear a newer save that started while it was resuming.
            await operation.task.value
            if saveOperation?.id == operation.id { saveOperation = nil }
            if failure != nil { return }
        }
    }
    private func performSave() async {
        saving = true
        defer { saving = false }
        while active && dirty && !pausedForRecovery && !requiresDraftReview {
            if document.stableID == nil {
                do { document.content = try NativeFrontmatter(document.content).setting("zerus-id", value: .text(UUID().uuidString.lowercased())) }
                catch { failure = error.localizedDescription; break }
            }
            let text = document.content
            do {
                try await io.write(document.path, data: Data(text.utf8), expected: Data(baseline.utf8))
                baseline = text; document.modified = Date(); dirty = document.content != text; failure = nil
                var committed = document; committed.content = text; onSave(committed)
                locateDraft(for: committed)
                if !dirty { retireDrafts() }
                else if !keepDraft() { break }
            } catch { failure = error.localizedDescription; break }
        }
    }
}


extension VaultStore {
    private func mappingWorker() throws -> NativeFileMappings {
        guard let root else { throw VaultFailure(message: "Open a vault first.") }
        if let worker = fileMappingWorkers[root] { return worker }
        let worker = NativeFileMappings(root: root); fileMappingWorkers[root] = worker; return worker
    }
    func refreshFileLocations() async {
        guard let io else { return }; let origin = workspaceID
        do {
            let value = try await io.fileLocations()
            guard origin == workspaceID else { return }
            fileLocations = value.locations; fileLocationIssue = value.warning
        } catch { if origin == workspaceID { fileLocationIssue = error.localizedDescription } }
    }
    func selectFile(_ url: URL, workspace expected: UUID) async throws -> NativeFileLease {
        guard expected == workspaceID, !switchingVault else { throw CancellationError() }
        let lease = try await mappingWorker().selected(url)
        guard expected == workspaceID else { throw CancellationError() }; return lease
    }
    func fileHubLease(_ note: NoteDocument, workspace expected: UUID) async throws -> NativeFileLease {
        guard expected == workspaceID, note.workspaceID == expected, let reference = note.fileHub else { throw CancellationError() }
        let worker = try mappingWorker()
        if let selection = try await worker.driveFolder(for: reference), let path = reference.path {
            let (bytes, item) = try await NativeDriveAccount.shared.files(account: selection.accountID).download(selection, path: path)
            guard expected == workspaceID, try await worker.driveFolder(for: reference) == selection else { throw CancellationError() }
            let value = try await worker.downloaded(bytes, name: item.name)
            guard expected == workspaceID, try await worker.driveFolder(for: reference) == selection else { throw CancellationError() }
            return value
        }
        let value = try await worker.resolve(reference)
        guard expected == workspaceID else { throw CancellationError() }; return value
    }
    func attachmentLease(_ item: NativeFileAttachment, workspace expected: UUID) async throws -> NativeFileLease {
        guard expected == workspaceID else { throw CancellationError() }
        let value = try await mappingWorker().resolve(.init(id: "vault-attachment:" + item.path, name: item.name, kind: .vault, path: item.path))
        guard expected == workspaceID else { throw CancellationError() }; return value
    }
    func locationMappingLabel(_ id: String, workspace expected: UUID) async throws -> String? {
        guard expected == workspaceID else { throw CancellationError() }
        let value = try await mappingWorker().locationLabel(id)
        guard expected == workspaceID else { throw CancellationError() }; return value
    }
    func mapFileLocation(_ id: String, folder: URL?, workspace expected: UUID) async throws {
        guard expected == workspaceID, !switchingVault, recovery == nil, fileLocations.contains(where: { $0.id == id }) else { throw VaultFailure(message: "This location or vault changed. Reopen File locations.") }
        try await mappingWorker().mapLocation(id, url: folder)
        guard expected == workspaceID else { throw CancellationError() }; searchRevision += 1
    }
    func mapDriveLocation(_ id: String, selection: NativeDriveFolder, workspace expected: UUID) async throws {
        guard expected == workspaceID, !switchingVault, recovery == nil, fileLocations.contains(where: { $0.id == id }) else { throw CancellationError() }
        let folder = try await NativeDriveAccount.shared.files(account: selection.accountID).metadata(selection.folderID)
        guard folder.folder else { throw VaultFailure(message: "Choose an ordinary Google Drive folder.") }
        guard expected == workspaceID, !switchingVault, fileLocations.contains(where: { $0.id == id }) else { throw CancellationError() }
        try await mappingWorker().mapDriveLocation(id, selection: .init(accountID: selection.accountID, email: selection.email, folderID: folder.id, name: selection.name))
        guard expected == workspaceID else { throw CancellationError() }; searchRevision += 1
    }
    func changeFileLocation(_ change: NativeFileLocationChange, workspace expected: UUID) async throws {
        guard let io, expected == workspaceID, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Wait for the current change, then reopen File locations.") }
        schemaSaving = true; defer { schemaSaving = false }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or share your drafts before editing file locations.") }
        let result = try await io.changeFileLocation(change)
        guard expected == workspaceID else { throw CancellationError() }
        fileLocations = result.locations; fileLocationIssue = result.warning; searchRevision += 1
    }
    func locateFile(_ note: NoteDocument, source: NativeFileLease, workspace expected: UUID) async throws {
        guard expected == workspaceID, note.workspaceID == expected, !switchingVault, recovery == nil, let original = note.fileHub,
              searchableNotes.first(where: { $0.path == note.path })?.fileHub == original else { throw VaultFailure(message: "This linked file changed. Reopen it before locating the original.") }
        try await mappingWorker().locate(original, source: source)
        guard expected == workspaceID else { throw CancellationError() }; searchRevision += 1
    }
    func saveFileHub(session: NoteSession? = nil, original: NativeFileHub? = nil, source: NativeFileLease?, storage: NativeFileStorage = .copy, title: String = "", folder: String = "Inbox", detach: Bool = false, workspace expected: UUID) async throws -> NoteDocument {
        guard source?.temporaryDirectory == nil || storage == .copy || detach else { throw VaultFailure(message: "A downloaded preview can be copied into the vault. Map its Drive folder to keep an original connection.") }
        guard let io, expected == workspaceID, !switchingVault, !schemaSaving, recovery == nil, session == nil || session?.document.workspaceID == expected else { throw VaultFailure(message: "The vault changed or another change is saving. Reopen the file action.") }
        schemaSaving = true; defer { schemaSaving = false }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or share your drafts before changing a linked file.") }
        let basis = try await io.scan(), mappings = try mappingWorker()
        let locations = storage == .copy || detach ? try NativeFileLocations(nil) : try await io.fileLocations()
        guard expected == workspaceID else { throw CancellationError() }
        let note = session?.document
        guard note?.fileHub == original else { throw VaultFailure(message: "The file connection changed while this action was open.") }
        if let source, !detach {
            for candidate in basis.notes where !candidate.trashed && candidate.path != note?.path {
                guard let hub = candidate.fileHub, let existing = try? await mappings.resolve(hub), existing.url.resolvingSymlinksInPath().standardizedFileURL == source.url.resolvingSymlinksInPath().standardizedFileURL else { continue }
                guard expected == workspaceID else { throw CancellationError() }
                if note == nil { var existing = candidate; existing.workspaceID = expected; return existing }
                throw VaultFailure(message: "This document already has a note: \(candidate.title). Open that note instead.")
            }
        }
        let reference: NativeFileHub?
        if detach { reference = nil }
        else {
            guard let source else { throw VaultFailure(message: "Choose a document first.") }
            let id = UUID().uuidString.lowercased()
            if storage == .copy { reference = .init(id: id, name: source.url.lastPathComponent, kind: .local) }
            else { reference = try await mappings.reference(for: source, id: id, locations: locations.locations) }
            if storage != .copy, reference?.kind == .local { try await mappings.locate(reference!, source: source) }
        }
        guard expected == workspaceID else { throw CancellationError() }
        let result = try await io.saveFileHub(basis: basis, note: note, original: original, reference: reference, title: title, folder: folder, source: source, storage: storage, locations: locations)
        guard expected == workspaceID else { throw CancellationError() }
        let snapshot = try await io.scan()
        guard expected == workspaceID else { throw CancellationError() }
        publish(snapshot)
        for note in notes { sessions[note.path]?.reconcile(note) }
        var saved = result; saved.workspaceID = expected; return saved
    }
}

extension VaultStore {
    func imageSnapshot(workspace expected: UUID) async throws -> NativeImageSnapshot {
        guard expected == workspaceID, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reopen Images.") }
        await flush()
        guard expected == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before reviewing images.") }
        var snapshot = try await io.imageSnapshot()
        guard expected == workspaceID else { throw CancellationError() }
        snapshot.workspaceID = expected
        return snapshot
    }
    func prepareImageChange(_ snapshot: NativeImageSnapshot, action: NativeImageChange) async throws -> NativeImagePlan {
        guard snapshot.workspaceID == workspaceID, snapshot.root == root, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "The vault changed. Reload Images.") }
        let plan = try await io.prepareImageChange(snapshot, action: action)
        guard snapshot.workspaceID == workspaceID else { throw CancellationError() }
        return plan
    }
    func undoImageChange(_ original: NativeImagePlan) async throws {
        guard original.snapshot.workspaceID == workspaceID, original.snapshot.root == root, let io else { throw VaultFailure(message: "The vault changed. Restore the image from its original vault’s Recently Deleted.") }
        var plan = try await io.prepareImageUndo(original)
        var snapshot = plan.snapshot; snapshot.workspaceID = original.snapshot.workspaceID
        plan = .init(snapshot: snapshot, action: plan.action, changes: plan.changes, title: plan.title, explanation: plan.explanation, files: plan.files)
        try await saveImageChange(plan)
    }
    func saveImageChange(_ plan: NativeImagePlan) async throws {
        guard plan.snapshot.workspaceID == workspaceID, plan.snapshot.root == root, let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or another change is saving. Reload the image review.") }
        schemaSaving = true; defer { schemaSaving = false }
        await flush()
        guard plan.snapshot.workspaceID == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your drafts before changing images.") }
        let editors = Array(sessions.values); editors.forEach { $0.holdForMutation(true) }; defer { editors.forEach { $0.holdForMutation(false) } }
        let saved = try await io.applyImageChange(plan)
        guard plan.snapshot.workspaceID == workspaceID else { throw CancellationError() }
        publish(saved); schemaRevision += 1
        for note in notes { sessions[note.path]?.reconcile(note) }
    }
    func imageLease(_ reference: String, notePath: String? = nil, workspace expected: UUID) async throws -> NativeFileLease {
        guard expected == workspaceID, let root, let io else { throw VaultFailure(message: "This image is unavailable. Reopen it in its original vault.") }
        let url: URL
        if let notePath { url = try await io.resolveResource(reference, notePath: notePath) }
        else { url = try await io.url(for: reference) }
        guard expected == workspaceID else { throw CancellationError() }
        return try NativeFileLease(scope: root, url: url)
    }
    func prepareExternalTransfer(session: NativeExternalNoteSession, project: NativeExternalProjectFiles?, folder: String,
                                 mode: NativeExternalTransferMode, workspace expected: UUID) async throws -> NativeExternalTransferReview {
        guard expected == workspaceID, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Open a destination vault before importing this file.") }
        session.finishEditors()
        await session.save(); await session.refresh(); await flush()
        guard expected == workspaceID, !session.dirty, !session.conflict, session.failure == nil else { throw VaultFailure(message: session.failure ?? "Save or keep this file’s draft before importing it.") }
        let review = try await io.prepareExternalTransfer(session.snapshot, project: project, folder: folder, mode: mode, workspaceID: expected)
        guard expected == workspaceID else { throw CancellationError() }; return review
    }
    func preparePendingExternalMove(_ record: NativeExternalMoveRecord, session: NativeExternalNoteSession, workspace expected: UUID) async throws -> NativeExternalTransferReview {
        guard expected == workspaceID, let io, !switchingVault, !schemaSaving, recovery == nil, record.phase != .removed else { throw VaultFailure(message: "Open the move’s destination vault before reviewing its original.") }
        session.finishEditors()
        await session.save(); await session.refresh()
        guard expected == workspaceID, !session.dirty, !session.conflict, session.failure == nil,
              session.id == record.sourceID, session.snapshot.bytes == record.sourceBytes else {
            throw VaultFailure(message: "The original changed after the vault copy was saved. Its current file and the retained recovery copy are preserved.")
        }
        let note = try await io.pendingExternalMoveNote(record), destination = try record.destination()
        let lease = try NativeFileLease(scope: session.snapshot.access.url)
        guard expected == workspaceID else { throw CancellationError() }
        var review = NativeExternalTransferReview(id: record.id, mode: .move, workspaceID: expected, destination: destination,
            source: session.snapshot, sourceLease: lease, project: nil, path: record.destinationPath, content: note.content,
            noteID: record.noteID, assets: [], existingNotePaths: [], noteInventory: [],
            warnings: ["The vault copy already exists. This review only removes the unchanged original Markdown file; project images and linked files stay in place."])
        review.pendingMove = record; return review
    }
    func commitExternalTransfer(_ review: NativeExternalTransferReview, session: NativeExternalNoteSession,
                                external: NativeExternalNotesModel) async throws -> NativeExternalTransferOutcome {
        guard review.workspaceID == workspaceID, review.destination.root.resolvingSymlinksInPath().standardizedFileURL == root?.resolvingSymlinksInPath().standardizedFileURL,
              let io, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or another change is saving. Review this import again.") }
        schemaSaving = true; defer { schemaSaving = false }
        await flush()
        guard review.workspaceID == workspaceID, !sessions.values.contains(where: \.dirty) else { throw VaultFailure(message: "Save or keep your vault drafts before importing a file.") }
        session.finishEditors()
        try session.beginTransfer(review.source); defer { session.endTransfer() }
        let editors = Array(sessions.values); editors.forEach { $0.holdForMutation(true) }; defer { editors.forEach { $0.holdForMutation(false) } }
        var record = review.pendingMove, copied: NoteDocument?, sourceRemoved = false
        do {
            if review.mode == .move, record == nil {
                let next = try NativeExternalTransferFiles.record(for: review)
                try await external.moveStore.save(next, replacing: nil); record = next
            }
            if let record = review.pendingMove { copied = try await io.pendingExternalMoveNote(record) }
            else { copied = try await io.commitExternalCopy(review) }
            publish(try await io.scan()); schemaRevision += 1
            if review.mode == .move, var next = record {
                if next.phase == .prepared {
                    next.phase = .copied; try await external.moveStore.save(next, replacing: record); record = next
                }
                try await NativeExternalTransferFiles.removeOriginal(review.source, record: next, destination: review.destination)
                sourceRemoved = true; session.markMoved()
                next.phase = .removed; try await external.moveStore.save(next, replacing: record); record = next
                try await external.finishImportedMove(next.sourceID)
                try await external.moveStore.finish(next)
            }
            await external.restore()
            var note = copied!; note.workspaceID = review.workspaceID
            return .init(note: note, sourceRemoved: sourceRemoved, recoveryPending: false, message: nil)
        } catch {
            await external.restore()
            if var note = copied {
                note.workspaceID = review.workspaceID
                let message = sourceRemoved ? "The file moved into the vault. Its saved connection still needs cleanup in Pending moves. " : "The vault copy is kept. The original has not been removed. "
                return .init(note: note, sourceRemoved: sourceRemoved, recoveryPending: record != nil, message: message + error.localizedDescription)
            }
            throw error
        }
    }
    func finishPendingExternalConnection(_ record: NativeExternalMoveRecord, external: NativeExternalNotesModel, workspace expected: UUID) async throws {
        guard expected == workspaceID, let io, !switchingVault, !schemaSaving, recovery == nil else { throw VaultFailure(message: "Open this move’s destination vault before finishing its saved connection.") }
        schemaSaving = true; defer { schemaSaving = false }
        _ = try await io.pendingExternalMoveNote(record)
        try await external.finishImportedMove(record.sourceID, sourceRemoved: record.phase == .removed)
        try await external.moveStore.finish(record); await external.restore()
    }

}


extension VaultStore {
    func createFolder(_ name: String, workspace expected: UUID) async throws {
        guard let io, expected == workspaceID, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reopen New folder.") }
        schemaSaving = true; defer { schemaSaving = false }
        let snapshot = try await io.createFolder(name)
        guard expected == workspaceID else { throw CancellationError() }
        publish(snapshot)
    }
    func folderIconSnapshot(workspace expected: UUID) async throws -> NativeFolderIconSnapshot {
        guard let io, expected == workspaceID, !switchingVault else { throw CancellationError() }
        var snapshot = try await io.folderIconSnapshot()
        guard expected == workspaceID else { throw CancellationError() }
        snapshot.workspaceID = expected; return snapshot
    }
    func setFolderIcon(_ snapshot: NativeFolderIconSnapshot, folder: String, value: String?) async throws {
        guard let io, snapshot.workspaceID == workspaceID, snapshot.root == root, !switchingVault, !schemaSaving, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reopen the icon picker.") }
        schemaSaving = true; defer { schemaSaving = false }
        publish(try await io.setFolderIcon(snapshot, folder: folder, value: value))
    }
    func reorderFolder(_ folder: String, direction: Int, workspace expected: UUID) {
        guard expected == workspaceID, let id = activeVaultID, !switchingVault,
              let other = NativeFolderOrder.adjacent(folder, in: folders, direction: direction) else { return }
        var order = folders
        guard let a = order.firstIndex(of: folder), let b = order.firstIndex(of: other) else { return }
        order.swapAt(a, b); folderOrder = order
        UserDefaults.standard.set(order, forKey: NativeFolderOrder.key(id))
    }
    func prepareFolderRename(_ snapshot: NativeRelationDefinitionSnapshot, source: String, destination: String) async throws -> NativeFolderRenamePlan {
        guard let io, snapshot.schema.workspaceID == workspaceID, snapshot.schema.root == root, !switchingVault else { throw VaultFailure(message: "The vault changed. Reopen Rename folder.") }
        let plan = try await io.prepareFolderRename(snapshot, source: source, destination: destination)
        guard snapshot.schema.workspaceID == workspaceID else { throw CancellationError() }; return plan
    }
    func saveFolderRename(_ plan: NativeFolderRenamePlan) async throws {
        guard let io, plan.snapshot.schema.workspaceID == workspaceID, plan.snapshot.schema.root == root,
              !switchingVault, !schemaSaving, !loading, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reload Rename folder.") }
        schemaSaving = true; defer { schemaSaving = false }
        let editors = Array(Set(sessions.values.map(ObjectIdentifier.init))).compactMap { id in sessions.values.first { ObjectIdentifier($0) == id } }
        editors.forEach { $0.holdForMutation(true) }; defer { editors.forEach { $0.holdForMutation(false) } }
        await flush()
        guard !editors.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your drafts before renaming this folder.") }
        let snapshot = try await io.applyFolderRename(plan)
        publish(snapshot)
        for editor in editors {
            let next = NativeFolderRenamePlan.notePath(editor.document.path, source: plan.source, destination: plan.destination)
            if let note = notes.first(where: { $0.path == next }) { editor.reconcile(note); sessions[next] = editor }
        }
        if let id = activeVaultID {
            folderOrder = folderOrder.map { NativeFolderPath.remap($0, from: plan.source, to: plan.destination) }
            UserDefaults.standard.set(folderOrder, forKey: NativeFolderOrder.key(id))
            let original = NativeNoteDefaults.load(id), next = NativeFolderPath.remap(original, from: plan.source, to: plan.destination)
            if next != original { UserDefaults.standard.set(next, forKey: NativeNoteDefaults.key(id)) }
        }
        try await loadTasks(); schemaRevision += 1
    }
}


extension VaultStore {
    func folderTrashSnapshot(workspace expected: UUID) async throws -> NativeFolderTrashSnapshot {
        guard let io, expected == workspaceID, !switchingVault else { throw CancellationError() }
        let snapshot = try await io.folderTrashSnapshot()
        guard expected == workspaceID else { throw CancellationError() }; return snapshot
    }
    func prepareFolderTrash(_ folder: String, workspace expected: UUID) async throws -> NativeFolderTrashPlan {
        guard let io, expected == workspaceID, !switchingVault else { throw VaultFailure(message: "The vault changed. Reopen the folder review.") }
        var plan = try await io.prepareFolderTrash(folder)
        guard expected == workspaceID else { throw CancellationError() }; plan.workspaceID = expected; return plan
    }
    func prepareFolderRestore(_ entry: NativeFolderTrashEntry, purge: Bool, workspace expected: UUID) async throws -> NativeFolderTrashPlan {
        guard let io, expected == workspaceID, !switchingVault else { throw VaultFailure(message: "The vault changed. Reopen Recently Deleted.") }
        var plan = try await io.prepareFolderRestore(entry, purge: purge)
        guard expected == workspaceID else { throw CancellationError() }; plan.workspaceID = expected; return plan
    }
    func saveFolderTrash(_ plan: NativeFolderTrashPlan) async throws {
        guard let io, plan.root == root, plan.workspaceID == workspaceID, !switchingVault, !schemaSaving, !loading, !recoverySaving, recovery == nil else { throw VaultFailure(message: "The vault changed or a file change is saving. Reload the folder review.") }
        schemaSaving = true; defer { schemaSaving = false }
        let editors = Array(Set(sessions.values.map(ObjectIdentifier.init))).compactMap { id in sessions.values.first { ObjectIdentifier($0) == id } }
        editors.forEach { $0.holdForMutation(true) }; defer { editors.forEach { $0.holdForMutation(false) } }
        await flush()
        guard !editors.contains(where: { $0.dirty }) else { throw VaultFailure(message: "Save or keep your drafts before changing this folder.") }
        let snapshot = try await io.applyFolderTrash(plan)
        if plan.action == .trash {
            for editor in editors where editor.document.path.hasPrefix(plan.entry.record.folder + "/") { discardSession(editor) }
            if let id = activeVaultID {
                let folder = plan.entry.record.folder
                folderOrder = folderOrder.filter { $0 != folder && !$0.hasPrefix(folder + "/") }
                UserDefaults.standard.set(folderOrder, forKey: NativeFolderOrder.key(id))
                let original = NativeNoteDefaults.load(id)
                if original == folder || original.hasPrefix(folder + "/") { UserDefaults.standard.removeObject(forKey: NativeNoteDefaults.key(id)) }
            }
        }
        publish(snapshot); schemaRevision += 1
    }
}
