import SwiftUI
import CryptoKit

@MainActor
final class NativeSearchModel: ObservableObject {
    @Published private(set) var result: NativeSearchResult?
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    private let engine = NativeSearchEngine()
    private var building: Task<Void, Never>?
    private var querying: Task<Void, Never>?
    private var epoch = UUID()
    private var queryEpoch = UUID()
    private var workspace: UUID?
    private var recentKey = ""
    private var recent: [String] = []
    private var query = ""
    private var filters = NativeSearchFilters()
    private var limit = 80
    private var ready = false
    private var externalRecords: [NativeExternalSearchRecord] = []
    private var replacingExternal: Task<Void, Never>?
    private var externalEpoch = UUID()
    private var externalUpdating = false

    func updateExternal(_ records: [NativeExternalSearchRecord]) {
        externalRecords = records; externalEpoch = UUID()
        replacingExternal?.cancel(); querying?.cancel(); queryEpoch = UUID()
        result = nil
        guard ready, let workspace else { return }
        externalUpdating = true; loading = true
        let request = externalEpoch, epoch = epoch
        replacingExternal = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.replaceExternal(records, workspace: workspace)
                guard self.externalEpoch == request, self.epoch == epoch else { return }
                self.externalUpdating = false; self.runQuery()
            } catch is CancellationError {} catch {
                guard self.externalEpoch == request, self.epoch == epoch else { return }
                self.problem = error.localizedDescription; self.loading = false
            }
        }
    }
    func rebuild(vault: VaultStore, external records: [NativeExternalSearchRecord] = []) {
        building?.cancel(); querying?.cancel(); replacingExternal?.cancel(); externalRecords = records
        let next = UUID(); epoch = next; ready = false; externalUpdating = false
        guard let root = vault.root else { result = nil; loading = false; return }
        let origin = vault.workspaceID
        if workspace != origin {
            result = nil; limit = 80
            restoreRecent(vault: vault, root: root)
        }
        workspace = origin; loading = true; problem = nil
        let sources = vault.searchSources(), files = vault.files
        let live = NativeChat.liveSearchConversation(for: root)
        let engine = engine
        building = Task { [weak self] in
            do {
                let worker = VaultFiles(root: root)
                let supplement = try await worker.searchSupplement(files: files, liveConversation: live)
                try Task.checkCancellation()
                try await engine.rebuild(sources, supplement: supplement)
                guard let self, self.epoch == next, vault.workspaceID == origin else { return }
                self.ready = true; self.updateExternal(self.externalRecords)
            } catch is CancellationError {} catch {
                guard let self, self.epoch == next, vault.workspaceID == origin else { return }
                self.problem = error.localizedDescription; self.loading = false
            }
        }
    }
    func search(query: String, filters: NativeSearchFilters) {
        self.query = query; self.filters = filters; limit = 80
        runQuery()
    }
    func more() { limit += 80; runQuery() }
    func visited(_ item: NativeSearchItem) {
        guard !recentKey.isEmpty else { return }
        recent.removeAll { $0 == item.id }; recent.insert(item.id, at: 0); recent = Array(recent.prefix(50))
        UserDefaults.standard.set(recent, forKey: recentKey)
    }
    func clearRecent() {
        guard !recentKey.isEmpty else { return }
        recent = []
        // An empty saved list is authoritative after Clear, including when
        // an older path-keyed list becomes available after a later relocation.
        UserDefaults.standard.set(recent, forKey: recentKey); runQuery()
    }
    private func restoreRecent(vault: VaultStore, root: URL) {
        let defaults = UserDefaults.standard
        func legacyKey(_ url: URL) -> String {
            "zerus.native.search.recent." + SHA256.hash(data: Data(url.standardizedFileURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        guard let id = vault.activeVaultID else {
            recentKey = legacyKey(root); recent = defaults.stringArray(forKey: recentKey) ?? []; return
        }
        recentKey = "zerus.native.search.recent.vault." + id.uuidString.lowercased()
        let current = vault.savedVaults.first { $0.id == id }.flatMap { URL(string: $0.location) }
        let roots = [root] + [current].compactMap { $0 } + vault.previousVaultRoots
        let otherLocations = Set(vault.savedVaults.filter { $0.id != id }.compactMap { URL(string: $0.location)?.standardizedFileURL })
        var seen = Set<String>(), imported = Set<String>()
        recent = []
        for candidate in roots where !otherLocations.contains(candidate.standardizedFileURL) {
            let key = legacyKey(candidate)
            guard let visits = defaults.stringArray(forKey: key) else { continue }
            for visit in visits where seen.insert(visit).inserted { recent.append(visit) }
            imported.insert(key)
        }
        if defaults.object(forKey: recentKey) != nil {
            if let saved = defaults.stringArray(forKey: recentKey) {
                recent = saved
                // Finish a migration interrupted after the canonical save.
                // A reused old path must not inherit its leftover source key.
                for key in imported { defaults.removeObject(forKey: key) }
            } else { recent = [] }
            return
        }
        recent = Array(recent.prefix(50))
        // Save the stable identity first. Retire only the known, unambiguous
        // source keys so a different vault reusing that path cannot adopt them.
        // Unknown or ambiguous legacy data remains untouched.
        defaults.set(recent, forKey: recentKey)
        for key in imported { defaults.removeObject(forKey: key) }
    }
    private func runQuery() {
        querying?.cancel(); let request = UUID(); queryEpoch = request
        guard ready, !externalUpdating, let workspace else { return }
        let query = query, filters = filters, recent = recent, limit = limit, epoch = epoch, engine = engine
        loading = true
        querying = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(160))
                let value = try await engine.search(workspace: workspace, query: query, filters: filters, recent: recent, limit: limit)
                guard let self, self.epoch == epoch, self.queryEpoch == request, self.workspace == workspace else { return }
                self.result = value; self.loading = false; self.problem = nil
            } catch is CancellationError {} catch {
                guard let self, self.epoch == epoch, self.queryEpoch == request else { return }
                self.problem = error.localizedDescription; self.loading = false
            }
        }
    }
}
