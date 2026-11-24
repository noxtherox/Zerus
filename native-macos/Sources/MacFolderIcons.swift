import SwiftUI
import AppKit

/// Offline artwork and search order come from the same Tabler catalog as desktop.
@MainActor final class MacFolderIconCatalog: ObservableObject {
    struct Entry: Decodable, Sendable, Identifiable {
        let name: String
        let label: String
        let searchText: String
        let svg: String
        var id: String { name }
    }
    private struct Catalog: Decodable, Sendable {
        let version: Int
        let icons: [Entry]
        let keywords: [String: String]
    }
    static let shared = MacFolderIconCatalog()
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var issue: String?
    private var names: [String: Entry] = [:]
    private var keywords: [String: String] = [:]
    private var loading: Task<Catalog, Error>?
    private let images = NSCache<NSString, NSImage>()
    init() { images.countLimit = 384 }
    func load() async {
        guard entries.isEmpty else { return }
        if loading == nil {
            let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "FolderIcons")
            loading = Task.detached(priority: .utility) {
                guard let url else { throw VaultFailure(message: "The offline icon catalog is missing. Reinstall the app to restore it.") }
                let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
                guard catalog.version == 1, !catalog.icons.isEmpty, Set(catalog.icons.map(\.name)).count == catalog.icons.count else { throw VaultFailure(message: "The offline icon catalog has an unsupported format.") }
                return catalog
            }
        }
        do {
            let value = try await loading!.value
            if entries.isEmpty { entries = value.icons; names = Dictionary(uniqueKeysWithValues: value.icons.map { ($0.name, $0) }); keywords = value.keywords }
            issue = nil
        } catch { issue = error.localizedDescription }
        loading = nil
    }
    func matches(_ query: String) -> [Entry] {
        let words = query.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
        return words.isEmpty ? entries : entries.filter { entry in words.allSatisfy { entry.searchText.contains($0) } }
    }
    func image(_ value: String?) -> NSImage? {
        guard let value, value.hasPrefix("tabler:"), let entry = names[String(value.dropFirst(7))] else { return nil }
        if let cached = images.object(forKey: value as NSString) { return cached }
        guard let image = NSImage(data: Data(entry.svg.utf8)) else { return nil }
        image.isTemplate = true; images.setObject(image, forKey: value as NSString); return image
    }
    func suggestion(_ name: String) -> String? {
        let words = name.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
        func singulars(_ word: String) -> [String] {
            if word.count > 3 && word.hasSuffix("ies") { return [String(word.dropLast(3)) + "y", String(word.dropLast())] }
            if word.count > 3 && word.hasSuffix("es") { return [String(word.dropLast()), String(word.dropLast(2))] }
            if word.count > 2 && word.hasSuffix("s") { return [String(word.dropLast())] }
            return []
        }
        for word in words.flatMap({ [$0] + singulars($0) }) { if let icon = keywords[word] { return "tabler:" + icon } }
        return nil
    }
}

struct MacFolderIcon: View {
    let value: String?
    var size: CGFloat = 17
    @ObservedObject private var catalog = MacFolderIconCatalog.shared
    var body: some View {
        Group {
            if let value, !value.hasPrefix("tabler:"), value.unicodeScalars.contains(where: { !$0.isASCII }) { Text(value).lineLimit(1) }
            else if let image = catalog.image(value) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "folder") }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .task { if value?.hasPrefix("tabler:") == true { await catalog.load() } }
    }
}

struct MacFolderLabel: View {
    let path: String
    let icon: String?
    var body: some View { Label { Text(path) } icon: { MacFolderIcon(value: icon, size: 14) } }
}

