import SwiftUI

@MainActor
final class NativeNoteVisit: Identifiable, Hashable {
    nonisolated let id = UUID()
    var session: NoteSession
    var stableID: String?
    var savedTitle: String
    let originalPath: String
    var position: NativeReadingPosition?
    var allowsInitialFocus = true
    init(_ session: NoteSession, anchor: NoteDocument) { self.session = session; stableID = anchor.stableID; originalPath = anchor.path; savedTitle = session.document.title }
    nonisolated static func == (lhs: NativeNoteVisit, rhs: NativeNoteVisit) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class NativeNoteNavigation: ObservableObject {
    let root: NativeNoteVisit
    let workspaceID: UUID
    let originTab: Int
    private let vault: VaultStore
    private let persistenceID: UUID?
    private let persistenceOwner = UUID()
    private var persistenceStarted = false
    private var closed = false
    private var reportedResumeFailure: String?
    private var positionSave: Task<Void, Never>?
    @Published private(set) var path: [NativeNoteVisit] = []
    @Published private(set) var forward: [NativeNoteVisit] = []
    @Published private(set) var opening = false
    private struct HeadingJump { let visit: UUID; let request: NativeHeadingRequest }
    @Published private var headingJump: HeadingJump?
    func headingRequest(for visit: UUID) -> NativeHeadingRequest? {
        guard workspaceID == vault.workspaceID, current.id == visit else { return nil }
        return headingJump?.visit == visit ? headingJump?.request : nil
    }
    @Published var issue: String?
    init(vault: VaultStore, session: NoteSession, originTab: Int = 0) {
        self.vault = vault; self.originTab = originTab; persistenceID = vault.activeVaultID; workspaceID = vault.workspaceID; root = NativeNoteVisit(session, anchor: vault.notes.first { $0.path == session.document.path } ?? session.document)
    }
    static func restore(vault: VaultStore) throws -> NativeNoteNavigation? {
        guard !vault.loading, !vault.switchingVault, vault.recovery == nil, let id = vault.activeVaultID,
              let saved = try NativeNoteResumeStore.load(id) else { return nil }
        var visits: [NativeNoteVisit] = [], currentIndex: Int?
        for (index, entry) in saved.entries.enumerated() {
            guard let note = entry.resolve(in: vault), let session = vault.session(for: note) else {
                if index == saved.current { throw VaultFailure(message: "The note you last had open is no longer available or has an ambiguous identity. Choose it again from Library.") }
                continue
            }
            if index == saved.current { currentIndex = visits.count }
            let visit = NativeNoteVisit(session, anchor: note); visit.position = entry.position; visit.allowsInitialFocus = false; visits.append(visit)
        }
        guard let index = currentIndex, let first = visits.first else { return nil }
        let navigation = NativeNoteNavigation(vault: vault, session: first.session, originTab: saved.originTab)
        navigation.root.position = first.position; navigation.root.allowsInitialFocus = false
        navigation.path = Array(visits.dropFirst().prefix(index))
        navigation.forward = Array(visits.dropFirst(index + 1).reversed())
        if visits.count != saved.entries.count { navigation.issue = "Some earlier visits are no longer available. Your remaining note history has been restored." }
        return navigation
    }
    func position(for visitID: UUID) -> NativeReadingPosition? { history.first { $0.id == visitID }?.position }
    func recordPosition(_ position: NativeReadingPosition, for visitID: UUID) {
        guard activePersistence, current.id == visitID, position.valid, current.position != position else { return }
        current.position = position
        positionSave?.cancel()
        positionSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation(); self?.checkpoint() } catch { }
        }
    }
    private var activePersistence: Bool {
        !closed && persistenceStarted && workspaceID == vault.workspaceID && persistenceID != nil && persistenceID == vault.activeVaultID && !vault.switchingVault && vault.recovery == nil
    }
    func activatePersistence() {
        guard !closed, workspaceID == vault.workspaceID, persistenceID == vault.activeVaultID, !vault.switchingVault, vault.recovery == nil else { return }
        persistenceStarted = true; checkpoint(claim: true)
    }
    func checkpoint(claim: Bool = false) {
        guard activePersistence, let id = persistenceID else { return }
        let visits = history, index = path.count, first = visits.count <= 100 ? 0 : max(0, min(index - 79, visits.count - 100))
        let entries = visits.dropFirst(first).prefix(100).map { visit -> NativeNoteResumeStore.Entry in
            let note = target(visit), identity = visit.stableID ?? note?.stableID
            return .init(path: note?.path ?? visit.session.document.path, stableID: identity,
                         legacyHash: identity == nil ? NativeReadingPosition.hash(note?.content ?? visit.session.document.content) : nil, position: visit.position)
        }
        do {
            if try NativeNoteResumeStore.write(.init(owner: persistenceOwner, entries: entries, current: index - first, originTab: originTab), vault: id, claim: claim) { reportedResumeFailure = nil }
        } catch { reportResumeFailure(error) }
    }
    private func reportResumeFailure(_ error: Error) {
        let message = error.localizedDescription
        guard reportedResumeFailure != message else { return }
        reportedResumeFailure = message
        if issue == nil { issue = message }
    }
    func close() {
        positionSave?.cancel()
        if activePersistence, let id = persistenceID {
            do { try NativeNoteResumeStore.close(id, owner: persistenceOwner) } catch { reportResumeFailure(error) }
        }
        closed = true
    }
    var current: NativeNoteVisit { path.last ?? root }
    var history: [NativeNoteVisit] { [root] + path + forward.reversed() }
    var canBack: Bool { workspaceID == vault.workspaceID && !path.isEmpty }
    var canForward: Bool { workspaceID == vault.workspaceID && !forward.isEmpty }
    func target(_ visit: NativeNoteVisit) -> NoteDocument? {
        guard workspaceID == vault.workspaceID else { return nil }
        let note = visit.session.document
        if let identity = visit.stableID {
            let matches = vault.notes.filter { !$0.trashed && $0.stableID == identity }
            return matches.count == 1 ? matches[0] : nil
        }
        // A legacy draft can acquire an ID before its first write succeeds.
        // Use that ID only once it exists in the actual vault inventory.
        if let identity = note.stableID {
            let matches = vault.notes.filter { !$0.trashed && $0.stableID == identity }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
        }
        return vault.notes.first { !$0.trashed && $0.path == visit.originalPath }
    }
    func editor(_ visit: NativeNoteVisit) -> NoteSession? {
        guard workspaceID == vault.workspaceID else { return nil }
        guard let note = target(visit), let editor = vault.session(for: note) else {
            return visit.session.dirty && visit.session.document.workspaceID == workspaceID ? visit.session : nil
        }
        // Restoring a trashed note creates a fresh editor. Retain its current
        // identity so later renames keep this visit connected as well.
        visit.session = editor; visit.stableID = visit.stableID ?? note.stableID; visit.savedTitle = note.title
        return editor
    }
    func title(_ visit: NativeNoteVisit) -> String { target(visit)?.title ?? visit.savedTitle }
    func updatePath(_ replacement: [NativeNoteVisit]) {
        guard workspaceID == vault.workspaceID, replacement != path, replacement.count <= path.count,
              zip(replacement, path).allSatisfy({ $0.id == $1.id }) else { return }
        let removed = path.dropFirst(replacement.count)
        forward.append(contentsOf: removed.reversed()); path = replacement; checkpoint()
    }
    func open(_ requested: NoteDocument, from source: UUID, heading: String? = nil) async {
        guard !opening, !vault.switchingVault, workspaceID == vault.workspaceID, requested.workspaceID == workspaceID, current.id == source else { return }
        opening = true; defer { opening = false }
        await current.session.save()
        guard !vault.switchingVault, workspaceID == vault.workspaceID, current.id == source else { return }
        let matches = vault.notes.filter { !$0.trashed && (requested.stableID == nil ? $0.path == requested.path : $0.stableID == requested.stableID) }
        guard matches.count == 1, let session = vault.session(for: matches[0]) else { issue = "This note is no longer available or has an ambiguous identity. Choose it again from Library."; return }
        if let now = target(current), now.path == matches[0].path {
            if let heading { headingJump = HeadingJump(visit: current.id, request: NativeHeadingRequest(fragment: heading)) }
            return
        }
        forward = []; path.append(NativeNoteVisit(session, anchor: matches[0]))
        headingJump = heading.map { HeadingJump(visit: current.id, request: NativeHeadingRequest(fragment: $0)) }; checkpoint()
    }
    func jump(to destination: UUID, from source: UUID) async {
        guard !opening, !vault.switchingVault, workspaceID == vault.workspaceID, current.id == source, destination != source else { return }
        opening = true; defer { opening = false }
        await current.session.save()
        guard !vault.switchingVault, workspaceID == vault.workspaceID, current.id == source else { return }
        if destination == root.id { updatePath([]) }
        else if let index = path.firstIndex(where: { $0.id == destination }) { updatePath(Array(path.prefix(index + 1))) }
        else if let index = forward.firstIndex(where: { $0.id == destination }) {
            let visits = forward.suffix(from: index).reversed(); path.append(contentsOf: visits); forward.removeSubrange(index...); checkpoint()
        }
    }
}

