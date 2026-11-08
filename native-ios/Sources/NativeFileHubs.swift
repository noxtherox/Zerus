import Foundation

struct NativeFileHub: Equatable, Sendable {
    enum Kind: String, Sendable { case vault, location, local }
    static let keys = ["zerus-file-id", "zerus-file-name", "zerus-file-kind", "zerus-file-location", "zerus-file-path", "zerus-file-managed"]
    let id: String
    let name: String
    let kind: Kind
    let path: String?
    let locationID: String?
    let managed: Bool
    init(id: String, name: String, kind: Kind, path: String? = nil, locationID: String? = nil, managed: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.path = path; self.locationID = locationID; self.managed = managed
    }
    init?(_ note: NoteDocument) {
        let fields = NativeFrontmatter(note.content)
        func text(_ key: String) -> String? {
            guard case .text(let raw) = fields.entry(key)?.value else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value
        }
        guard let id = text(Self.keys[0]), let name = text(Self.keys[1]), let raw = text(Self.keys[2]), let kind = Kind(rawValue: raw) else { return nil }
        let path = text(Self.keys[4]).flatMap(Self.relative), location = text(Self.keys[3])
        guard kind == .local || path != nil, kind != .location || location != nil else { return nil }
        self.init(id: id, name: name, kind: kind, path: path, locationID: location, managed: fields.entry(Self.keys[5])?.value == .checkbox(true))
    }
    static func relative(_ value: String) -> String? {
        var value = value.replacingOccurrences(of: "\\", with: "/")
        if value.hasPrefix("./") { value.removeFirst(2) }
        guard !value.isEmpty, !value.hasPrefix("/"), value.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) == nil,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return value
    }
    func setting(in content: String) throws -> String {
        var next = content
        let values: [NativePropertyValue?] = [.text(id), .text(name), .text(kind.rawValue), locationID.map(NativePropertyValue.text), path.map(NativePropertyValue.text), managed ? .checkbox(true) : nil]
        for (key, value) in zip(Self.keys, values) { next = try NativeFrontmatter(next).setting(key, value: value) }
        return next
    }
    func portableBody(_ body: String) -> String {
        guard kind == .vault, let path else { return body }
        let label = name.replacingOccurrences(of: #"[\[\]\r\n]"#, with: "", options: .regularExpression)
        return body + "\n\n[" + label + "](" + MarkdownResources.encodedPath(path, preservingSuffixOf: "") + ")\n"
    }
    static func detached(_ content: String) throws -> String {
        try keys.reduce(content) { try NativeFrontmatter($0).setting($1, value: nil) }
    }
}

extension NoteDocument {
    var fileHub: NativeFileHub? { NativeFileHub(self) }
    var unfiledFileHub: Bool { !trashed && path.hasPrefix(".zerus/files/") }
}

enum NativeFileStorage: String, CaseIterable, Sendable {
    case copy = "Copy into vault", external = "Keep original connection", backup = "Keep connection and backup"
    var shortName: String { switch self { case .copy: "Vault copy"; case .external: "Original connection"; case .backup: "Original + backup" } }
    var detail: String {
        switch self {
        case .copy: "A portable copy travels with your notes. The original stays in place."
        case .external: "Use the original file. Other devices may need to locate it or map its folder."
        case .backup: "Use the original and keep a snapshot in the vault. The backup does not update automatically."
        }
    }
}

struct NativeFileAttachment: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    static func all(in content: String) -> [Self] {
        guard case .list(let values) = NativeFrontmatter(content).entry("zerus-attachments")?.value else { return [] }
        var seen = Set<String>()
        return values.compactMap { value in
            guard let raw = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any], let id = raw["id"] as? String, let name = raw["name"] as? String,
                  raw["kind"] as? String == "vault", let path = raw["path"] as? String, let normalized = NativeFileHub.relative(path), seen.insert(id).inserted else { return nil }
            return Self(id: id, name: name, path: normalized)
        }
    }
}

