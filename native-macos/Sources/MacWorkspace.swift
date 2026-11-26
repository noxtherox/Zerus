import SwiftUI
import AppKit
import Combine

/// Live note text has narrower observers than the vault/navigation model.
/// The workspace reads this same value for saving and recovery.
@MainActor final class MacNoteDraftState: ObservableObject {
    @Published var body = ""
    @Published var saveStatus = "Saved"
    /// Index of the outline heading at the top of the editor viewport.
    @Published var visibleHeading: Int?
}

/// Bulk selection belongs to collection content, not the editor or library.
/// Keep its notifications local while the workspace owns the selection rules.
@MainActor final class MacCollectionSelectionState: ObservableObject {
    @Published fileprivate(set) var paths = Set<String>()
    @Published fileprivate(set) var selecting = false
}

/// A Mac window owns its navigation and drafts. Shared files remain the source of truth.
/// Observation tracks each property separately, so a view re-renders only
/// for the values it reads (not for every change anywhere in the window).
/// Caches filled from getters and task plumbing are ignored by observation.
@MainActor @Observable
final class MacWorkspace {
    final class Weak { weak var value: MacWorkspace?; init(_ value: MacWorkspace) { self.value = value } }
    static var windows: [Weak] = []
    private let draftOwner = UUID().uuidString.lowercased()
    @ObservationIgnored private var adoptedDrafts: [String: [MacNoteRecoveryRecord]] = [:]
    /// The external library is its own ObservableObject; reading it through
    /// the workspace depends on `externalRevision`, which its changes bump.
    @ObservationIgnored private let externalStorage = MacExternalLibrary()
    private(set) var externalRevision = 0
    var external: MacExternalLibrary { _ = externalRevision; return externalStorage }
    /// Bumped when a preference stored outside the workspace (UserDefaults) changes.
    var preferenceRevision = 0
    let desktopFiles = MacDesktopFileOpener()
    @ObservationIgnored weak var presentationWindow: NSWindow?
    @ObservationIgnored private var externalObserver: AnyCancellable?
    private(set) var fileMappings: NativeFileMappings?
    private(set) var folderIcons: [Data: String] = [:]
    private var folderIconBytes: Data?
    private(set) var folderIconIssue: String?
    var settingsImport: MacDesktopSettingsReview?
    var printRequest: MacExportRequest?
    var previewDocument: NativeFileLease?
    var fileMappingRevision = 0
    var imageUndo: MacImageReview?
    var editorSheetActive = false
    var agentSettingsActive = false
    var imageSaving = false
    var recoverySaving = false
    var schemaMaintenanceSaving = false
    var externalCopySaving = false
    var paneLayout = MacPaneLayout()
    var paneLayoutSaving = false
    var paneLayoutReady = false
    var paneLayoutIssue: String?
    var paneRevision = 0
    var noteMovesSaving = false
    var noteMoveProgress = (0, 0)
    init() { Self.windows = Self.windows.filter { $0.value != nil }; Self.windows.append(Weak(self)); externalObserver = externalStorage.objectWillChange.sink { [weak self] _ in self?.externalRevision &+= 1 } }