struct NativeNoteNavigationView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject var navigation: NativeNoteNavigation
    var body: some View {
        NavigationStack(path: Binding(get: { navigation.path }, set: navigation.updatePath)) {
            destination(navigation.root)
                .navigationDestination(for: NativeNoteVisit.self) { visit in destination(visit) }
        }
        .environmentObject(navigation)
        .onAppear { navigation.activatePersistence() }
        .onChange(of: phase) { _, phase in if phase == .active { navigation.activatePersistence() } else { navigation.checkpoint() } }
        .alert("Note navigation", isPresented: Binding(get: { navigation.issue != nil }, set: { if !$0 { navigation.issue = nil } })) {
            Button("OK") { navigation.issue = nil }
        } message: { Text(navigation.issue ?? "") }
    }
    @ViewBuilder private func destination(_ visit: NativeNoteVisit) -> some View {
        if let session = navigation.editor(visit) {
            NoteEditorScreen(session: session, visitID: visit.id, initialPosition: visit.position, allowsInitialFocus: visit.allowsInitialFocus, closeNote: { navigation.close(); dismiss() }, openNote: { note in Task { await navigation.open(note, from: visit.id) } })
        } else {
            ContentUnavailableView("Note unavailable", systemImage: "doc.questionmark", description: Text("This note may be in Recently Deleted, removed or replaced. Return to another visit, or find it in Library."))
                .navigationTitle(navigation.title(visit)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Close note") { navigation.close(); dismiss() } }
                    ToolbarItem(placement: .bottomBar) { NativeNoteNavigationMenu(visitID: visit.id) }
                }
        }
    }
}