struct NativeFileLocation: Identifiable, Equatable, Sendable { let id: String; let name: String }
struct NativeFileLocations: Sendable {
    static let path = ".zerus/file-locations.json"
    let bytes: Data?
    let locations: [NativeFileLocation]
    let warning: String?
    init(_ bytes: Data?) throws {
        self.bytes = bytes
        guard let bytes else { locations = []; warning = nil; return }
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], NativeHistory.integer(value["version"]) == 1, let records = value["locations"] as? [Any] else { throw VaultFailure(message: "File locations use an unsupported format. The original file is preserved.") }
        var known: [NativeFileLocation] = [], seen = Set<String>()
        for record in records {
            guard let raw = record as? [String: Any], let id = raw["id"] as? String, !id.isEmpty, let name = raw["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(id).inserted else { continue }
            known.append(.init(id: id, name: name))
        }
        locations = known; warning = records.count == known.count ? nil : "Some file-location records are unsupported and have been preserved."
    }
}

enum NativeFileLocationChange: Sendable { case add(id: String, name: String), rename(NativeFileLocation, name: String), remove(NativeFileLocation) }

extension VaultFiles {
    func fileLocations() throws -> NativeFileLocations { try NativeFileLocations(historyData(NativeFileLocations.path)) }
    func changeFileLocation(_ change: NativeFileLocationChange) throws -> NativeFileLocations {
        let current = try fileLocations()
        var object = try current.bytes.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] } ?? ["version": 1, "locations": [Any]()]
        var records = object["locations"] as! [Any]
        let id: String, name: String?
        switch change {
        case .add(let value, let title): id = value; name = title
        case .rename(let original, let title): id = original.id; name = title
        case .remove(let original): id = original.id; name = nil
        }
        if let name {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200, name.rangeOfCharacter(from: .newlines) == nil else { throw VaultFailure(message: "Use a location name of 1–200 characters on one line.") }
        }
        let matches = records.indices.filter { (records[$0] as? [String: Any])?["id"] as? String == id }
        var dependencies: [VaultFileChange] = []
        var paths: Set<String>?
        switch change {
        case .add:
            guard !id.isEmpty, matches.isEmpty else { throw VaultFailure(message: "That file location already exists.") }
            records.append(["id": id, "name": name!.trimmingCharacters(in: .whitespacesAndNewlines)])
        case .rename(let original, _), .remove(let original):
            guard matches.count == 1, var record = records[matches[0]] as? [String: Any], record["name"] as? String == original.name else { throw VaultFailure(message: "This file location changed. Refresh before editing it.") }
            if let name { record["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines); records[matches[0]] = record }
            else {
                let snapshot = try scan()
                guard !snapshot.notes.contains(where: { note in NativeFrontmatter(note.content).entries.contains { $0.key.lowercased() == "zerus-file-location" && ($0.value == nil || $0.value?.display == id) } }) else { throw VaultFailure(message: "Notes still use this location, including any in Recently Deleted. Replace or detach those connections before removing it.") }
                dependencies = snapshot.notes.map { .init(path: $0.path, before: Data($0.content.utf8), after: Data($0.content.utf8)) }; paths = Set(snapshot.notes.map(\.path)); records.remove(at: matches[0])
            }
        }
        object["locations"] = records
        let after = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), expected = paths, root = root
        try applyTransaction(dependencies + [.init(path: NativeFileLocations.path, before: current.bytes, after: after)], validate: {
            if let expected, try Self.notePathInventory(root: root) != expected { throw VaultFailure(message: "Notes changed while removing the location. Refresh and try again.") }
        })
        return try NativeFileLocations(after)
    }

    /// Note metadata, source checks and optional backup/copy are one recovered
    /// transaction. Replacing a binding gives it a new identity; the old
    /// bookmark remains usable by history and never points at the new file.
    func saveFileHub(basis: VaultSnapshot, note: NoteDocument?, original: NativeFileHub?, reference: NativeFileHub?, title: String, folder: String, source: NativeFileLease?, storage: NativeFileStorage, locations: NativeFileLocations? = nil) throws -> NoteDocument {
        let id = note?.stableID ?? UUID().uuidString.lowercased()
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
        var path = note?.path ?? ((folder == "Inbox" ? "" : folder + "/") + Self.fileNoteName(clean.isEmpty ? "Document" : clean) + ".md")
        if note == nil {
            let base = String(path.dropLast(3)); var count = 2
            while try basis.notes.contains(where: { $0.path == path }) || FileManager.default.fileExists(atPath: url(for: path).path) { path = base + " \(count).md"; count += 1 }
        }
        if let note {
            guard !note.trashed, basis.notes.first(where: { $0.path == note.path })?.content == note.content, note.fileHub == original else { throw VaultFailure(message: "The linked file or note changed. Reopen the file action.") }
        }
        var content = note?.content ?? "---\nzerus-id: \(id)\n---\n# \(clean.isEmpty ? "Document" : clean)\n\n"
        var assets: [VaultFileChange] = [], sourceBytes: Data?
        if var reference {
            if storage == .copy || storage == .backup {
                guard let source else { throw VaultFailure(message: "Choose the file again.") }
                let data = try source.readForCopy(); sourceBytes = data
                let ownedPath = ".zerus/attachments/" + UUID().uuidString.lowercased() + "/" + Self.fileNoteName(reference.name)
                assets.append(.init(path: ownedPath, before: nil, after: data))
                if storage == .copy { reference = .init(id: reference.id, name: reference.name, kind: .vault, path: ownedPath, managed: true) }
                else {
                    let fields = NativeFrontmatter(content), existing: [String]
                    if let entry = fields.entry("zerus-attachments") { guard case .list(let values) = entry.value else { throw VaultFailure(message: "This note's attachment metadata uses an unsupported format. Its original bytes are preserved.") }; existing = values } else { existing = [] }
                    let backupID = UUID().uuidString.lowercased()
                    let attachment: [String: Any] = ["id": backupID, "name": reference.name, "kind": "vault", "path": ownedPath, "managed": true]
                    let record = String(decoding: try JSONSerialization.data(withJSONObject: attachment, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
                    content = try fields.setting("zerus-attachments", value: .list(existing + [record]))
                    let temporary = NoteDocument(path: path, content: content, modified: Date())
                    let newline = content.contains("\r\n") ? "\r\n" : "\n"
                    content = temporary.replacingBody(temporary.parts.body + newline + "Backup: [" + reference.name.replacingOccurrences(of: #"[\[\]\r\n]"#, with: "", options: .regularExpression) + "](zerus-attachment:" + backupID + ")" + newline)
                }
            }
            content = try reference.setting(in: content)
        } else { content = try NativeFileHub.detached(content) }
        let changes = basis.notes.map { item in VaultFileChange(path: item.path, before: Data(item.content.utf8), after: Data((item.path == path ? content : item.content).utf8)) }
        let creation = note == nil ? [VaultFileChange(path: path, before: nil, after: Data(content.utf8))] : []
        let paths = Set(basis.notes.map(\.path)), root = root, bytes = sourceBytes, sourceLease = source
        let locationDependency: [VaultFileChange] = reference?.kind == .location ? [.init(path: NativeFileLocations.path, before: locations?.bytes, after: locations?.bytes)] : []
        try applyTransaction(changes + creation + assets + locationDependency, selectedReading: bytes == nil ? [] : [sourceLease!], validate: {
            guard try Self.notePathInventory(root: root) == paths else { throw VaultFailure(message: "Notes changed. Reopen this file action before saving.") }
            if let bytes, let sourceLease, try Data(contentsOf: sourceLease.url) != bytes { throw VaultFailure(message: "The original file changed while saving. Choose it again to review the current file.") }
        })
        return .init(path: path, content: content, modified: Date())
    }
    nonisolated static func fileNoteName(_ text: String) -> String {
        let safe = text.replacingOccurrences(of: #"[/\\:\x00-\x1F]"#, with: "-", options: .regularExpression)
        return safe.isEmpty || safe == "." || safe == ".." ? "Document" : safe
    }
}
