import Foundation

enum MacTab: Codable, Hashable, Identifiable {
    case note(String), collection(String), folder(String)
    var id: String { switch self { case .note(let path): "note:" + path; case .collection(let name): "collection:" + name; case .folder(let path): "folder:" + path } }
    var target: String { switch self { case .note(let path), .collection(let path), .folder(let path): path } }
    var notePath: String? { if case .note(let path) = self { return path }; return nil }
    func remappingFolder(_ source: String, to destination: String) -> Self {
        switch self {
        case .note(let path): return .note(NativeFolderRenamePlan.notePath(path, source: source, destination: destination))
        case .collection: return self
        case .folder(let path): return .folder(NativeFolderPath.remap(path, from: source, to: destination))
        }
    }
}

/// Device-local navigation contains no note bodies and never changes vault data.
struct MacNavigationState: Codable {
    var version = 1
    var tabs: [MacTab] = []
    var pinnedTabs: Set<MacTab>? = nil
    var active: MacTab?
    var collections: [String: MacCollectionState] = [:]
    var inspector = true
    var currentCollection = "All Notes"
    var currentCollectionIsFolder = false
    var keptFolders: Set<String> = []
    var collapsedFolders: Set<String> = []
    var importedHideSubtypes: Bool? = nil
    static let globalViews: Set<String> = ["All Notes", "Tasks", "Links", "Files", "External Notes", "Pinned", "Archive", "Trash"]
    func validated(notes: [NoteDocument], folders: [String]) -> Self {
        let paths = Set(notes.map(\.path))
        func valid(_ tab: MacTab) -> Bool { switch tab { case .note(let path): paths.contains(path); case .collection(let value): Self.globalViews.contains(value); case .folder(let path): folders.contains(path) } }
        var next = self, seen = Set<MacTab>()
        next.tabs = tabs.filter { valid($0) && seen.insert($0).inserted }
        next.active = active.flatMap { next.tabs.contains($0) ? $0 : nil } ?? next.tabs.last
        let pins = (pinnedTabs ?? []).intersection(Set(next.tabs))
        next.pinnedTabs = pins.isEmpty ? nil : pins
        next.keptFolders = keptFolders.intersection(folders); next.collapsedFolders = collapsedFolders.intersection(folders)
        return next
    }
    func remappingFolder(_ source: String, to destination: String) -> Self {
        var next = self
        next.tabs = tabs.map { $0.remappingFolder(source, to: destination) }
        next.active = active?.remappingFolder(source, to: destination)
        next.pinnedTabs = pinnedTabs.map { Set($0.map { $0.remappingFolder(source, to: destination) }) }
        next.keptFolders = Set(keptFolders.map { NativeFolderPath.remap($0, from: source, to: destination) })
        next.collapsedFolders = Set(collapsedFolders.map { NativeFolderPath.remap($0, from: source, to: destination) })
        if currentCollectionIsFolder { next.currentCollection = NativeFolderPath.remap(currentCollection, from: source, to: destination) }
        // A moved folder's current view takes precedence over stale state once
        // stored for a now-absent destination with the same path.
        next.collections = collections.filter { !$0.key.hasPrefix("folder:") || !MacFolderOrdering.within(String($0.key.dropFirst(7)), source) }
        for (key, value) in collections where key.hasPrefix("folder:") && MacFolderOrdering.within(String(key.dropFirst(7)), source) {
            next.collections["folder:" + NativeFolderPath.remap(String(key.dropFirst(7)), from: source, to: destination)] = value
        }
        return next
    }
    static func key(_ root: URL) -> String { "zerus.mac.navigation.v1." + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.path) }
}