struct NativeNoteNavigationMenu: View {
    @EnvironmentObject private var navigation: NativeNoteNavigation
    let visitID: UUID
    var finishEditing: () -> Void = { }
    var body: some View {
        Menu {
            if navigation.canBack {
                Button("Back to " + navigation.title(navigation.path.dropLast().last ?? navigation.root), systemImage: "chevron.backward") { go(navigation.path.dropLast().last ?? navigation.root) }.accessibilityIdentifier("note.navigation.back")
            }
            if let next = navigation.forward.last {
                Button("Forward to " + navigation.title(next), systemImage: "chevron.forward") { go(next) }.accessibilityIdentifier("note.navigation.forward")
            }
            Section("Visit history") {
                ForEach(navigation.history) { visit in
                    Button { go(visit) } label: {
                        Label(navigation.title(visit), systemImage: visit.id == navigation.current.id ? "checkmark" : visit.session.dirty ? "pencil" : "doc.text")
                    }.disabled(visit.id == navigation.current.id).accessibilityIdentifier("note.navigation.visit." + visit.id.uuidString)
                }
            }
        } label: { Label("Navigation", systemImage: "arrow.left.arrow.right") }
        .disabled(navigation.opening).accessibilityIdentifier("note.navigation")
    }
    private func go(_ visit: NativeNoteVisit) { finishEditing(); Task { await navigation.jump(to: visit.id, from: visitID) } }
}