struct MacFolderIconRequest: Identifiable {
    let folder: String
    let workspaceID: UUID
    var id: String { folder }
}
struct MacFolderIconPicker: View {
    @Bindable var workspace: MacWorkspace
    let request: MacFolderIconRequest
    @ObservedObject private var catalog = MacFolderIconCatalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: MacFolderIconSnapshot?
    @State private var query = ""
    @State private var emoji = ""
    @State private var count = 160
    @State private var busy = false
    @State private var issue: String?
    private var connected: Bool { workspace.workspaceID == request.workspaceID && workspace.folders.contains { $0.utf8.elementsEqual(request.folder.utf8) } }
    var body: some View {
        let matches = catalog.matches(query)
        VStack(alignment: .leading, spacing: 14) {
            Text("Icon for “" + (request.folder as NSString).lastPathComponent + "”").font(.title2.bold())
            Text("Search the offline Tabler catalog or use an emoji.").foregroundStyle(.secondary)
            TextField("Search icons…", text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { _, _ in count = 160 }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                    ForEach(matches.prefix(count)) { entry in
                        let value = "tabler:" + entry.name
                        Button { save(value) } label: {
                            MacFolderIcon(value: value).frame(width: 40, height: 40)
                                .background(snapshot?.icon(request.folder) == value ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(MacBoxButtonStyle()).help(entry.label).accessibilityLabel("Use " + entry.label + " icon")
                    }
                }
                if matches.count > count { Button("Show more (\(matches.count - count) remaining)") { count += 160 }.padding(.top, 8) }
                if matches.isEmpty && catalog.issue == nil { Text(catalog.entries.isEmpty ? "Loading icons…" : "No matching icons").foregroundStyle(.secondary).padding() }
            }.frame(height: 300).disabled(snapshot == nil || !connected || busy)
            HStack {
                TextField("One emoji", text: $emoji).textFieldStyle(.roundedBorder).frame(width: 120)
                Button("Use emoji") { save(emoji) }.disabled(emoji.count != 1 || !emoji.unicodeScalars.contains { !$0.isASCII } || snapshot == nil || !connected || busy)
                Spacer(); Text("\(matches.count) icons").font(.caption).foregroundStyle(.secondary)
            }
            if let message = issue ?? catalog.issue { HStack { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled); Button("Reload") { Task { await reload() } } } }
            if !connected { Text("The vault or folder changed. Reopen the icon picker.").foregroundStyle(.secondary) }
            HStack {
                Button("Reset to folder") { save(nil) }.disabled(snapshot == nil || !connected || busy)
                if busy { ProgressView().controlSize(.small) }
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
        }.padding(24).frame(width: 600).interactiveDismissDisabled(busy)
            .task { await reload() }
    }
    private func reload() async {
        do { snapshot = try await workspace.folderIconReview(request); issue = nil }
        catch { issue = error.localizedDescription }
        await catalog.load()
    }
    private func save(_ value: String?) {
        guard let snapshot, !busy else { return }; busy = true; issue = nil
        Task { defer { busy = false }; do { try await workspace.changeFolderIcon(snapshot, folder: request.folder, value: value); dismiss() } catch { issue = error.localizedDescription } }
    }
}


extension MacWorkspace {
    /// The desktop suggests each newly created destination level. Restrict the
    /// candidates to this operation's destinations, not other newly scanned paths.
    func suggestingFolderIcons(in snapshot: VaultSnapshot, destinations: [String], previousFolders: [String], using io: VaultFiles) async -> (snapshot: VaultSnapshot, warning: String?) {
        let previous = Set(previousFolders.map { Data($0.utf8) })
        var seen = Set<Data>(), suggestions: [(String, String)] = []
        await MacFolderIconCatalog.shared.load()
        for destination in destinations {
            let parts = destination.split(separator: "/")
            for depth in 1...max(1, parts.count) where depth <= parts.count {
                let path = parts.prefix(depth).joined(separator: "/"), key = Data(path.utf8)
                guard !previous.contains(key), seen.insert(key).inserted,
                      let icon = MacFolderIconCatalog.shared.suggestion(String(parts[depth - 1])) else { continue }
                suggestions.append((path, icon))
            }
        }
        guard !suggestions.isEmpty else { return (snapshot, nil) }
        do { return (try await io.macSuggestFolderIcons(suggestions, previousFolders: previousFolders), nil) }
        catch { return (snapshot, "Files were saved, but suggested folder icons could not be saved. " + error.localizedDescription) }
    }
}