struct MacCollectionState: Codable {
    var query = ""
    var mode = "List"
    var sort = NativeNoteSort.updatedDescending.rawValue
    var date = NativeNoteDate.any.rawValue
    var includeArchived = false
    var folders: Set<String> = []
    var extensions: Set<String> = []
    var matchAnyProperty = false
    var properties: [Property] = []
    var hideSubtypes = false
    var layout: MacCollectionLayout? = nil
    struct Property: Codable {
        struct Value: Codable { let kind: String; let value: String }
        let name: String
        let values: [Value]?
        let comparison: String?
        let date: String
        let endDate: String
        var condition: String? = nil
        var numberComparison: String? = nil
        var number: String? = nil
        var endNumber: String? = nil
        var relativeDate: String? = nil
    }
    init(query: String = "", mode: String = "List", filters: NativeCollectionFilters = .init(), hideSubtypes: Bool = false, layout: MacCollectionLayout? = nil) {
        self.layout = layout; self.query = query; self.mode = mode; self.sort = filters.sort.rawValue; self.date = filters.date.rawValue
        includeArchived = filters.includeArchived; folders = filters.folders; extensions = filters.extensions
        matchAnyProperty = filters.matchAnyProperty; self.hideSubtypes = hideSubtypes
        properties = filters.properties.map { filter in .init(name: filter.name, values: filter.values?.sorted { $0.id < $1.id }.map { .init(kind: $0.kind.rawValue, value: $0.value) }, comparison: filter.dateComparison?.rawValue, date: filter.date, endDate: filter.endDate, condition: filter.condition?.rawValue, numberComparison: filter.numberComparison.rawValue, number: filter.number, endNumber: filter.endNumber, relativeDate: filter.relativeDate.rawValue) }
    }
    var filters: NativeCollectionFilters {
        .init(sort: NativeNoteSort(rawValue: sort) ?? .updatedDescending, date: NativeNoteDate(rawValue: date) ?? .any, includeArchived: includeArchived, folders: folders, extensions: extensions, matchAnyProperty: matchAnyProperty, properties: properties.map { property in
            .init(name: property.name, values: property.values.map { Set($0.compactMap { value in NativeCollectionValue.Kind(rawValue: value.kind).map { NativeCollectionValue(kind: $0, value: value.value) } }) }, dateComparison: property.comparison.flatMap(NativePropertyDateComparison.init(rawValue:)), date: property.date, endDate: property.endDate, condition: property.condition.flatMap(NativePropertyCondition.init(rawValue:)), numberComparison: property.numberComparison.flatMap(NativeNumberComparison.init(rawValue:)) ?? .equal, number: property.number ?? "", endNumber: property.endNumber ?? "", relativeDate: property.relativeDate.flatMap(NativeRelativeDate.init(rawValue:)) ?? .today)
        })
    }
}

/// Shared filtering deliberately rejects trashed paths. Filter their logical paths
/// and return the original documents so restore still operates on the trash file.
enum MacNoteCollection {
    static func filter(_ notes: [NoteDocument], destination: String, filters: NativeCollectionFilters, query: String, hideSubtypes: Bool = false, folderCollection: Bool = false) -> [NoteDocument] {
        let selected = notes.filter { note in
            if folderCollection { return !note.trashed && (hideSubtypes ? (note.path as NSString).deletingLastPathComponent == destination : note.path.hasPrefix(destination + "/")) }
            switch destination {
            case "Trash": return note.trashed
            case "Archive": return !note.trashed && note.archived
            case "Pinned": return !note.trashed && note.pinned
            case "Links": return !note.trashed && (note.savedLink != nil || note.unfiledSavedLink)
            case "Files": return !note.trashed && (note.fileHub != nil || note.unfiledFileHub)
            case "All Notes": return !note.trashed && !note.path.hasPrefix(".zerus/")
            default: return !note.trashed && (hideSubtypes ? (note.path as NSString).deletingLastPathComponent == destination : note.path.hasPrefix(destination + "/"))
            }
        }
        var active = filters
        if !folderCollection && (destination == "Archive" || destination == "Trash") { active.includeArchived = true }
        guard destination == "Trash" && !folderCollection else { return active.apply(selected, query: query, archiveOnly: destination == "Archive" && !folderCollection) }
        let byPath = Dictionary(uniqueKeysWithValues: selected.map { (String($0.path.dropFirst(7)), $0) })
        let logical = selected.map { note in var copy = note; copy.path = String(note.path.dropFirst(7)); return copy }
        return active.apply(logical, query: query).compactMap { byPath[$0.path] }
    }
}

/// Finish device-local paths before the durable rename receipt is removed.
/// Repeating this after another interruption is safe: destination paths no
/// longer match the original source. Vault files stay owned by the transaction.
enum MacFolderRenameRecovery {
    static func finish(root: URL, source: String, destination: String) throws {
        let defaults = UserDefaults.standard
        var changed = false
        let key = MacNavigationState.key(root)
        let saved = try defaults.data(forKey: key) ?? MacNavigationArchive.data(forKey: key)
        if let saved, let state = try? JSONDecoder().decode(MacNavigationState.self, from: saved), state.version == 1 {
            let next = state.remappingFolder(source, to: destination)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(next)
            if data != saved { defaults.set(data, forKey: key); changed = true }
        }
        let folderKey = MacNewNotePreferences.key(root)
        if let folder = defaults.string(forKey: folderKey), MacNewNotePreferences.ordinary(folder) {
            let mapped = NativeFolderPath.remap(folder, from: source, to: destination)
            if mapped != folder { defaults.set(mapped, forKey: folderKey); changed = true }
        }
        let orderKey = MacFolderOrdering.key(root)
        if let order = defaults.stringArray(forKey: orderKey) {
            let mapped = order.map { NativeFolderPath.remap($0, from: source, to: destination) }
            if mapped != order { defaults.set(mapped, forKey: orderKey); changed = true }
        }
        if changed, !defaults.synchronize() {
            throw VaultFailure(message: "The folder was renamed, but its saved window paths could not be stored. The rename recovery record is kept; reopen this vault to retry.")
        }
    }
}