    var root: URL?
    var notes: [NoteDocument] = [] { didSet { collectionRevision &+= 1; cachedCollection = nil; cachedBacklinks = nil } }
    var folders: [String] = [] { didSet { folderOrderingCache = nil } }
    private(set) var folderOrder: [String] = [] { didSet { folderOrderingCache = nil } }
    @ObservationIgnored private var folderOrderingCache: MacFolderOrdering?
    var files: [String] = []
    private(set) var collectionFileDates: [String: NativeFileDates] = [:]
    var tasks: [NativeTask] = []
    var taskLists: [NativeTaskList] = []
    var taskCategories: [String] = []
    var generalTaskListName = "General"
    var taskWarning: String?
    var taskDraftStore: NativeTaskDraftStore?
    var taskDraftIssue: String?
    var tasksSaving = false { didSet { if tasksSaving != oldValue { tasksSavingSubject.send(tasksSaving) } } }
    /// Every change of `tasksSaving`, delivered synchronously (as `$tasksSaving` was).
    var tasksSavingPublisher: AnyPublisher<Bool, Never> { tasksSavingSubject.eraseToAnyPublisher() }
    @ObservationIgnored private let tasksSavingSubject = CurrentValueSubject<Bool, Never>(false)
    @ObservationIgnored private var taskPipeline: Task<Bool, Never>?
    private var taskRevision = 0
    private var pendingTaskChanges = 0
    var destination = "All Notes"
    var folderCollection = false
    var query = "" { didSet { if query != oldValue { editorFocusRequest = nil; clearCollectionSelection() }; persistNavigation(deferWrite: true) } }
    var filters = NativeCollectionFilters() { didSet { if filters != oldValue { clearCollectionSelection() }; persistNavigation() } }
    var selection: String? { didSet { if let previous = oldValue, previous != selection { scheduleTitleFileSync(previous) } } }
    /// Title each note had when last opened, used to tell whether its file
    /// name still follows the title (see `MacTitleFileSync`).
    @ObservationIgnored private var openedTitles: [String: String] = [:]
    @ObservationIgnored private var titleSyncJobs: [String: Task<Void, Never>] = [:]
    private(set) var pinnedTabs = Set<MacTab>()
    var tabs: [MacTab] = [] { didSet {
        let kept = pinnedTabs.intersection(Set(tabs))
        if kept != pinnedTabs { pinnedTabs = kept }
        persistNavigation()
    } }
    var activeTab: MacTab? { didSet { persistNavigation() } }
    var hideSubtypes = false { didSet { if hideSubtypes != oldValue { clearCollectionSelection() }; persistNavigation() } }
    var keptFolders = Set<String>() { didSet { persistNavigation() } }
    var collapsedFolders = Set<String>() { didSet { persistNavigation() } }
    let draftState = MacNoteDraftState()
    var body: String { get { draftState.body } set { draftState.body = newValue } }
    var sourceMode = false
    // Admission depends only on exact source bytes. Keep a small window-local
    // set so reopening retained editors does not rebuild the same parser tree.
    // Large bodies still use the full check without retaining extra text here.
    @ObservationIgnored private var openingAdmissions: [(body: String, required: Bool)] = []
    private func openingRequiresSource(_ text: String) -> Bool {
        if let index = openingAdmissions.firstIndex(where: { $0.body.utf8.elementsEqual(text.utf8) }) {
            let entry = openingAdmissions.remove(at: index)
            openingAdmissions.append(entry)
            return entry.required
        }
        let required = MacMarkdown.requiresSource(text)
        if text.utf8.count <= 1_048_576 {
            if openingAdmissions.count == 4 { openingAdmissions.removeFirst() }
            openingAdmissions.append((text, required))
        }
        return required
    }
    var browsingCollection = false
    var inspector = true { didSet { persistNavigation() } }
    var inspectorRequest = 0
    private var noteEditRevision = 0
    var showSearch = false
    var showNoteRecovery = false
    private(set) var preparingToClose = false
    var globalQuery = ""
    var showChat = false
    var missingNoteLink: MacMissingNoteLink?
    private(set) var editorFocusRequest: UUID?
    var headingRequest: MacHeadingRequest?
    @ObservationIgnored var agentController: MacAgentController?
    var agentWritingHeld = false
    var busy = false { didSet { if busy != oldValue { busySubject.send(busy) } } }
    /// Every change of `busy`, delivered synchronously (as `$busy` was).
    var busyPublisher: AnyPublisher<Bool, Never> { busySubject.eraseToAnyPublisher() }
    @ObservationIgnored private let busySubject = CurrentValueSubject<Bool, Never>(false)
    /// Optimistic kanban moves: the card renders in its target column while the
    /// single-note write runs. Entries are cleared by the move that set them.
    var boardPendingMoves: [String: MacBoardPendingMove] = [:]
    /// A board write is in flight. Polling defers to it, but the window stays usable.
    var boardSaving = false
    @ObservationIgnored var boardMoveChain: Task<Void, Never>?
    @ObservationIgnored var cachedBoardSnapshot: (key: MacBoardSnapshotKey, value: (scope: MacBoardScope, groups: [MacCollectionGroup]))?
    private(set) var usingStartupCache = false
    private(set) var startupRefreshing = false
    private(set) var startupIssue: String?
    private var startupIdentity: MacStartupIdentity?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    private var startupRequest: UUID?
    private var startupSaved: [String: NoteDocument] = [:]
    private var startupSaveRevision = 0
    private var snapshotRevision = 0
    private var startupTaskData: Data?
    @ObservationIgnored private var cacheWrite: Task<Void, Never>?
    var issue: String?
    var saveStatus: String {
        get { draftState.saveStatus }
        set { if draftState.saveStatus != newValue { draftState.saveStatus = newValue } }
    }
    var noteDiskChange: MacNoteDiskChange?
    private(set) var retainedExportReady = false
    private var retainedExport: (workspace: UUID, note: NoteDocument, body: String, url: URL)?
    private var baselineIdentityUnique = false
    private var refreshID: UUID?
    private var metadataEpoch = UUID()
    var viewMode = "List" { didSet { persistNavigation() } }
    let collectionSelection = MacCollectionSelectionState()
    var selectedPaths: Set<String> {
        get { collectionSelection.paths }
        set { if collectionSelection.paths != newValue { collectionSelection.paths = newValue } }
    }
    private var collectionSelectionAnchor: String?
    var selecting: Bool {
        get { collectionSelection.selecting }
        set { if collectionSelection.selecting != newValue { collectionSelection.selecting = newValue } }
    }
    var collectionLayout = MacCollectionLayout() { didSet { persistNavigation() } }
    private var sharedViews: MacViewSnapshot?
    private var namedViews: MacSavedViewSnapshot?
    var savedViews: [MacSavedView] = []
    @ObservationIgnored private var filterWrite: Task<Void, Never>?
    private var filterWriteID: UUID?
    private var filterDraft = false
    private var viewRevision = 0
    var schema: NativeSchemaSnapshot?
    let inspectorRecovery = MacInspectorRecoveryState()
    var revisions: NativeRevisionSnapshot? {
        get { inspectorRecovery.revisions }
        set { inspectorRecovery.revisions = newValue }
    }
    var history: NativeHistorySnapshot? {
        get { inspectorRecovery.history }
        set { inspectorRecovery.history = newValue }
    }
    var revisionIssue: String? {
        get { inspectorRecovery.revisionIssue }
        set { inspectorRecovery.revisionIssue = newValue }
    }
    var historyIssue: String? {
        get { inspectorRecovery.historyIssue }
        set { inspectorRecovery.historyIssue = newValue }
    }
    var recentVaults: [String] = MacRecentVaults.stored()
    var vaultIcons: [String: String] = UserDefaults.standard.dictionary(forKey: MacRecentVaults.iconsKey) as? [String: String] ?? [:]
    private(set) var io: VaultFiles?
    @ObservationIgnored private var backlinkSources: [String: (content: String, references: [NoteReference])] = [:]
    @ObservationIgnored private var cachedBacklinks: (path: String, notes: [NoteDocument])?
    private var baseline: NoteDocument? { didSet { currentResourceCache = nil; editorSavedLink = baseline?.savedLink } }
    @ObservationIgnored private var editorSavedLink: NativeSavedLink?
    @ObservationIgnored private var currentResourceCache: [String]?
    @ObservationIgnored private var saveJob: Task<Void, Never>?
    @ObservationIgnored private var writes: Task<Bool, Never>?
    private var drafts: [String: String] = [:]
    private var generation = UUID()
    private var navigation: [MacTab] = []
    @ObservationIgnored private var navigationWrite: Task<Void, Never>?
    private var navigationState = MacNavigationState()
    private var restoringNavigation = false
    private var navigationIndex = -1
    var workspaceID: UUID { generation }
    var current: NoteDocument? { baseline }
    var canPrintCurrentNote: Bool {
        root != nil && selection != nil && current != nil && (viewMode == "List" || !browsingCollection) && (folderCollection || destination != "Tasks" && destination != "External Notes") && !busy && !preparingToClose && !editorSheetActive
    }
    func presentPrint() {
        guard canPrintCurrentNote, let note = current, let root else { return }
        printRequest = MacExportRequest(note: note, body: body, root: root)
        editorSheetActive = true
    }
    /// The attachment panel represents the saved note, not the changing draft.
    /// Recompute only when that snapshot changes, including Save and refresh.
    var currentResources: [String] {
        guard let baseline else { return [] }
        if let currentResourceCache { return currentResourceCache }
        let references = MarkdownResources.localReferences(in: baseline.parts.body)
        currentResourceCache = references
        return references
    }
    var isDirty: Bool { baseline.map { $0.parts.body != body } ?? false }
    var vaultTitle: String { root?.lastPathComponent ?? "Zerus Vault" }
    var regularNotes: [NoteDocument] { notes.filter { !$0.trashed && !$0.path.hasPrefix(".zerus/") } }
    private struct CollectionKey: Equatable {
        let revision: UInt64
        let destination: String
        let filters: NativeCollectionFilters
        let query: String
        let hideSubtypes: Bool
        let folderCollection: Bool
        let day: Date?
        let calendar: Calendar?
    }
    private var collectionRevision: UInt64 = 0
    @ObservationIgnored private var cachedCollection: (key: CollectionKey, notes: [NoteDocument])?
    @ObservationIgnored private var collectionGeneration: UInt64 = 0
    @ObservationIgnored private var cachedFolderNoteCounts: (revision: UInt64, counts: [String: Int])?
    @ObservationIgnored private var cachedCollectionFields: (key: CollectionKey, workspace: UUID, schema: Data?, fields: [NativePropertyDefinition])?
    @ObservationIgnored private var cachedGalleryGroups: (key: CollectionKey, workspace: UUID, name: String, relations: Bool, groups: [MacCollectionGroup])?
    var collection: [NoteDocument] {
        // Editing, selection and inspector updates do not change collection
        // membership. Avoid filtering/sorting the vault on every view update.
        let calendar = filters.date == .any ? nil : Calendar.current
        let key = CollectionKey(revision: collectionRevision, destination: destination, filters: filters, query: query, hideSubtypes: hideSubtypes, folderCollection: folderCollection, day: calendar?.startOfDay(for: Date()), calendar: calendar)
        if let cachedCollection, cachedCollection.key == key { return cachedCollection.notes }
        let result = MacNoteCollection.filter(notes, destination: destination, filters: filters, query: query, hideSubtypes: hideSubtypes, folderCollection: folderCollection)
        cachedCollection = (key, result)
        collectionGeneration &+= 1
        return result
    }
    /// Changes whenever the collection is recomputed, so derived caches kept
    /// in extensions can follow membership, filters and inventory together.
    var collectionIdentity: UInt64 { _ = collection; return collectionGeneration }
    var collectionFields: [NativePropertyDefinition] {
        let shown = collection
        // Reading collection always resolves its key, including date boundaries.
        let key = cachedCollection!.key, bytes = schema?.bytes
        if let cachedCollectionFields, cachedCollectionFields.key == key,
           cachedCollectionFields.workspace == workspaceID, cachedCollectionFields.schema == bytes {
            return cachedCollectionFields.fields
        }
        let owned = folderCollection ? (try? schema?.effective(notePath: destination + "/.collection.md")) ?? [] : []
        let found = MacCollectionValues.definitions(notes: shown, schema: schema)
        let fields = (owned.filter { !$0.hidden && $0.type != .unsupported } + found.filter { field in !owned.contains { $0.id == field.id } }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cachedCollectionFields = (key, workspaceID, bytes, fields)
        return fields
    }
    func galleryGroups(name: String, relations: Bool) -> [MacCollectionGroup] {
        let shown = collection
        let key = cachedCollection!.key
        if let cachedGalleryGroups, cachedGalleryGroups.key == key,
           cachedGalleryGroups.workspace == workspaceID, cachedGalleryGroups.name == name,
           cachedGalleryGroups.relations == relations {
            return cachedGalleryGroups.groups
        }
        // Selection and collapse state do not change groups. The inventory
        // revision also covers relation targets outside the shown collection.
        let groups = MacCollectionValues.galleryGroups(notes: shown, name: name, relationNotes: relations ? notes : nil)
        cachedGalleryGroups = (key, workspaceID, name, relations, groups)
        return groups
    }
    func noteCount(in folder: String) -> Int {
        if let cachedFolderNoteCounts, cachedFolderNoteCounts.revision == collectionRevision {
            return cachedFolderNoteCounts.counts[folder] ?? 0
        }
        var counts: [String: Int] = [:]
        // Count every ancestor once per inventory, preserving the sidebar's
        // prefix rule without scanning the full vault for each visible row.
        for note in notes where !note.trashed && !note.path.hasPrefix(".zerus/") {
            for index in note.path.indices where note.path[index] == "/" {
                counts[String(note.path[..<index]), default: 0] += 1
            }
        }
        cachedFolderNoteCounts = (collectionRevision, counts)
        return counts[folder] ?? 0
    }
    private var folderOrdering: MacFolderOrdering {
        if let folderOrderingCache { return folderOrderingCache }
        let value = MacFolderOrdering(folders: folders, preference: folderOrder)
        folderOrderingCache = value; return value
    }
    var orderedFolders: [String] { folderOrdering.ordered }
    var visibleFolders: [String] {
        orderedFolders.filter { folder in !collapsedFolders.contains { parent in folder.hasPrefix(parent + "/") && !keptFolders.contains(folder) } }
    }
    var folderOrderScope: MacFolderOrderScope { .init(workspace: workspaceID, folders: folders, ordered: orderedFolders) }
    func folderOrderNeighbors(_ path: String) -> (previous: String?, next: String?) { folderOrdering.neighbors[Data(path.utf8)] ?? (nil, nil) }
    @discardableResult func reorderFolder(_ transfer: MacFolderOrderTransfer, target: String, before: Bool) -> Bool {
        guard root != nil, !busy, !preparingToClose, !editorSheetActive, transfer.scope == folderOrderScope,
              !MacFolderOrdering.samePath(transfer.source, target), folders.contains(where: { MacFolderOrdering.samePath($0, transfer.source) }), folders.contains(where: { MacFolderOrdering.samePath($0, target) }),
              MacFolderOrdering.samePath(MacFolderOrdering.parent(transfer.source), MacFolderOrdering.parent(target)) else { return false }
        let source = transfer.source, original = orderedFolders
        let moving = original.filter { MacFolderOrdering.within($0, source) }
        var next = original.filter { !MacFolderOrdering.within($0, source) }
        guard let index = next.firstIndex(where: { MacFolderOrdering.samePath($0, target) }) else { return false }
        let insertion = before ? index : (next.lastIndex { MacFolderOrdering.within($0, target) } ?? index) + 1
        next.insert(contentsOf: moving, at: insertion)
        guard !next.elementsEqual(original, by: MacFolderOrdering.samePath) else { return false }
        persistFolderOrder(next); return true
    }
    @discardableResult func dropFolder(_ transfer: MacFolderOrderTransfer, target: String) -> Bool {
        guard let source = transfer.scope.ordered.firstIndex(where: { MacFolderOrdering.samePath($0, transfer.source) }), let destination = transfer.scope.ordered.firstIndex(where: { MacFolderOrdering.samePath($0, target) }) else { return false }
        return reorderFolder(transfer, target: target, before: source > destination)
    }
    private func persistFolderOrder(_ order: [String]) {
        guard let root else { return }
        let key = MacFolderOrdering.key(root)
        UserDefaults.standard.set(order, forKey: key)
        for peer in Self.windows.compactMap(\.value) where peer.root.map(MacFolderOrdering.key) == key { peer.folderOrder = order }
    }
    /// Note linking needs current draft text but no task-search metadata.
    func noteSearchSources() -> (notes: [NoteDocument], drafts: Set<String>) {
        var searchable = notes
        var changed = Set(drafts.keys)
        for index in searchable.indices {
            if let value = drafts[searchable[index].path] { searchable[index].content = searchable[index].replacingBody(value) }
            if searchable[index].path == selection, isDirty { searchable[index].content = searchable[index].replacingBody(body); changed.insert(searchable[index].path) }
        }
        return (searchable, changed)
    }
    func searchSources() -> NativeSearchSources {
        let searchable = noteSearchSources()
        let tasks = tasks.map { task in NativeSearchTaskSource(id: task.id, title: task.title, category: task.category, list: taskLists.first { $0.id == task.listID }?.name ?? generalTaskListName, priority: task.priority, scheduled: task.date, due: task.dueDate, completed: task.completed, modified: (task.raw["updatedAt"] as? String).flatMap(NativeRevisionIndex.date) ?? task.createdAt) }
        return .init(workspaceID: workspaceID, notes: searchable.notes, drafts: searchable.drafts, tasks: tasks)
    }
    func chatContextSnapshot() async throws -> MacChatContextSnapshot {
        guard let io, let root else { throw VaultFailure(message: "Open a vault before choosing context.") }
        let origin = workspaceID, fresh = try await io.scan()
        try Task.checkCancellation()
        guard origin == workspaceID else { throw CancellationError() }
        // Use the editor's original baseline, even if a refresh found a new
        // note at that path. An old local draft never belongs to its replacement.
        let kept = baseline.flatMap { note in isDirty ? MacChatContextSnapshot.Draft(baseline: note, content: note.replacingBody(body)) : nil }
        return .init(workspaceID: origin, root: root, notes: fresh.notes, drafts: kept.map { [$0] } ?? [])
    }
    /// iCloud can evict `.zerus/*.json` (properties, views, type icons…) to
    /// dataless placeholders. Every scan reads some of them, and a coordinated
    /// read of a placeholder blocks until it downloads. Ask iCloud to fetch
    /// them as soon as the vault opens so later reads do not stall.
    nonisolated static func requestLocalVaultMetadata(_ root: URL) {
        let folder = root.appendingPathComponent(".zerus", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for file in files where file.pathExtension == "json" {
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_flags & 0x4000_0000 != 0 /* SF_DATALESS */ else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
    }
    func openSearchNote(path: String, stableID: String?, workspaceID: UUID) async throws {
        guard workspaceID == self.workspaceID, let io else { throw VaultFailure(message: "The vault changed. Refresh search.") }
        let fresh = try await io.scan()
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        let matches = fresh.notes.filter { !$0.trashed && (stableID == nil ? $0.path == path : $0.stableID == stableID) }
        guard matches.count == 1, let note = matches.first else { throw VaultFailure(message: "This result changed. Refresh search before opening it.") }
        apply(fresh); await openNote(note.path, awaitInspector: false)
        guard selection == note.path else { throw VaultFailure(message: issue ?? "Save the current note before opening this result.") }
    }
    func openSearchConversation(_ conversation: NativeSearchConversation, workspaceID: UUID) async throws -> MacChatController {
        guard workspaceID == self.workspaceID, let root, let io, case .shared(let id) = conversation.origin else { throw VaultFailure(message: "The conversation or vault changed. Refresh search.") }
        let fresh = try await io.conversationSnapshot(id)
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        guard fresh.conversation.deletedAt == nil else { throw VaultFailure(message: "This conversation moved to Trash. Restore it from AI chat before opening it here.") }
        let chat = MacChatController.shared(root: root)
        try await chat.select(id)
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        guard chat.conversation?.deletedAt == nil else { throw VaultFailure(message: "This conversation moved to Trash. Restore it from AI chat before opening it here.") }
        return chat
    }
    func searchFile(_ path: String, workspaceID: UUID) async throws -> NativeFileLease {
        guard workspaceID == self.workspaceID, files.contains(path), let mappings = fileMappings else { throw VaultFailure(message: "This file or vault changed. Refresh search.") }
        let lease = try await mappings.resolve(.init(id: "search:" + path, name: (path as NSString).lastPathComponent, kind: .vault, path: path))
        guard workspaceID == self.workspaceID else { throw CancellationError() }
        return lease
    }
    var backlinks: [NoteDocument] {
        guard let note = current else { return [] }
        // Inspector layout and accessibility can request the same result again.
        // Only the inventory and selected path affect this calculation; every
        // inventory write invalidates this single retained result.
        if let cachedBacklinks, cachedBacklinks.path == note.path { return cachedBacklinks.notes }
        let paths = Set(notes.map(\.path))
        backlinkSources = backlinkSources.filter { paths.contains($0.key) }
        // Use the inventory's current metadata, which can differ from a retained
        // editor baseline after an outside edit. A reference that cannot select
        // this path from that subset cannot select it from the complete vault.
        let targetNotes = notes.filter { !$0.trashed && $0.path == note.path }
        guard !targetNotes.isEmpty else { return [] }
        var resolved: [String: Bool] = [:]
        let linkSyntax = CharacterSet(charactersIn: "[<:")
        let result = notes.filter { other in
            guard !other.trashed, other.path != note.path else { return false }
            let references: [NoteReference]
            if let cached = backlinkSources[other.path], cached.content == other.content { references = cached.references }
            else {
                let body = other.parts.body
                // Wiki/Markdown links need an opening bracket, autolinks need
                // an angle bracket, and bare URL schemes need a colon. Plain
                // prose without any of these cannot contain a note reference.
                references = body.rangeOfCharacter(from: linkSyntax) == nil ? [] : NoteReference.references(in: body)
                backlinkSources[other.path] = (other.content, references)
            }
            return references.contains { reference in
                if let matched = resolved[reference.target] { return matched }
                guard !reference.targets(in: targetNotes, includeHeadingFragments: true).isEmpty else {
                    resolved[reference.target] = false; return false
                }
                // Keep complete-vault resolution for possible matches: a title
                // may be ambiguous or shadowed by another note's exact path.
                let candidates = reference.targets(in: notes, includeHeadingFragments: true)
                let matched = candidates.count == 1 && candidates.first?.path == note.path
                resolved[reference.target] = matched; return matched
            }
        }
        cachedBacklinks = (note.path, result)
        return result
    }
    func revealHeading(_ fragment: String) {
        guard let selection else { return }
        guard fragment.isEmpty || MacHeadings.target(fragment, in: body) != nil else {
            issue = "This heading is no longer in the note. Choose a current heading in Outline."; return
        }
        headingRequest = .init(fragment: fragment, path: selection)
    }
    private func openLinkedNote(_ note: NoteDocument, heading: String?) async {
        let origin = workspaceID
        await openNote(note.path)
        guard origin == workspaceID, selection == note.path else { return }
        if let heading { revealHeading(heading) }
    }
    func saveFocusedDocument() async {
        if let session = external.selected { await session.save() } else { _ = await save() }
    }
    func prepareToQuit() async -> Bool { await prepareToCloseWindow() }
    func prepareToCloseWindow() async -> Bool {
        guard !agentSettingsActive else { issue = "Save or discard the unsaved AI settings before closing this window or quitting."; return false }
        guard !preparingToClose, !busy, !editorSheetActive, !imageSaving, !recoverySaving, !noteMovesSaving, !paneLayoutSaving, !externalCopySaving, !schemaMaintenanceSaving, !tasksSaving else { issue = "Finish the current change before closing this window."; return false }
        let origin = workspaceID
        var allowed = false
        preparingToClose = true
        defer { preparingToClose = false; if !allowed { agentController?.cancelLeaving() } }
        if let agentController, !(await agentController.prepareToLeave()) { issue = agentController.issue; return false }
        saveJob?.cancel()
        await filterWrite?.value; await taskPipeline?.value
        if let writes, !(await writes.value) { return false }
        if !retainedExportIsCurrent() {
            await refresh()
            // An inventory error must not hide a changed/unreadable selected file.
            if let original = baseline, noteDiskChange == nil, let io {
                do {
                    let bytes = try await io.read(original.path)
                    guard origin == workspaceID, baseline?.content == original.content, baseline?.path == original.path else { return false }
                    if bytes != Data(original.content.utf8) { noteDiskChange = .modified; persistDraft(); saveStatus = "Outside change — text retained" }
                } catch {
                    guard origin == workspaceID else { return false }
                    noteDiskChange = .unavailable; persistDraft(); saveStatus = "Original unavailable — text retained"
                }
            }
        }
        guard origin == workspaceID else { return false }
        if noteDiskChange != nil {
            guard retainedExportIsCurrent() else {
                if retainedExportReady { retainedExportReady = false; issue = "The exported copy changed or is unavailable. Export the retained text again before closing." }
                return false
            }
        } else { guard await save(), !isDirty else { return false } }
        guard await external.selected?.checkpoint() ?? true else { issue = external.selected?.failure ?? "The external draft could not be kept. Export it before closing."; return false }
        if let root {
            let otherWindow = Self.windows.contains { $0.value !== self && $0.value?.root?.resolvingSymlinksInPath().standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL }
            if !otherWindow, let chat = MacChatController.existing(root: root), !(await chat.prepareToLeave()) { issue = chat.issue; return false }
        }
        await MacNoteRecoveryStore.waitForCheckpoints()
        allowed = origin == workspaceID && (noteDiskChange == nil ? !isDirty : retainedExportIsCurrent())
        if allowed { persistNavigation(); cancelStartupRefresh(); await cacheWrite?.value }
        return allowed
    }
    private func retainedExportIsCurrent() -> Bool {
        guard let kept = retainedExport, retainedExportReady, kept.workspace == workspaceID, baseline == kept.note, body == kept.body else { return false }
        return (try? Data(contentsOf: kept.url)) == Data(kept.note.replacingBody(kept.body).utf8)
    }
    func exportNoteRecovery(_ record: MacNoteRecoveryRecord, to url: URL, workspaceID expected: UUID) throws {
        guard expected == workspaceID, let root else { throw VaultFailure(message: "The vault changed. Reopen recovery before exporting.") }
        try MacNoteRecoveryStore.export(record, root: root, to: url)
        if noteDiskChange != nil, let note = baseline, note.path == record.note.path, note.content == record.note.content, body == record.body {
            retainedExport = (workspaceID, note, body, url); retainedExportReady = true
        }
    }
    func chooseVault() {
        guard !busy, !preparingToClose else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Open Vault"; panel.message = "Choose your Markdown vault. Your existing files and metadata stay in place."
        if panel.runModal() == .OK, let url = panel.url { Task { await openVault(url) } }
    }
    func openVault(_ url: URL) async {
        guard !agentSettingsActive else { issue = "Save or discard the unsaved AI settings before switching vaults."; return }
        guard !busy, !preparingToClose, !editorSheetActive, !imageSaving, !noteMovesSaving, !paneLayoutSaving, !externalCopySaving, !schemaMaintenanceSaving, !recoverySaving else { issue = "Finish the current change before switching vaults."; return }
        let previousController = agentController, previousWorkspace = workspaceID
        busy = true
        cancelStartupRefresh()
        defer { busy = false; if workspaceID == previousWorkspace { previousController?.cancelLeaving() } }
        if let agentController, !(await agentController.prepareToLeave()) { issue = agentController.issue; return }
        if let root, let chat = MacChatController.existing(root: root), !(await chat.prepareToLeave()) { issue = chat.issue; return }
        guard await save() else { return }
        await filterWrite?.value
        await taskPipeline?.value
        guard !paneLayoutSaving else { issue = "Finish the properties pane change before switching vaults."; return }
        // An already accepted asynchronous edit may arrive while the earlier writes finish.
        guard await save() else { return }
        guard !isDirty else { issue = "Writing arrived while saving. Your draft is retained; open the vault again when ready."; return }
        let editingRevision = noteEditRevision
        do {
            let worker = VaultFiles(root: url)
            Task.detached(priority: .utility) { Self.requestLocalVaultMetadata(url) }
            let recoveredFolderRename = try await worker.macPrepareStartup()
            let identity = try? await Task.detached { try MacStartupIdentity.read(url) }.value
            // A completed save in another live window may still have its
            // disposable snapshot queued. Finish those writes before loading it.
            for peer in Self.windows.compactMap(\.value) where peer.root?.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL {
                if peer.navigationWrite != nil { peer.persistNavigation() }
                await peer.cacheWrite?.value
            }
            let cached: MacStartupSnapshot?
            if let identity, !recoveredFolderRename { cached = await MacStartupCache.shared.load(identity) } else { cached = nil }
            let snapshot: VaultSnapshot
            if let cached { snapshot = cached.snapshot } else { snapshot = try await worker.scan() }
            guard editingRevision == noteEditRevision else { issue = "Writing arrived while opening the vault. Your draft is retained; open the vault again when ready."; return }
            persistNavigation(); restoringNavigation = true
            openingAdmissions.removeAll()
            generation = UUID(); agentController = nil; paneRevision += 1; paneLayoutSaving = false; paneLayout = .init(); paneLayoutReady = false; paneLayoutIssue = nil; refreshID = nil; noteDiskChange = nil; retainedExport = nil; retainedExportReady = false; baselineIdentityUnique = false; backlinkSources = [:]; editorFocusRequest = nil; headingRequest = nil; missingNoteLink = nil; imageUndo = nil; taskPipeline = nil; pendingTaskChanges = 0; tasksSaving = false; taskRevision += 1; sharedViews = nil; namedViews = nil; savedViews = []; filterWrite = nil; filterWriteID = nil; filterDraft = false; io = worker; fileMappings = NativeFileMappings(root: url); fileMappingRevision = 0; root = url; baseline = nil; selection = nil; body = ""; tabs = []; activeTab = nil; drafts = [:]; adoptedDrafts = [:]
            startupIdentity = identity; usingStartupCache = cached != nil; startupIssue = nil; startupSaved = [:]; startupSaveRevision = 0
            schema = nil; tasks = []; taskLists = []; taskCategories = []; startupTaskData = nil
            if let cached {
                schema = NativeSchemaSnapshot(root: url, bytes: cached.schema)
                if let bytes = cached.views, let object = try? NativeJSON.object(with: bytes) as? [String: Any] { sharedViews = .init(bytes: bytes, object: object) }
                if let data = try? NativeTaskData(cached.tasks) { applyTaskData(data) }
            }
            taskDraftStore = nil; taskDraftIssue = nil
            do { taskDraftStore = try NativeTaskDraftStore(vaultRoot: url, vaultID: identity?.taskDraftID) }
            catch { taskDraftIssue = error.localizedDescription }
            apply(snapshot, cache: cached == nil); destination = "All Notes"; folderCollection = false; query = ""; navigation = []; navigationIndex = -1
            if !MacRecentVaults.isTemporary(url.path) {
                recentVaults.removeAll { $0 == url.path }; recentVaults.insert(url.path, at: 0); recentVaults = Array(recentVaults.prefix(12))
                UserDefaults.standard.set(recentVaults, forKey: MacRecentVaults.recentsKey)
            }
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "zerus.mac.bookmark." + NativeHistory.hash(url.path)) }
            folderOrder = UserDefaults.standard.stringArray(forKey: MacFolderOrdering.key(url)) ?? []
            let key = MacNavigationState.key(url)
            let savedNavigation: Data?
            if let current = UserDefaults.standard.data(forKey: key) { savedNavigation = current }
            else { savedNavigation = try MacNavigationArchive.data(forKey: key) }
            navigationState = savedNavigation.flatMap { try? JSONDecoder().decode(MacNavigationState.self, from: $0) } ?? .init()
            if cached == nil { navigationState = navigationState.validated(notes: notes, folders: folders) }
            tabs = navigationState.tabs; pinnedTabs = (navigationState.pinnedTabs ?? []).intersection(Set(tabs)); restoreCollection(navigationState.currentCollection, folder: navigationState.currentCollectionIsFolder); inspector = navigationState.inspector; keptFolders = navigationState.keptFolders; collapsedFolders = navigationState.collapsedFolders
            let restoredActive = navigationState.active
            if cached != nil {
                restoringNavigation = false
                restoreCachedNavigation(restoredActive)
                beginStartupRefresh()
                return
            }
            await refreshMetadata()
            restoringNavigation = false
            if let tab = restoredActive {
                if case .note(let path) = tab, (folderCollection ? folders.contains(destination) : MacNavigationState.globalViews.contains(destination)) {
                    await openNote(path, preserveCollection: true)
                } else { await activateTab(tab) }
            }
            else if let first = collection.first { await openNote(first.path) }
            else { await openCollection("All Notes") }
            persistNavigation()
        } catch { restoringNavigation = false; issue = error.localizedDescription }
    }
    func restore() async {
        guard root == nil else { return }
        if let path = ProcessInfo.processInfo.environment["ZERUS_MAC_VAULT"] { await openVault(URL(fileURLWithPath: path)); return }
        if let path = recentVaults.first { await openRecentVault(path) }
    }
    func apply(_ snapshot: VaultSnapshot, cache: Bool = true) {
        snapshotRevision += 1
        adoptFolderIcons(snapshot)
        // String equality is Unicode-canonical; inventory identity must retain
        // exact spellings even when a provider preserves modification dates.
        let sameNotes = notes.elementsEqual(snapshot.notes) { left, right in
            left == right && left.path.utf8.elementsEqual(right.path.utf8) && left.content.utf8.elementsEqual(right.content.utf8)
        }
        if !sameNotes {
            if !restoringNavigation { remapRefreshedNavigation(snapshot.notes) }
            notes = snapshot.notes
        }
        if !folders.elementsEqual(snapshot.folders, by: { $0.utf8.elementsEqual($1.utf8) }) { folders = snapshot.folders }
        if !files.elementsEqual(snapshot.files, by: { $0.utf8.elementsEqual($1.utf8) }) { files = snapshot.files }
        if collectionFileDates != snapshot.fileDates { collectionFileDates = snapshot.fileDates }
        if cache {
            if startupRefreshing { startupSaved = [:]; startupSaveRevision += 1 }
            cacheCurrentSnapshot()
        }
    }
    private func cacheCurrentSnapshot() {
        guard let identity = startupIdentity else { return }
        let value = MacStartupSnapshot(snapshot: .init(notes: notes, files: files, fileDates: collectionFileDates, folders: folders, folderIssue: folderIconIssue, macFolderIconBytes: folderIconBytes), schema: schema?.bytes, views: sharedViews?.bytes, tasks: startupTaskData)
        let previous = cacheWrite, requested = DispatchTime.now().uptimeNanoseconds
        cacheWrite = Task { await previous?.value; await MacStartupCache.shared.store(value, identity: identity, requested: requested) }
    }
    private func cancelStartupRefresh() {
        startupRequest = nil; startupTask?.cancel(); startupTask = nil; startupRefreshing = false
    }
    private func restoreCachedNavigation(_ tab: MacTab?) {
        if let tab {
            activeTab = tab
            switch tab {
            case .note(let path):
                if let note = notes.first(where: { $0.path == path }) { adoptOpenedNote(note, record: true) }
                else { browsingCollection = true }
            case .folder(let path): restoreCollection(path, folder: true); browsingCollection = true
            case .collection(let name): restoreCollection(name); browsingCollection = true
            }
        } else if let note = collection.first { adoptOpenedNote(note, record: true) }
        else { activeTab = .collection("All Notes"); browsingCollection = true }
        persistNavigation()
    }
    private func beginStartupRefresh() {
        guard startupTask == nil, let root, let io else { return }
        let origin = generation, request = UUID(), scanner = VaultFiles(root: root), initialEditRevision = noteEditRevision
        startupRequest = request; startupRefreshing = true; startupIssue = nil; startupSaved = [:]; startupSaveRevision = 0
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == origin, self.startupRequest == request { self.startupTask = nil; self.startupRequest = nil; self.startupRefreshing = false; self.startupSaved = [:] }
            }
            do {
                while !Task.isCancelled {
                    while self.busy || self.boardSaving || self.noteMovesSaving || self.schemaMaintenanceSaving || self.recoverySaving || self.imageSaving {
                        try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(30))
                    }
                    let revision = self.snapshotRevision
                    var fresh = try await scanner.scan()
                    while self.busy || self.boardSaving || self.noteMovesSaving || self.schemaMaintenanceSaving || self.recoverySaving || self.imageSaving {
                        try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(30))
                    }
                    guard origin == self.generation, self.startupRequest == request else { return }
                    if revision != self.snapshotRevision { continue }
                    // A scan may have read a note before the user's startup save.
                    // Re-read every saved path, including notes left since then.
                    while true {
                        _ = await self.writes?.value
                        let savedVersion = self.startupSaveRevision
                        for path in self.startupSaved.keys.sorted() {
                            let saved = try await io.macReadStartupNote(path)
                            fresh.notes.removeAll { $0.path == path }; fresh.notes.append(saved)
                        }
                        if savedVersion == self.startupSaveRevision { break }
                    }
                    try Task.checkCancellation()
                    guard origin == self.generation, self.startupRequest == request else { return }
                    if revision != self.snapshotRevision { continue }
                    let untouched = !self.isDirty && self.noteEditRevision == initialEditRevision
                    let original = self.baseline
                    self.apply(fresh, cache: false)
                    if untouched, let original {
                        let saved = self.notes.first { $0.path == original.path } ?? self.savedIdentity(in: self.notes, original: original)
                        if let saved { self.adoptOpenedNote(saved, record: false) }
                        else {
                            self.tabs.removeAll { $0 == .note(original.path) }
                            self.baseline = nil; self.selection = nil; self.body = ""; self.noteDiskChange = nil; self.browsingCollection = true
                            self.activeTab = self.tabs.last ?? .collection("All Notes")
                        }
                    } else if !self.isDirty, let original, self.noteEditRevision != initialEditRevision,
                              self.notes.first(where: { $0.path == original.path })?.content != original.content {
                        // Marked text is deliberately absent from the bound body.
                        // An input intent still owns its old byte baseline.
                        self.noteDiskChange = .modified; self.saveStatus = "Outside change — text retained"
                    } else { _ = self.reconcileRefreshedNote() }
                    self.usingStartupCache = false; self.startupIssue = nil
                    self.cacheCurrentSnapshot()
                    if self.selection == nil, case .note(let path) = self.activeTab, self.notes.contains(where: { $0.path == path }) { await self.openNote(path, preserveCollection: true) }
                    else { await self.loadInspector() }
                    await self.refreshMetadata()
                    return
                }
            } catch {
                if !Task.isCancelled, origin == self.generation, self.startupRequest == request { self.startupIssue = "Could not refresh the vault. The cached copy and your drafts are kept. " + error.localizedDescription }
            }
        }
    }
    func refreshMetadata() async {
        guard let io else { return }
        let origin = generation, revision = viewRevision, tasksVersion = taskRevision, epoch = metadataEpoch
        do {
            let data = try await io.taskData(), definitions = try await io.schemaSnapshot()
            guard origin == generation, epoch == metadataEpoch else { return }
            if tasksVersion == taskRevision && !tasksSaving { applyTaskData(data) }
            if schema.map({ $0.root != definitions.root || $0.bytes != definitions.bytes || $0.workspaceID != definitions.workspaceID }) ?? true {
                schema = definitions
            }
            let views = try await io.macViewSnapshot(), named = try await io.macSavedViewSnapshot()
            guard origin == generation, epoch == metadataEpoch else { return }
            if revision == viewRevision {
                // A read-only poll must not republish the same settings or
                // rewrite navigation preferences. Raw bytes retain foreign
                // fields and exact Unicode spellings when a client changes them.
                if namedViews.map({ $0.bytes != named.bytes }) ?? true {
                    namedViews = named; savedViews = folderCollection ? named.entries(destination) : []
                }
                if filterWriteID == nil, sharedViews.map({ $0.bytes != views.bytes }) ?? true {
                    sharedViews = views; adoptSharedView(views, owner: destination)
                }
            }

        } catch { if origin == generation, epoch == metadataEpoch { issue = error.localizedDescription } }
        if origin == generation { await refreshPaneLayout(); cacheCurrentSnapshot() }
    }
    func adoptCLISetupSnapshot(_ snapshot: VaultSnapshot, changes: [VaultFileChange]) async {
        if let original = baseline, !isDirty, noteDiskChange == nil,
           let change = changes.first(where: { $0.path == original.path && $0.before == Data(original.content.utf8) }),
           let saved = snapshot.notes.first(where: { $0.path == original.path && Data($0.content.utf8) == change.after }) {
            removeDraft(original); baseline = saved; body = saved.parts.body
            baselineIdentityUnique = saved.stableID.map { id in snapshot.notes.filter { !$0.trashed && $0.stableID == id }.count == 1 } ?? false
        }
        await adoptSchemaMaintenanceSnapshot(snapshot)
    }
    func adoptSchemaMaintenanceSnapshot(_ snapshot: VaultSnapshot) async {
        refreshID = nil; metadataEpoch = UUID()
        apply(snapshot); _ = reconcileRefreshedNote()
        await loadInspector(); await refreshMetadata()
    }
    func adoptAgentReview(_ review: NativeAgentReview, snapshot: VaultSnapshot) async {
        let mappings = MacAgentOrganizationReconciliation.mappings(review)
        remapMovedNotePaths(mappings)
        // Owned Trash/restore and legacy identity upgrades must not look like
        // outside deletion/replacement. Late writing still uses the normal
        // retained-draft reconciliation path.
        if let original = baseline, !isDirty, noteDiskChange == nil,
           review.changedNotes.contains(where: { $0.path == original.path && $0.before == Data(original.content.utf8) }) {
            let target = mappings[original.path] ?? original.path
            if let bytes = review.changes.first(where: { $0.path == target })?.after,
               let saved = snapshot.notes.first(where: { $0.path == target && Data($0.content.utf8) == bytes }) {
                removeDraft(original)
                if saved.trashed {
                    tabs.removeAll { $0 == .note(original.path) || $0 == .note(saved.path) }
                    if activeTab == .note(original.path) || activeTab == .note(saved.path) { activeTab = nil }
                    selection = nil; baseline = nil; body = ""; sourceMode = false; baselineIdentityUnique = false
                } else {
                    baseline = saved; selection = saved.path; body = saved.parts.body
                    baselineIdentityUnique = saved.stableID.map { id in snapshot.notes.filter { $0.stableID == id }.count == 1 } ?? false
                    sourceMode = MacMarkdown.requiresSource(body)
                }
                saveStatus = "Saved"
            }
        }
        await adoptSchemaMaintenanceSnapshot(snapshot)
        await reconcileNavigation()
    }
    func refresh() async {
        if let startupTask {
            await startupTask.value
            if usingStartupCache { return }
        }
        if usingStartupCache {
            if !preparingToClose { beginStartupRefresh(); await startupTask?.value }
            return
        }
        guard let io, !busy, !schemaMaintenanceSaving, !noteMovesSaving, !imageSaving, !recoverySaving, !boardSaving, refreshID == nil else { return }
        let origin = generation, request = UUID(); refreshID = request
        defer { if refreshID == request { refreshID = nil } }
        do {
            let snapshot = try await io.scan()
            guard origin == generation, refreshID == request, !schemaMaintenanceSaving, !noteMovesSaving, !boardSaving else { return }
            apply(snapshot)
            if writes == nil, reconcileRefreshedNote() { await loadInspector() }
            await refreshMetadata()
        } catch { if origin == generation, refreshID == request { issue = error.localizedDescription } }
    }
    private func refreshedNote(in values: [NoteDocument], original: NoteDocument) -> NoteDocument? {
        let samePath = values.first { $0.path == original.path }
        let sameIdentity = samePath.map { original.stableID == nil || $0.stableID == original.stableID } ?? false
        return sameIdentity ? samePath : savedIdentity(in: values, original: original)
    }
    private func remapRefreshedNavigation(_ updated: [NoteDocument]) {
        let paths = Set((tabs + navigation).compactMap(\.notePath))
        let candidates = notes.compactMap { note -> (path: String, id: String)? in
            guard paths.contains(note.path), note.path != selection, !note.trashed,
                  drafts[note.path] == nil, adoptedDrafts[note.path]?.isEmpty != false,
                  let id = note.stableID else { return nil }
            return (note.path, id)
        }
        guard !candidates.isEmpty else { return }
        let ids = Set(candidates.map(\.id))
        var before: [String: Int] = [:], after: [String: [NoteDocument]] = [:]
        for note in notes where !note.trashed {
            if let id = note.stableID, ids.contains(id) { before[id, default: 0] += 1 }
        }
        for note in updated where !note.trashed {
            if let id = note.stableID, ids.contains(id) { after[id, default: []].append(note) }
        }
        var protected = Set(drafts.keys).union(adoptedDrafts.filter { !$0.value.isEmpty }.map(\.key))
        var selectedMove: [String: String] = [:]
        if let original = baseline {
            protected.insert(original.path)
            // Startup input intent has separate reconciliation below. Never
            // release a live or retained draft merely to repair another tab.
            if !usingStartupCache, writes == nil, !isDirty,
               let saved = refreshedNote(in: updated, original: original),
               noteDiskChange == nil || saved.content == original.content {
                protected.remove(original.path)
                if saved.path != original.path { selectedMove[original.path] = saved.path }
            }
        }
        var mapping: [String: String] = [:]
        for candidate in candidates {
            guard before[candidate.id] == 1, let matches = after[candidate.id], matches.count == 1,
                  let target = matches.first, target.path != candidate.path, !protected.contains(target.path) else { continue }
            mapping[candidate.path] = target.path
        }
        guard !mapping.isEmpty else { return }
        // Include a clean selected move in the same substitution, so swaps do
        // not sequentially remap one tab onto another note's new path.
        mapping.merge(selectedMove) { _, selected in selected }
        remapMovedNotePaths(mapping)
        persistNavigation()
    }
    private func savedIdentity(in notes: [NoteDocument], original: NoteDocument) -> NoteDocument? {
        guard !original.trashed, baselineIdentityUnique, let id = original.stableID else { return nil }
        let matches = notes.filter { !$0.trashed && $0.stableID == id }
        return matches.count == 1 ? matches.first : nil
    }
    private func reconcileRefreshedNote() -> Bool {
        guard let original = baseline else { return false }
        let saved = refreshedNote(in: notes, original: original)
        if let saved, !isDirty, noteDiskChange == nil || saved.content == original.content {
            if noteDiskChange != nil { removeDraft(original) }
            let changed = saved.path != original.path || saved.content != original.content
            if saved.path != original.path, selection == original.path { remapMovedNotePaths([original.path: saved.path]); persistNavigation() }
            // Keep the saved snapshot (and its attachment cache) when a poll
            // finds no change. Exact UTF-8 checks supplement String's canonical
            // equality so a provider's Unicode spelling is still adopted.
            // A modification date alone (the refresh after this window's own
            // save) is not a change: replacing the baseline would rebuild the
            // editor and discard its undo history.
            if !saved.path.utf8.elementsEqual(original.path.utf8) || !saved.content.utf8.elementsEqual(original.content.utf8) || saved.stableID != original.stableID { baseline = saved }
            let savedBody = saved.parts.body
            if !body.utf8.elementsEqual(savedBody.utf8) { body = savedBody }
            if changed { sourceMode = MacMarkdown.requiresSource(body) }
            if noteDiskChange != nil { noteDiskChange = nil }
            if retainedExportReady { retainedExportReady = false }
            retainedExport = nil
            if saveStatus != "Saved" { saveStatus = "Saved" }
            return changed
        }
        let samePath = notes.first { $0.path == original.path }
        let change: MacNoteDiskChange?
        if let saved {
            change = saved.path != original.path ? .moved(saved.path) : saved.content != original.content ? .modified : nil
        } else { change = samePath == nil ? .missing : .replaced }
        if change != noteDiskChange { retainedExportReady = false; retainedExport = nil; if change != nil { persistDraft() } }
        if noteDiskChange != change { noteDiskChange = change }
        if change != nil {
            saveJob?.cancel()
            if saveStatus != "Outside change — text retained" { saveStatus = "Outside change — text retained" }
        } else if isDirty, saveStatus != "Unsaved changes" { saveStatus = "Unsaved changes" }
        return false
    }
    func exportRetainedNote(to url: URL) throws {
        guard noteDiskChange != nil, let note = baseline else { throw VaultFailure(message: "There is no retained note to export.") }
        let data = Data(note.replacingBody(body).utf8)
        // Never let a recovery export overwrite any file inside the open vault.
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        if let root {
            guard !destination.pathComponents.starts(with: root.standardizedFileURL.resolvingSymlinksInPath().pathComponents) else { throw VaultFailure(message: "Export the retained text outside this vault so its saved files stay unchanged.") }
        }
        guard !destination.pathComponents.starts(with: MacNoteRecoveryStore.directory.resolvingSymlinksInPath().pathComponents) else { throw VaultFailure(message: "Export outside the private drafts folder so recovery files stay unchanged.") }
        try data.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == data else { throw VaultFailure(message: "The exported copy could not be verified. Your text is still kept here.") }
        retainedExport = (generation, note, body, url); retainedExportReady = true
    }
    func useSavedNoteAfterExport() async throws {
        guard let io, let kept = retainedExport, kept.workspace == generation, baseline == kept.note, body == kept.body, retainedExportReady else { throw VaultFailure(message: "Export the current retained text before using the saved version.") }
        let snapshot = try await io.scan()
        guard kept.workspace == generation, baseline == kept.note, body == kept.body,
              try Data(contentsOf: kept.url) == Data(kept.note.replacingBody(kept.body).utf8) else { throw VaultFailure(message: "The note or exported copy changed. Export your retained text again.") }
        let saved = savedIdentity(in: snapshot.notes, original: kept.note) ?? snapshot.notes.first { $0.path == kept.note.path }
        saveJob?.cancel(); drafts.removeValue(forKey: kept.note.path); removeDraft(kept.note)
        baseline = nil; selection = nil; body = ""; noteDiskChange = nil; retainedExport = nil; retainedExportReady = false
        apply(snapshot)
        if let saved {
            if saved.path != kept.note.path { remapMovedNotePaths([kept.note.path: saved.path]) }
            await openNote(saved.path)
        } else {
            tabs.removeAll { $0 == .note(kept.note.path) }; navigation.removeAll { $0 == .note(kept.note.path) }; navigationIndex = min(navigationIndex, navigation.count - 1)
            await openCollection(destination, folder: folderCollection)
        }
        persistNavigation()
    }
    func openRecentVault(_ path: String) async {
        let key = "zerus.mac.bookmark." + NativeHistory.hash(path)
        do {
            if let data = UserDefaults.standard.data(forKey: key) {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                await openVault(url)
            } else { await openVault(URL(fileURLWithPath: path)) }
        } catch { issue = "Reconnect this vault with Open Vault: " + error.localizedDescription }
    }
    func vaultSettingsDestination() throws -> String {
        guard let root, !busy, !preparingToClose, !agentWritingHeld else { throw VaultFailure(message: "Open an available vault before importing vault preferences.") }
        return root.lastPathComponent
    }
    func vaultSettingsStamp() throws -> Data {
        _ = try vaultSettingsDestination()
        guard let root else { throw VaultFailure(message: "The destination vault is unavailable.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let values: [String: Any] = [
            "workspace": workspaceID.uuidString, "folders": folders,
            "navigation": try encoder.encode(navigationState).base64EncodedString(),
            "savedNavigation": UserDefaults.standard.data(forKey: MacNavigationState.key(root))?.base64EncodedString() ?? "",
            "defaultFolder": UserDefaults.standard.object(forKey: MacNewNotePreferences.key(root)) ?? NSNull(),
            "order": UserDefaults.standard.object(forKey: MacFolderOrdering.key(root)) ?? NSNull()
        ]
        return try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
    }
    func applyImportedVaultPreferences(_ source: MacDesktopSettingsSnapshot.Vault) {
        guard let root else { return }
        UserDefaults.standard.set(source.defaultNoteFolder, forKey: MacNewNotePreferences.key(root))
        let order = source.folderOrder.filter { path in folders.contains { MacFolderOrdering.samePath($0, path) } }
        persistFolderOrder(order)
        for peer in Self.windows.compactMap(\.value) where peer.root.map(MacFolderOrdering.key) == MacFolderOrdering.key(root) {
            let previous = peer.restoringNavigation; peer.restoringNavigation = true
            peer.navigationState.importedHideSubtypes = source.hideSubtypeNotes
            for key in peer.navigationState.collections.keys where key.hasPrefix("folder:") {
                peer.navigationState.collections[key]?.hideSubtypes = source.hideSubtypeNotes
            }
            peer.keptFolders = Set(source.keptOpenFolders.filter { path in peer.folders.contains { MacFolderOrdering.samePath($0, path) } })
            peer.collapsedFolders = peer.collapsedFolders.filter { parent in !peer.keptFolders.contains { MacFolderOrdering.within($0, parent) } }
            if peer.folderCollection { peer.hideSubtypes = source.hideSubtypeNotes }
            peer.restoringNavigation = previous; peer.persistNavigation(); peer.preferenceRevision &+= 1
        }
    }
    func persistNavigation(deferWrite: Bool = false) {
        guard !restoringNavigation, let root else { return }
        navigationWrite?.cancel(); navigationWrite = nil
        let key = MacNavigationState.key(root)
        // Preferences are shared across windows. A later navigation action wins;
        // an older window must not publish its delayed snapshot afterward.
        for peer in Self.windows.compactMap(\.value) where peer !== self && peer.navigationWrite != nil {
            guard let otherRoot = peer.root, MacNavigationState.key(otherRoot) == key else { continue }
            peer.navigationWrite?.cancel(); peer.navigationWrite = nil
        }
        navigationState.tabs = tabs; navigationState.active = activeTab; navigationState.inspector = inspector; navigationState.currentCollection = destination; navigationState.currentCollectionIsFolder = folderCollection
        navigationState.keptFolders = keptFolders; navigationState.collapsedFolders = collapsedFolders
        navigationState.pinnedTabs = pinnedTabs.isEmpty ? nil : pinnedTabs
        navigationState.collections[collectionKey] = .init(query: query, mode: viewMode, filters: filters, hideSubtypes: hideSubtypes, layout: collectionLayout)
        // Search membership stays immediate; only device-local preferences wait
        // for a typing pause. Any navigation or close flushes the latest state.
        if deferWrite {
            navigationWrite = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.navigationWrite = nil
                self.persistNavigation()
            }
            return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(navigationState), UserDefaults.standard.data(forKey: key) != data {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private var collectionKey: String { (folderCollection ? "folder:" : "view:") + destination }
    private func restoreCollection(_ value: String, folder: Bool = false) {
        let current = restoringNavigation; restoringNavigation = true
        let stored = navigationState.collections[(folder ? "folder:" : "view:") + value]
        let state = stored ?? .init(hideSubtypes: folder ? navigationState.importedHideSubtypes ?? false : false)
        collectionLayout = (folder ? sharedViews?.layout(value) : nil) ?? state.layout ?? .init()
        destination = value; folderCollection = folder; query = state.query; filters = (folder ? sharedViews?.filters(value) : nil) ?? stored?.filters ?? (folder ? .init(sort: .createdDescending) : state.filters); viewMode = (folder ? sharedViews?.mode(value) : nil) ?? state.mode; hideSubtypes = state.hideSubtypes
        clearCollectionSelection(); filterDraft = false; savedViews = folder ? namedViews?.entries(value) ?? [] : []; restoringNavigation = current
    }
    private func adoptSharedView(_ snapshot: MacViewSnapshot, owner: String) {
        guard folderCollection, destination == owner else { return }
        let previous = restoringNavigation; restoringNavigation = true
        if let layout = snapshot.layout(owner) { collectionLayout = layout }
        if let mode = snapshot.mode(owner) { viewMode = mode }
        if filterWriteID == nil && !filterDraft, let sharedFilters = snapshot.filters(owner) { filters = sharedFilters }
        restoringNavigation = previous; persistNavigation()
    }
    func changeCollectionFilters(_ next: NativeCollectionFilters) {
        viewRevision += 1; filters = next
        guard folderCollection, let io else { return }
        filterDraft = !MacSharedFilters.canPersist(next)
        guard !filterDraft else { return }
        let owner = destination, origin = generation, token = UUID(), previous = filterWrite
        filterWriteID = token
        filterWrite = Task {
            await previous?.value
            do {
                let result = try await io.macSaveFilters(owner: owner, filters: next)
                if origin == generation { viewRevision += 1; sharedViews = result; cacheCurrentSnapshot() }
            } catch { if origin == generation { issue = error.localizedDescription } }
            if origin == generation && filterWriteID == token { filterWriteID = nil; filterWrite = nil }
        }
    }
    func saveCurrentView(name: String) async -> Bool {
        let owner = destination, origin = generation, mode = viewMode, layout = collectionLayout, currentFilters = filters
        guard folderCollection, let io, MacSharedFilters.canPersist(currentFilters) else { issue = "Complete the filter values before saving a folder view."; return false }
        await filterWrite?.value
        guard origin == generation else { return false }
        do {
            let result = try await io.macSavePreset(owner: owner, name: name, mode: mode, layout: layout, filters: currentFilters)
            guard origin == generation else { return false }; viewRevision += 1; namedViews = result
            if destination == owner && folderCollection { savedViews = result.entries(owner) }
            return true
        } catch { issue = error.localizedDescription; return false }
    }
    func applySavedView(_ entry: MacSavedView) async {
        let owner = destination, origin = generation
        guard folderCollection, let io else { return }
        await filterWrite?.value
        guard origin == generation else { return }
        do {
            let result = try await io.macApplyPreset(owner: owner, entry: entry)
            guard origin == generation else { return }; viewRevision += 1; sharedViews = result; cacheCurrentSnapshot()
            if destination == owner && folderCollection { filterDraft = false; adoptSharedView(result, owner: owner); clearCollectionSelection(); browsingCollection = true }
        } catch { issue = error.localizedDescription }
    }
    func changeSavedView(_ entry: MacSavedView, name: String?, owner: String, workspaceID: UUID) async -> Bool {
        guard workspaceID == generation, let io else { issue = "The vault changed. Reopen saved views."; return false }
        do {
            let result: MacSavedViewSnapshot
            if let name { result = try await io.macRenamePreset(owner: owner, entry: entry, name: name) }
            else { result = try await io.macDeletePreset(owner: owner, entry: entry) }
            guard workspaceID == generation else { return false }; viewRevision += 1; namedViews = result
            if destination == owner && folderCollection { savedViews = result.entries(owner) }
            return true
        } catch { issue = error.localizedDescription; return false }
    }
    func updateCollectionLayout(_ layout: MacCollectionLayout, mode: String? = nil) async {
        let origin = generation, owner = destination, folder = folderCollection, nextMode = mode ?? viewMode
        let previous = collectionLayout, previousMode = viewMode
        if mode != nil { browsingCollection = true }
        viewRevision += 1
        collectionLayout = layout; viewMode = nextMode
        do {
            if folder, let io {
                let result = try await io.macSaveView(owner: owner, mode: nextMode, layout: layout)
                guard origin == generation else { return }; viewRevision += 1; sharedViews = result; cacheCurrentSnapshot()
            }
            guard origin == generation, owner == destination, folder == folderCollection else { return }
            collectionLayout = layout; viewMode = nextMode
        } catch { if origin == generation {
            if owner == destination && folder == folderCollection && collectionLayout == layout && viewMode == nextMode { collectionLayout = previous; viewMode = previousMode }
            issue = error.localizedDescription
        } }
    }
    func setCollectionProperty(path: String, expected: String, workspaceID: UUID, name: String, value: NativePropertyValue?) async throws {
        guard workspaceID == generation, await save(), workspaceID == generation, let io else { throw VaultFailure(message: "The vault changed. Reopen the property editor.") }
        guard let note = notes.first(where: { $0.path == path }), !note.trashed, note.content == expected else { throw VaultFailure(message: "The note changed. Reopen its property to preserve the latest version.") }
        guard !name.isEmpty, !name.lowercased().hasPrefix("zerus-") else { throw VaultFailure(message: "This property is managed by Zerus.") }
        if let definition = try schema?.effective(notePath: path).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            guard definition.type != .relation else { throw VaultFailure(message: "Use the paired relation editor.") }
            try definition.validateValue(value)
        }
        let text = try NativeFrontmatter(note.content).setting(name, value: value)
        try await io.write(path, data: Data(text.utf8), expected: Data(expected.utf8))
        guard workspaceID == generation else { return }
        apply(try await io.scan()); await reloadCurrent()
    }
    func prepareCollectionMove(paths: Set<String>, name: String, value: NativePropertyValue?, workspaceID: UUID) async throws -> NativeBulkPlan {
        guard workspaceID == generation, await save(), workspaceID == generation else { throw VaultFailure(message: "The vault changed. Move the notes again.") }
        let snapshot = try await bulkReviewSnapshot()
        guard workspaceID == generation else { throw VaultFailure(message: "The vault changed. Move the notes again.") }
        let selected = snapshot.source.notes.filter { paths.contains($0.path) }
        guard selected.count == paths.count, !selected.isEmpty else { throw VaultFailure(message: "Some selected notes are no longer available.") }
        return try snapshot.plan(selected: selected, mutation: .init(properties: [.init(name: name, operation: value == nil ? .clear : .set, value: value)]))
    }
    func navigate(_ value: String, newTab: Bool = false) { Task { await openCollection(value, newTab: newTab) } }
    func navigateFolder(_ value: String, newTab: Bool = false) { Task { await openCollection(value, folder: true, newTab: newTab) } }
    func openCollection(_ value: String, folder: Bool = false, record: Bool = true, newTab: Bool = true) async {
        guard await save() else { return }
        await filterWrite?.value
        persistNavigation()
        let restoring = restoringNavigation; restoringNavigation = true
        restoreCollection(value, folder: folder)
        editorFocusRequest = nil; baseline = nil; selection = nil; body = ""; revisions = nil; history = nil; browsingCollection = true
        let tab: MacTab = folder ? .folder(value) : .collection(value)
        if !tabs.contains(tab) {
            if !newTab, let current = activeTab, !pinnedTabs.contains(current), let index = tabs.firstIndex(of: current) {
                tabs[index] = tab
            } else { tabs.append(tab) }
        }
        activeTab = tab
        restoringNavigation = restoring
        if record { recordNavigation(tab) }; persistNavigation()
    }
    func activateTab(_ tab: MacTab, record: Bool = true) async {
        switch tab { case .note(let path): await openNote(path, record: record, newTab: true); case .collection(let value): await openCollection(value, record: record); case .folder(let path): await openCollection(path, folder: true, record: record) }
    }
    private func recordNavigation(_ tab: MacTab) {
        if navigation.indices.contains(navigationIndex), navigation[navigationIndex] == tab { return }
        navigation = Array(navigation.prefix(navigationIndex + 1)); navigation.append(tab); navigationIndex = navigation.count - 1
    }
    func togglePinnedTab(_ tab: MacTab) {
        guard tabs.contains(tab) else { return }
        if pinnedTabs.contains(tab) { pinnedTabs.remove(tab) } else { pinnedTabs.insert(tab) }
        persistNavigation()
    }
    func reorderTab(_ tab: MacTab, before other: MacTab) {
        guard tab != other, let source = tabs.firstIndex(of: tab), tabs.contains(other) else { return }
        var ordered = tabs; ordered.remove(at: source)
        if let index = ordered.firstIndex(of: other) { ordered.insert(tab, at: index); tabs = ordered }
    }
    func toggleFolder(_ folder: String) {
        guard !keptFolders.contains(where: { $0 == folder || $0.hasPrefix(folder + "/") }) else { return }
        if collapsedFolders.contains(folder) { collapsedFolders.remove(folder) } else { collapsedFolders.insert(folder) }
    }
    func keepFolderOpen(_ folder: String) {
        if keptFolders.contains(folder) { keptFolders.remove(folder) }
        else { keptFolders.insert(folder); collapsedFolders = collapsedFolders.filter { !folder.hasPrefix($0 + "/") && $0 != folder } }
    }
    func clearCollectionSelection() {
        selectedPaths = []; selecting = false; collectionSelectionAnchor = nil
    }
    func selectAllCollectionNotes() {
        let paths = collection.map(\.path)
        selectedPaths = Set(paths); selecting = true; collectionSelectionAnchor = paths.last
    }
    /// The caller supplies the order of the displayed group (or Calendar month).
    /// Clamp stale rendered rows to the current filtered collection before use.
    func activateCollectionNote(_ path: String, modifiers: NSEvent.ModifierFlags = [], order: [String]? = nil) async {
        let visible = collection.map(\.path), allowed = Set(visible)
        var seen = Set<String>()
        let ordered = (order ?? visible).filter { allowed.contains($0) && seen.insert($0).inserted }
        guard allowed.contains(path), let end = ordered.firstIndex(of: path) else { return }
        if selecting || modifiers.contains(.command) || modifiers.contains(.shift) {
            selectedPaths.formIntersection(allowed)
            if modifiers.contains(.shift), let anchor = collectionSelectionAnchor, let start = ordered.firstIndex(of: anchor) {
                selectedPaths.formUnion(ordered[min(start, end)...max(start, end)])
            } else {
                if !selectedPaths.insert(path).inserted { selectedPaths.remove(path) }
                collectionSelectionAnchor = path
            }
        } else {
            clearCollectionSelection()
            await openNote(path)
        }
    }
    /// `awaitInspector: false` returns once the note is in the editor and
    /// loads its saved versions in the background. Version history can sit on
    /// slow (iCloud) storage and must not hold up callers such as search.
    func openNote(_ path: String, record: Bool = true, preserveCollection: Bool = false, newTab: Bool = false, awaitInspector: Bool = true) async {
        guard path != selection else { browsingCollection = false; editorFocusRequest = UUID(); return }
        guard await save(), let note = notes.first(where: { $0.path == path }) else { return }
        persistNavigation()
        if !preserveCollection, !collection.contains(where: { $0.path == path }) {
            // Root notes display “Inbox”, but do not live in an Inbox directory.
            // Imported root notes must open in a collection that includes them.
            let filed = note.path.contains("/")
            let target = note.trashed ? "Trash" : note.folder == "Saved links" ? "Links" : note.folder == "Files" ? "Files" : filed ? note.folder : "All Notes"
            restoreCollection(target, folder: filed && !note.trashed && !note.path.hasPrefix(".zerus/"))
        }
        adoptOpenedNote(note, record: record, newTab: newTab)
        if awaitInspector { await loadInspector() } else { Task { await loadInspector() } }
    }
    private func adoptOpenedNote(_ note: NoteDocument, record: Bool, newTab: Bool = false) {
        headingRequest = nil; draftState.visibleHeading = nil; browsingCollection = false; baseline = note; selection = note.path; body = drafts[note.path] ?? note.parts.body
        titleSyncJobs.removeValue(forKey: note.path)?.cancel(); openedTitles[note.path] = note.title
        baselineIdentityUnique = note.stableID.map { id in notes.filter { !$0.trashed && $0.stableID == id }.count == 1 } ?? false
        noteDiskChange = nil; retainedExport = nil; retainedExportReady = false
        sourceMode = openingRequiresSource(body)
        let tab = MacTab.note(note.path)
        // Replacing or appending a tab and activating it are one navigation transition.
        // Persist the completed state rather than writing an inactive new tab.
        let restoring = restoringNavigation; restoringNavigation = true
        if !tabs.contains(tab) {
            if !newTab, let current = activeTab, !pinnedTabs.contains(current), let index = tabs.firstIndex(of: current) {
                tabs[index] = tab
            } else { tabs.append(tab) }
        }; activeTab = tab
        restoringNavigation = restoring
        if record { recordNavigation(tab) }; persistNavigation()
        editorFocusRequest = UUID()
        saveStatus = "Saved"
        if let recovery = recoverDraft(note), recovery != note.parts.body {
            body = recovery; drafts[note.path] = recovery; persistDraft(); saveStatus = "Recovered draft — Save to keep"; issue = "An unsaved draft was recovered for \(note.title). Review it before saving."
        }
    }
    func canHistoryStep(_ step: Int) -> Bool { navigation.indices.contains(navigationIndex + step) }
    func historyStep(_ step: Int) async {
        let next = navigationIndex + step
        guard navigation.indices.contains(next) else { return }
        let previous = navigationIndex; navigationIndex = next
        let tab = navigation[next]
        await activateTab(tab, record: false)
        if activeTab != tab { navigationIndex = previous }
    }
    func closeTab(_ tab: MacTab) async {
        if tab == activeTab { guard await save() else { return }; activeTab = nil; selection = nil; baseline = nil; body = "" }
        let removedIndex = tabs.firstIndex(of: tab)
        tabs.removeAll { $0 == tab }
        if activeTab == nil, !tabs.isEmpty {
            let next = tabs[min(removedIndex ?? tabs.count - 1, tabs.count - 1)]
            await activateTab(next)
        }
        persistNavigation()
    }
    /// The saved link owns one managed URL paragraph. Its URL bar edits that
    /// address; the writing surface edits only the title and annotations.
    func editorBody(_ text: String) -> String {
        guard let saved = editorSavedLink else { return text }
        return NativeSavedLink.withoutURL(text, address: saved.address)
    }
    func changedEditor(_ text: String) {
        if let saved = editorSavedLink { changed(NativeSavedLink.withURL(text, address: saved.address)) }
        else { changed(text) }
    }
    func editingIntent() { noteEditRevision += 1 }
    func changed(_ text: String) {
        guard baseline != nil, !schemaMaintenanceSaving, !noteMovesSaving else { return }
        noteEditRevision += 1
        if browsingCollection { browsingCollection = false }
        if agentWritingHeld, text != body { noteDiskChange = .modified }
        body = text
        if retainedExportReady { retainedExportReady = false }
        let status = noteDiskChange == nil ? "Unsaved changes" : "Outside change — text retained"
        if saveStatus != status { saveStatus = status }
        if let path = selection { drafts[path] = text; persistDraft() }
        saveJob?.cancel()
        guard noteDiskChange == nil else { return }
        saveJob = Task { try? await Task.sleep(for: .milliseconds(800)); guard !Task.isCancelled else { return }; _ = await save() }
    }
    @discardableResult func save() async -> Bool {
        // Serialize saves; a later edit must compare against the result of the preceding save.
        if let pending = writes { guard await pending.value else { return false } }
        guard noteDiskChange == nil else { saveStatus = "Outside change — text retained"; return false }
        guard let original = baseline, original.parts.body != body, let io else { return true }
        let content = original.replacingBody(body), origin = generation
        let job = Task { () -> Bool in
            do {
                try await io.write(original.path, data: Data(content.utf8), expected: Data(original.content.utf8))
                guard origin == generation else { return true }
                var updated = original; updated.content = content; updated.modified = Date()
                if startupRefreshing { startupSaved[original.path] = updated; startupSaveRevision += 1 }
                guard selection == original.path else { return true }
                baseline = updated
                if let i = notes.firstIndex(where: { $0.path == original.path }) { notes[i] = updated }
                if body == updated.parts.body { saveStatus = "Saved"; drafts.removeValue(forKey: original.path); removeDraft(original) }
                cacheCurrentSnapshot()
                return true
            } catch { saveStatus = "Save blocked — draft retained"; issue = error.localizedDescription; return false }
        }
        writes = job; let saved = await job.value; writes = nil; return saved
    }
    private func draftURL(_ note: NoteDocument) -> URL? {
        root.map { MacNoteRecoveryStore.location(root: $0.standardizedFileURL.resolvingSymlinksInPath(), path: note.path, windowID: draftOwner) }
    }
    private func persistDraft() {
        guard let note = baseline, let root else { return }
        let origin = generation, keptBody = body
        MacNoteRecoveryStore.enqueueCheckpoint(root: root, note: note, body: keptBody, windowID: draftOwner) { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.generation == origin, self.selection == note.path,
                      self.body.utf8.elementsEqual(keptBody.utf8), self.drafts[note.path] != nil || self.noteDiskChange != nil else { return }
                self.issue = "The recovery draft could not be saved: " + message
            }
        }
    }
    private func liveDraftOwners() -> Set<String> {
        guard let root else { return [] }
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        return Set(Self.windows.compactMap { entry in
            guard let peer = entry.value, peer !== self, peer.root?.standardizedFileURL.resolvingSymlinksInPath() == canonical else { return nil }
            return peer.draftOwner
        })
    }
    private func recoverDraft(_ note: NoteDocument) -> String? {
        guard let root else { return nil }
        do {
            let live = liveDraftOwners()
            let records = try MacNoteRecoveryStore.snapshot(root: root, notePath: note.path).records.filter { $0.note.path == note.path && ($0.windowID.map { !live.contains($0) } ?? true) }
            let matching = records.filter { Data($0.note.content.utf8) == Data(note.content.utf8) }
            guard Set(matching.map { Data($0.body.utf8) }).count == 1 else {
                if !records.isEmpty { issue = "Retained drafts exist for this note. Review Note recovery drafts before choosing which text to keep." }
                return nil
            }
            adoptedDrafts[note.path] = matching.filter { $0.windowID != draftOwner }
            return matching.first?.body
        } catch { issue = "Recovery drafts could not be read and were kept: " + error.localizedDescription; return nil }
    }
    private func removeDraft(_ note: NoteDocument) {
        MacNoteRecoveryStore.flushCheckpoints()
        if let url = draftURL(note) { try? FileManager.default.removeItem(at: url) }
        let live = liveDraftOwners()
        for record in adoptedDrafts.removeValue(forKey: note.path) ?? [] {
            guard record.windowID.map({ !live.contains($0) }) ?? true,
                  (try? Data(contentsOf: record.file)) == record.bytes else { continue }
            try? FileManager.default.removeItem(at: record.file)
        }
    }
    @discardableResult func createNote(title: String = "Untitled", folder: String? = nil) async -> String? {
        guard !busy, !preparingToClose, !schemaMaintenanceSaving, !noteMovesSaving else { issue = "Finish the current change before creating a note."; return nil }
        let directory = folder ?? (folderCollection ? destination : defaultNoteFolder)
        let previousFolderCollection = folderCollection
        let nextCollection = !folderCollection && ["Trash", "Tasks", "External Notes", "Files", "Links"].contains(destination) ? "All Notes" : destination
        busy = true; defer { busy = false }
        guard await save(), let io else { return nil }
        guard !isDirty else { issue = "Writing arrived while saving. Save your draft before creating another note."; return nil }
        let origin = generation
        do {
            let name = try NativeNoteRename.cleanTitle(title)
            var path = directory + "/" + name + ".md", number = 2
            while notes.contains(where: { $0.path.caseInsensitiveCompare(path) == .orderedSame }) { path = directory + "/" + name + " \(number).md"; number += 1 }
            let noteID = UUID().uuidString.lowercased()
            let text = "---\nzerus-id: \(noteID)\n---\n# \(name)\n\n"
            try await io.write(path, data: Data(text.utf8), expected: nil)
            let snapshot = try await io.scan()
            // A case-insensitive volume may keep a different directory spelling.
            // Follow the created identity to the actual scanned path.
            if let saved = snapshot.notes.first(where: { $0.stableID == noteID }) { path = saved.path }
            guard origin == generation else { issue = "The vault changed. The new note was kept in its original vault."; return nil }
            apply(snapshot); persistNavigation(); restoreCollection(nextCollection, folder: previousFolderCollection)
            query = ""; changeCollectionFilters(.init(sort: .createdDescending))
            await openNote(path, preserveCollection: true); return path
        } catch { issue = error.localizedDescription; return nil }
    }
    func folderIcon(_ folder: String) -> String? { folderIcons[Data(folder.utf8)] }
    private func adoptFolderIcons(_ snapshot: VaultSnapshot) {
        if folderIconBytes != snapshot.macFolderIconBytes {
            let icons = (try? MacFolderIconSnapshot(root: root ?? URL(fileURLWithPath: "/"), bytes: snapshot.macFolderIconBytes))?.icons ?? [:]
            folderIconBytes = snapshot.macFolderIconBytes
            if folderIcons != icons { folderIcons = icons }
        }
        if folderIconIssue != snapshot.folderIssue { folderIconIssue = snapshot.folderIssue }
    }
    func folderIconReview(_ request: MacFolderIconRequest) async throws -> MacFolderIconSnapshot {
        guard request.workspaceID == workspaceID, folders.contains(where: { $0.utf8.elementsEqual(request.folder.utf8) }), let io else { throw VaultFailure(message: "The vault or folder changed. Reopen the icon picker.") }
        let snapshot = try await io.macFolderIconSnapshot()
        guard request.workspaceID == workspaceID else { throw VaultFailure(message: "The vault changed. Reopen the icon picker.") }
        var result = snapshot; result.workspaceID = request.workspaceID; return result
    }
    func changeFolderIcon(_ snapshot: MacFolderIconSnapshot, folder: String, value: String?) async throws {
        guard snapshot.workspaceID == workspaceID, !busy, !preparingToClose, !schemaMaintenanceSaving, !noteMovesSaving, !agentWritingHeld, let io else { throw VaultFailure(message: "The vault changed or another change is running. Reopen the icon picker.") }
        let origin = workspaceID; busy = true; defer { busy = false }
        let updated = try await io.macSetFolderIcon(snapshot, folder: folder, value: value)
        guard origin == workspaceID else { return }
        for peer in Self.windows.compactMap(\.value) where peer.root?.resolvingSymlinksInPath().standardizedFileURL == root?.resolvingSymlinksInPath().standardizedFileURL {
            peer.snapshotRevision += 1; peer.refreshID = nil
            peer.adoptFolderIcons(updated); peer.cacheCurrentSnapshot()
        }
    }
    func createFolder(_ name: String) async {
        guard !busy, !preparingToClose, !schemaMaintenanceSaving, !noteMovesSaving, let io else { return }
        let origin = workspaceID; busy = true; defer { busy = false }
        do {
            let folder = try NativeFolderPath.clean(name), previous = try await io.scan().folders
            let created = try await io.createFolder(folder)
            let decorated = await suggestingFolderIcons(in: created, destinations: [folder], previousFolders: previous, using: io)
            let snapshot = decorated.snapshot
            if let warning = decorated.warning { issue = warning }
            guard origin == workspaceID else { return }; apply(snapshot); await openCollection(folder, folder: true)
        } catch { issue = error.localizedDescription }
    }

    func bulkReviewSnapshot() async throws -> NativeBulkSnapshot {
        guard await save(), let io else { throw VaultFailure(message: "Save the current note before reviewing changes.") }
        let origin = generation, snapshot = try await io.bulkSnapshot()
        guard origin == generation else { throw VaultFailure(message: "The vault changed. Reopen the review.") }
        var schema = snapshot.source.schema; schema.workspaceID = origin
        return .init(source: .init(schema: schema, notes: snapshot.source.notes.map { note in var value = note; value.workspaceID = origin; return value }), historyBytes: snapshot.historyBytes, records: snapshot.records)
    }
    func prepareFolderRename(_ source: String, destination: String) async throws -> NativeFolderRenamePlan {
        guard await save(), let io else { throw VaultFailure(message: "Save the current note before reviewing changes.") }
        let origin = generation, raw = try await io.relationDefinitionSnapshot()
        var schema = raw.schema; schema.workspaceID = origin
        let plan = try await io.prepareFolderRename(.init(schema: schema, notes: raw.notes), source: source, destination: destination)
        guard origin == generation else { throw VaultFailure(message: "The vault changed. Reopen the folder review.") }
        return plan
    }
    func prepareFolderTrash(_ source: String) async throws -> NativeFolderTrashPlan {
        guard await save(), let io else { throw VaultFailure(message: "Save the current note before reviewing changes.") }
        let origin = generation
        var plan = try await io.prepareFolderTrash(source)
        guard origin == generation else { throw VaultFailure(message: "The vault changed. Reopen the folder review.") }
        plan.workspaceID = origin; return plan
    }
    func prepareFolderRestore(_ entry: NativeFolderTrashEntry, purge: Bool = false) async throws -> NativeFolderTrashPlan {
        guard await save(), let io else { throw VaultFailure(message: "Save the current note before reviewing changes.") }
        let origin = generation
        var plan = try await io.prepareFolderRestore(entry, purge: purge)
        guard origin == generation else { throw VaultFailure(message: "The vault changed. Reopen the folder review.") }
        plan.workspaceID = origin; return plan
    }
    func commitFolderRename(_ plan: NativeFolderRenamePlan) async throws {
        guard !busy, !preparingToClose else { throw VaultFailure(message: "Finish the current change before renaming a folder.") }
        busy = true; defer { busy = false }
        guard plan.snapshot.schema.root == root, plan.snapshot.schema.workspaceID == generation, let io, await save(), plan.snapshot.schema.workspaceID == generation else { throw VaultFailure(message: "The vault changed or saving is blocked. Review the folder again.") }
        let snapshot = try await io.applyFolderRename(plan)
        guard plan.snapshot.schema.workspaceID == generation, plan.snapshot.schema.root == root else { throw VaultFailure(message: "The folder was renamed in its original vault. Reopen that vault to refresh its folders.") }
        remapDefaultNoteFolder(from: plan.source, to: plan.destination)
        persistFolderOrder(folderOrder.map { NativeFolderPath.remap($0, from: plan.source, to: plan.destination) })
        restoringNavigation = true
        let source = plan.source, target = plan.destination, oldSelected = selection
        pinnedTabs = Set(pinnedTabs.map { $0.remappingFolder(source, to: target) })
        tabs = tabs.map { $0.remappingFolder(source, to: target) }; activeTab = activeTab?.remappingFolder(source, to: target)
        navigation = navigation.map { $0.remappingFolder(source, to: target) }
        keptFolders = Set(keptFolders.map { NativeFolderPath.remap($0, from: source, to: target) })
        collapsedFolders = Set(collapsedFolders.map { NativeFolderPath.remap($0, from: source, to: target) })
        var remapped: [String: MacCollectionState] = [:]
        for (key, value) in navigationState.collections {
            let mapped = key.hasPrefix("folder:") ? "folder:" + NativeFolderPath.remap(String(key.dropFirst(7)), from: source, to: target) : key
            remapped[mapped] = value
        }
        navigationState.collections = remapped
        if folderCollection { destination = NativeFolderPath.remap(destination, from: source, to: target) }
        apply(snapshot)
        if let oldSelected { selection = NativeFolderRenamePlan.notePath(oldSelected, source: source, destination: target) }
        restoringNavigation = false
        await reconcileNavigation(); persistNavigation()
    }
    func commitFolderTrash(_ plan: NativeFolderTrashPlan) async throws {
        guard !busy, !preparingToClose else { throw VaultFailure(message: "Finish the current change before changing a folder.") }
        busy = true; defer { busy = false }
        guard plan.root == root, plan.workspaceID == generation, let io, await save(), plan.workspaceID == generation else { throw VaultFailure(message: "The vault changed or saving is blocked. Review the folder again.") }
        let snapshot = try await io.applyFolderTrash(plan)
        guard plan.workspaceID == generation, plan.root == root else { throw VaultFailure(message: "The folder change was saved in its original vault. Reopen that vault to refresh its folders.") }
        apply(snapshot)
        if plan.action == .trash {
            remapDefaultNoteFolder(from: plan.entry.record.folder, to: nil)
            let path = plan.entry.record.folder
            persistFolderOrder(folderOrder.filter { $0 != path && !$0.hasPrefix(path + "/") })
            keptFolders = keptFolders.filter { $0 != path && !$0.hasPrefix(path + "/") }
            collapsedFolders = collapsedFolders.filter { $0 != path && !$0.hasPrefix(path + "/") }
        }
        await reconcileNavigation(); persistNavigation()
    }
    func reconcileNavigation() async {
        let valid = MacNavigationState(tabs: tabs, active: activeTab).validated(notes: notes, folders: folders)
        tabs = valid.tabs
        if let path = selection, let note = notes.first(where: { $0.path == path }) { baseline = note; body = note.parts.body; await loadInspector() }
        else { baseline = nil; selection = nil; body = ""; revisions = nil; history = nil }
        if activeTab != nil && !tabs.contains(activeTab!) { activeTab = nil }
        if folderCollection && !folders.contains(destination) { restoreCollection("All Notes") }
        if activeTab == nil { if let tab = valid.active { await activateTab(tab) } else { await openCollection("All Notes") } }
        await refreshMetadata(); persistNavigation()
    }
    /// Renaming recreates the path-keyed editor (losing cursor and Undo), so a
    /// title edit renames the file shortly after the note is left, not mid-typing.
    private func scheduleTitleFileSync(_ path: String) {
        guard let opened = openedTitles.removeValue(forKey: path) else { return }
        titleSyncJobs.removeValue(forKey: path)?.cancel()
        titleSyncJobs[path] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.syncFileNameToTitle(path, openedTitle: opened)
        }
    }
    private func syncFileNameToTitle(_ path: String, openedTitle: String) async {
        titleSyncJobs[path] = nil
        if let pending = writes { _ = await pending.value }
        guard selection != path, drafts[path] == nil, !busy, !preparingToClose, !schemaMaintenanceSaving, !noteMovesSaving, let io,
              let note = notes.first(where: { $0.path == path }), !note.trashed, note.stableID != nil,
              let title = MacTitleFileSync.title(path: path, title: note.title, openedTitle: openedTitle) else { return }
        let origin = generation
        do {
            let snapshot = try await io.relationDefinitionSnapshot()
            let plan = try await io.prepareRename(snapshot, source: path, title: title, renameFile: true)
            guard origin == generation, selection != path, drafts[path] == nil else { return }
            let result = try await io.applyRelationMaintenance(plan.maintenance)
            guard origin == generation else { return }
            apply(result)
            guard let renamed = result.notes.first(where: { !$0.trashed && $0.stableID == note.stableID }), renamed.path != path else { return }
            remapMovedNotePaths([path: renamed.path])
            // The note was reopened while its file moved: adopt the new path.
            if baseline?.path == path { baseline = renamed; if let draft = drafts.removeValue(forKey: path) { drafts[renamed.path] = draft } }
            persistNavigation()
        } catch {
            // Keep the current file name (e.g. the target name is taken).
            // The explicit Rename command reports why.
        }
    }
    func rename(_ note: NoteDocument, title: String) async {
        guard await save(), let io else { return }
        do {
            let snapshot = try await io.relationDefinitionSnapshot()
            let plan = try await io.prepareRename(snapshot, source: note.path, title: title, renameFile: true)
            apply(try await io.applyRelationMaintenance(plan.maintenance))
            tabs.removeAll { $0 == .note(note.path) }; selection = nil; baseline = nil
            if let newNote = notes.first(where: { $0.stableID == note.stableID }) { await openNote(newNote.path) }
        } catch { issue = error.localizedDescription }
    }
    func noteMoveDraftLocations(_ paths: Set<String>) -> [String: URL] {
        guard let root else { return [:] }
        return Dictionary(uniqueKeysWithValues: paths.map { path in
            do { return (path, try MacNoteRecoveryStore.locations(root: root, path: path).first ?? MacNoteRecoveryStore.location(root: root, path: path, windowID: draftOwner)) }
            catch { return (path, MacNoteRecoveryStore.directory) }
        })
    }
    func remapMovedNotePaths(_ mapping: [String: String]) {
        let previous = restoringNavigation
        restoringNavigation = true; defer { restoringNavigation = previous }
        func remap(_ tab: MacTab) -> MacTab { if case .note(let path) = tab, let target = mapping[path] { return .note(target) }; return tab }
        pinnedTabs = Set(pinnedTabs.map(remap))
        var seen = Set<MacTab>()
        tabs = tabs.map(remap).filter { seen.insert($0).inserted }
        activeTab = activeTab.map(remap); navigation = navigation.map(remap)
        if let selection, let target = mapping[selection] { self.selection = target }
        selectedPaths.subtract(mapping.keys)
    }
    func move(_ note: NoteDocument, folder: String) async {
        guard await save(), let io else { return }
        do {
            let snapshot = try await io.relationDefinitionSnapshot()
            let path = (folder.isEmpty ? "" : folder + "/") + (note.path as NSString).lastPathComponent
            let plan = try await io.prepareMove(snapshot, source: note.path, destination: path)
            let moved = try await io.applyMacNoteMove(plan, source: note.path, destination: path)
            apply(moved.snapshot); selection = nil; baseline = nil; tabs.removeAll { $0 == .note(note.path) }; await openNote(path)
            if !moved.warnings.isEmpty { issue = moved.warnings.map(\.reason).joined(separator: "\n") }
        } catch { issue = error.localizedDescription }
    }
    func commitBulk(_ plan: NativeBulkPlan) async throws {
        guard plan.snapshot.source.schema.root == root, plan.snapshot.source.schema.workspaceID == generation, let io, await save(), plan.snapshot.source.schema.workspaceID == generation else { throw VaultFailure(message: "The vault changed or saving is blocked. Review the organization change again.") }
        apply(try await io.applyBulk(plan)); await reloadCurrent()
    }
    func flag(_ paths: Set<String>, pinned: Bool? = nil, archived: Bool? = nil) async {
        guard await save(), let io else { return }
        do {
            let snapshot = try await io.bulkSnapshot()
            let plan = try snapshot.plan(selected: notes.filter { paths.contains($0.path) }, mutation: .init(pinned: pinned, archived: archived))
            apply(try await io.applyBulk(plan)); await reloadCurrent()
        } catch { issue = error.localizedDescription }
    }
    func trash(_ note: NoteDocument) async {
        guard await save(), let io else { return }
        do {
            let current = notes.first { $0.path == note.path } ?? note
            let path = try await io.availablePath(current.trashed ? String(current.path.dropFirst(7)) : ".trash/" + current.path)
            try await io.move(current.path, to: path, expected: Data(current.content.utf8))
            tabs.removeAll { $0 == .note(note.path) }; if selection == note.path { selection = nil; baseline = nil; body = ""; activeTab = nil }
            apply(try await io.scan())
        } catch { issue = error.localizedDescription }
    }
    /// Reviews permanent removal of every note currently in Trash.
    func prepareEmptyTrash() async -> NativeNoteTrashPlan? {
        guard await save(), let io else { return nil }
        let paths = Set(notes.filter(\.trashed).map(\.path)); guard !paths.isEmpty else { return nil }
        do { return try await io.prepareNoteTrashPurge(try await io.revisionTrashSnapshot(), paths: paths) }
        catch { issue = error.localizedDescription; return nil }
    }
    func commitEmptyTrash(_ plan: NativeNoteTrashPlan) async {
        guard await save(), let io else { return }
        do {
            guard plan.snapshot.root == root else { throw VaultFailure(message: "The vault changed. Review emptying Trash again.") }
            apply(try await io.applyNoteTrashPurge(plan)); await reconcileNavigation()
        } catch { issue = error.localizedDescription }
    }
    func duplicate(_ note: NoteDocument) async {
        guard let created = await createNote(title: note.title + " copy", folder: note.folder), selection == created else { return }
        changed(note.parts.body); _ = await save()
    }
    func setProperty(_ name: String, value: NativePropertyValue?) async {
        guard await save(), let note = baseline, let io else { return }
        do {
            guard !name.isEmpty, !name.lowercased().hasPrefix("zerus-") else { throw VaultFailure(message: "Zerus-managed properties cannot be edited here.") }
            if let definition = try schema?.effective(notePath: note.path).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                guard definition.type != .relation else { throw VaultFailure(message: "Relations need their dedicated paired editor. This value was left unchanged.") }
                if let value { try definition.validateValue(value) }
            }
            let text = try NativeFrontmatter(note.content).setting(name, value: value)
            try await io.write(note.path, data: Data(text.utf8), expected: Data(note.content.utf8))
            apply(try await io.scan()); await reloadCurrent()
        } catch { issue = error.localizedDescription }
    }
    func loadInspector() async {
        guard let io, let path = selection else { return }
        let origin = generation, epoch = metadataEpoch
        do {
            let snapshot = try await io.macRecoverySnapshot(notePath: path, workspaceID: origin)
            guard origin == generation, epoch == metadataEpoch, selection == path else { return }
            revisions = snapshot.revisions; history = snapshot.history; revisionIssue = snapshot.revisionIssue; historyIssue = snapshot.historyIssue
        } catch { if origin == generation && epoch == metadataEpoch && selection == path { revisions = nil; history = nil; revisionIssue = error.localizedDescription; historyIssue = error.localizedDescription } }
    }
    func reloadCurrent() async {
        guard let path = selection, let note = notes.first(where: { $0.path == path }) else { return }
        baseline = note; body = note.parts.body; await refreshMetadata()
    }
    private func applyTaskData(_ data: NativeTaskData) {
        let bytes = try? JSONSerialization.data(withJSONObject: data.object, options: [.sortedKeys])
        // The cached task snapshot is reset with the vault. Identical JSON has
        // identical derived collections and warnings; polling must not publish
        // five window-wide changes for it. Compare bytes, preserving Unicode
        // spellings and foreign fields, and still apply if encoding fails.
        if let bytes, bytes == startupTaskData { return }
        startupTaskData = bytes
        tasks = data.tasks.map { value in var task = value; task.workspaceID = generation; return task }
        taskLists = data.lists; taskCategories = data.categories; generalTaskListName = data.generalName; taskWarning = data.warning
    }
    func newTask(title: String = "", listID: String = "") -> NativeTask {
        var task = NativeTask(title: title); task.workspaceID = generation
        if !listID.isEmpty { task.listID = listID }; return task
    }
    func taskDraftSession(_ task: NativeTask, recovered: NativeTaskDraft? = nil) throws -> NativeTaskDraftSession {
        guard task.workspaceID == generation else { throw VaultFailure(message: "The vault changed. Reopen this task in its original vault.") }
        let session = NativeTaskDraftSession(task: task, store: taskDraftStore, canonical: tasks.first { $0.id == task.id }, recovered: recovered, accessIssue: taskDraftIssue)
        if let saved = session.completedCopy(in: tasks) { session.committed(saved) }
        return session
    }
    func reloadTask(id: String, workspaceID: UUID) async throws -> NativeTask {
        await taskPipeline?.value
        guard workspaceID == generation, let io else { throw VaultFailure(message: "The vault changed. Reopen this task in its original vault.") }
        let data = try await io.taskData()
        guard workspaceID == generation else { throw CancellationError() }
        taskRevision += 1; applyTaskData(data)
        guard let task = tasks.first(where: { $0.id == id }) else { throw VaultFailure(message: "This task is no longer in the vault. Export its draft or save it as a new task.") }
        return task
    }
    func commitTaskDraft(_ session: NativeTaskDraftSession, delete: Bool = false, copy: Bool = false) async -> Bool {
        guard session.task.workspaceID == generation else { issue = "The vault changed. Reopen this task in its original vault."; return false }
        session.keep()
        do {
            if copy, let saved = session.completedCopy(in: tasks) { session.committed(saved); return true }
            let submitted = session.task
            let task = try copy ? session.copyIntent() : submitted
            guard await saveTask(task, delete: delete) else { return false }
            guard task.workspaceID == generation else { session.keep(); issue = "The vault changed. Reopen this task in its original vault."; return false }
            if delete { try session.discard() }
            else {
                let saved = tasks.first { $0.id == task.id } ?? task, latest = session.task
                let changed = Set(submitted.raw.keys).union(latest.raw.keys).subtracting(["updatedAt", "completedAt"])
                    .filter { !NativeTaskData.equal(submitted.raw[$0], latest.raw[$0]) }
                if !changed.isEmpty {
                    // A queued control/input event can arrive after the save
                    // snapshot. Advance its baseline without discarding that
                    // newer draft, including the identity of a newly saved copy.
                    if latest.id == submitted.id, NativeTaskData.equal(latest.raw["createdAt"], submitted.raw["createdAt"]) {
                        var merged = saved.raw
                        for key in changed { merged[key] = latest.raw[key] }
                        if let retained = NativeTask(restoring: merged, baseline: saved.raw, workspace: task.workspaceID) { session.task = retained }
                    }
                    session.keep()
                    issue = "Earlier task changes were saved. Newer task changes remain open; save again."
                    return false
                }
                session.committed(saved)
            }
            return true
        } catch { issue = error.localizedDescription; return false }
    }
    @discardableResult func saveTask(_ task: NativeTask, delete: Bool = false) async -> Bool {
        guard let origin = task.workspaceID else { issue = "Reopen this task in its vault before saving."; return false }
        return await changeTasks(.save(task, delete: delete), workspaceID: origin)
    }
    @discardableResult func changeTasks(_ change: NativeTaskChange, workspaceID expected: UUID) async -> Bool {
        guard expected == generation, let io else { issue = "The vault changed. Reopen the task or list controls."; return false }
        let origin = generation, previous = taskPipeline
        taskRevision += 1; pendingTaskChanges += 1; tasksSaving = true
        let job = Task { () -> Bool in
            await previous?.value
            guard origin == generation else { return false }
            defer { if origin == generation { pendingTaskChanges -= 1; tasksSaving = pendingTaskChanges > 0 } }
            do {
                let data = try await io.changeTasks(change)
                guard origin == generation else { return false }
                taskRevision += 1; applyTaskData(data); cacheCurrentSnapshot(); return true
            } catch { if origin == generation { issue = error.localizedDescription }; return false }
        }
        taskPipeline = job; return await job.value
    }
    func createLink(address: String, title: String) async {
        guard let io else { return }
        do { let note = try await io.createSavedLink(address: address, title: title); apply(try await io.scan()); destination = "Links"; await openNote(note.path) }
        catch { issue = error.localizedDescription }
    }
    func updateLink(_ note: NoteDocument, address: String, workspaceID: UUID) async throws {
        guard workspaceID == generation, let io else { throw VaultFailure(message: "The vault changed. Reopen this link.") }
        guard await save(), workspaceID == generation else { throw VaultFailure(message: "Save the note before updating its address.") }
        guard let current = notes.first(where: { $0.path == note.path }), current.content == note.content else {
            throw VaultFailure(message: "This note changed. Reopen Edit URL before saving.")
        }
        let snapshot = try await io.updateSavedLink(note, address: address)
        guard workspaceID == generation else { return }
        apply(snapshot); await reloadCurrent()
    }
    func createLinkedNote(title: String, folder: String, workspaceID origin: UUID) async throws -> NoteDocument {
        guard origin == workspaceID, let io else { throw VaultFailure(message: "The vault changed. Choose the note link again.") }
        let target = folder.isEmpty || folder.hasPrefix(".") ? defaultNoteFolder : folder
        let note = try await io.createLinkTarget(title: title, folder: target)
        guard origin == workspaceID else { throw VaultFailure(message: "The vault changed after creating the note. The original vault keeps it; insert its link there.") }
        await refresh(); return note
    }
    func follow(_ value: String) async {
        if value.hasPrefix("zerus-attachment:"), let note = current,
           let item = NativeFileAttachment.all(in: note.content).first(where: { $0.id == String(value.dropFirst("zerus-attachment:".count)) }) { await previewAttachment(item); return }
        if let url = URL(string: value), ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); return }
        let reference = URL(string: value).flatMap(NoteReference.init(url:)) ?? NoteReference(target: value, label: value, explicitLabel: false)
        if let url = URL(string: value), let fragment = MacHeadings.localFragment(url) {
            revealHeading(fragment); return
        }
        // Markdown moves write explicit relative URLs. Resolve them from the
        // active note before considering title/path aliases elsewhere in the vault.
        if let root, let current, let url = URL(string: value), url.scheme == nil, !value.hasPrefix("#"),
           let candidates = try? VaultFiles.resourceCandidates(value, notePath: current.path, root: root),
           let note = candidates.compactMap({ candidate in notes.first { !$0.trashed && root.appendingPathComponent($0.path).standardizedFileURL == candidate } }).first {
            await openLinkedNote(note, heading: URL(string: value).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.fragment }); return
        }
        // Ordinary local file links (including Add file's vault-root asset
        // spelling) open the document preview after relative note resolution.
        if let root, let current, let url = URL(string: value), url.scheme == nil, !value.hasPrefix("#"),
           let file = try? VaultFiles.resolveResource(value, notePath: current.path, root: root),
           !["md", "markdown"].contains(file.pathExtension.lowercased()) {
            do { previewDocument = try NativeFileLease(scope: root, url: file) }
            catch { issue = error.localizedDescription }
            return
        }
        let targets = reference.targets(in: notes, includeHeadingFragments: true)
        if targets.count == 1, let note = targets.first { await openLinkedNote(note, heading: reference.heading(in: note)) }
        else if targets.isEmpty, !reference.target.hasPrefix("zerus:"), reference.target.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\#")) == nil, (try? NativeNoteRename.cleanTitle(reference.target)) != nil, root != nil {
            let folder = current.map { ($0.path as NSString).deletingLastPathComponent }.flatMap { $0.isEmpty || $0.hasPrefix(".") ? nil : $0 } ?? defaultNoteFolder
            missingNoteLink = .init(title: reference.target, folder: folder, workspaceID: workspaceID)
        } else { issue = targets.isEmpty ? "This note link could not be found in the current vault." : "This note link matches more than one note. Use a stable note link." }
    }
    func reveal(_ note: NoteDocument) { if let root { NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(note.path)]) } }
}
