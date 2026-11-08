import Foundation
import CryptoKit

struct NativeHistoryVersion: Identifiable, Sendable {
    let path: String
    let bytes: Data
    let id: String
    let parentID: String?
    let timestamp: String
    let source: String
    let kept: Bool
    let label: String?
    let checkpoint: Bool
    let depth: Int
    let hash: String
    var content: String?
    var alternate = false
    var incomplete = false
    var object: [String: Any] { (try! JSONSerialization.jsonObject(with: bytes)) as! [String: Any] }
}

struct NativeHistoryObservation: Sendable {
    let before: NoteDocument
    let retrying: Bool
}

struct NativeHistorySnapshot: Sendable {
    let root: URL
    var workspaceID: UUID?
    let note: NoteDocument
    let versions: [NativeHistoryVersion]
    let records: [String: Data]
    let problems: [String]
    let settingsBytes: Data?
    let enabled: Bool
    let limit: Int?
    var directory: String { ".zerus/history/notes/" + (note.stableID ?? "") }
}

enum NativeHistoryAction: Sendable {
    case restore(String), update(String, kept: Bool, label: String), clear
}
struct NativeHistoryPlan: Sendable {
    let snapshot: NativeHistorySnapshot
    let action: NativeHistoryAction
    let changes: [VaultFileChange]
    let content: String?
    var maintenance: NativeHistoryMaintenancePlan? = nil
}

enum NativeHistory {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func hash(_ text: String) -> String { hash(Data(text.utf8)) }
    static func identity(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil }
    static func stripped(_ text: String) -> String {
        let parsed = NativeFrontmatter(text), result = NSMutableString(string: text)
        for entry in parsed.entries.filter({ $0.key.lowercased().hasPrefix("zerus-") }).sorted(by: { $0.range.location > $1.range.location }) { result.replaceCharacters(in: entry.range, with: "") }
        // Empty frontmatter has no user-visible meaning.
        let next = result as String, front = NativeFrontmatter(next)
        return front.header.trimmingCharacters(in: CharacterSet(charactersIn: "-. \r\n")).isEmpty ? front.body : next
    }
    static func preservingMetadata(_ historical: String, current: String) throws -> String {
        let old = NativeFrontmatter(historical), live = NativeFrontmatter(current)
        let output = NSMutableString(string: historical)
        for entry in old.entries.filter({ $0.key.lowercased().hasPrefix("zerus-") }).sorted(by: { $0.range.location > $1.range.location }) { output.replaceCharacters(in: entry.range, with: "") }
        var content = output as String
        // Copy raw ranges so foreign app-owned nested metadata and comments survive.
        let metadata = live.entries.filter { $0.key.lowercased().hasPrefix("zerus-") }.map { (current as NSString).substring(with: $0.range) }.joined()
        if !metadata.isEmpty {
            let target = NativeFrontmatter(content)
            if target.headerLength == 0 { content = "---" + live.newline + metadata + "---" + live.newline + content }
            else { content = (content as NSString).replacingCharacters(in: NSRange(location: target.closingOffset, length: 0), with: metadata) }
        }
        return content
    }
    static func delta(_ before: String, _ after: String) -> [String: Any] {
        let a = Array(before.utf16), b = Array(after.utf16)
        var start = 0, endA = a.count, endB = b.count
        while start < min(a.count, b.count) && a[start] == b[start] { start += 1 }
        // JSON cannot carry a lone surrogate. Broaden the edit to scalar bounds.
        if start > 0 && start < a.count && (0xDC00...0xDFFF).contains(a[start]) { start -= 1 }
        while endA > start && endB > start && a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        if endA < a.count && endA > start && (0xDC00...0xDFFF).contains(a[endA]) { endA += 1; endB += 1 }
        return ["start": start, "removed": String(decoding: a[start..<endA], as: UTF16.self), "inserted": String(decoding: b[start..<endB], as: UTF16.self)]
    }
    static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue < Double(Int.max), n.doubleValue == Double(n.intValue) else { return nil }
        return n.intValue
    }
    static func apply(_ delta: [String: Any], to parent: String) throws -> String {
        guard let start = integer(delta["start"]), let removed = delta["removed"] as? String, let inserted = delta["inserted"] as? String else { throw VaultFailure(message: "Unsupported history delta.") }
        let units = Array(parent.utf16), count = removed.utf16.count
        guard start <= units.count, count <= units.count - start, Array(units[start..<(start + count)]) == Array(removed.utf16) else { throw VaultFailure(message: "History delta does not match its parent.") }
        let result = Array(units[..<start]) + Array(inserted.utf16) + Array(units[(start + count)...])
        let text = String(decoding: result, as: UTF16.self)
        guard Array(text.utf16) == result else { throw VaultFailure(message: "History delta splits a Unicode character.") }
        return text
    }
    static func prunedPaths(_ versions: [NativeHistoryVersion], limit: Int, preserving: Set<String> = []) -> Set<String> {
        let checkpoints = versions.filter { $0.checkpoint && !$0.kept }.sorted { $0.timestamp > $1.timestamp }
        guard checkpoints.count > limit else { return [] }
        let retained = Set(checkpoints.prefix(limit).map(\.id)), byID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
        var keep = Set<String>()
        for id in preserving {
            var cursor = byID[id]
            while let current = cursor, keep.insert(current.id).inserted {
                if current.checkpoint { break }
                cursor = current.parentID.flatMap { byID[$0] }
            }
        }
        for item in versions {
            var cursor: NativeHistoryVersion? = item, family: [String] = [], seen = Set<String>()
            while let current = cursor, seen.insert(current.id).inserted {
                family.append(current.id)
                if current.checkpoint { if retained.contains(current.id) || item.kept { keep.formUnion(family) }; break }
                cursor = current.parentID.flatMap { byID[$0] }
            }
        }
        return Set(versions.filter { !keep.contains($0.id) && !$0.kept }.map(\.path))
    }
    static func imageLinks(_ text: String) throws -> [MarkdownMoveLinks.Link] {
        let refs = Set(MarkdownText.imageReferences(text))
        return try MarkdownMoveLinks.links(in: text).filter { refs.contains($0.value) }
    }
}

extension VaultFiles {
    func historyData(_ path: String) throws -> Data? {
        let location = try url(for: path)
        return FileManager.default.fileExists(atPath: location.path) ? try read(path) : nil
    }
    func historyRecordPaths(_ noteID: String) throws -> Set<String> {
        guard NativeHistory.identity(noteID) else { throw VaultFailure(message: "This note has an unsupported history identity.") }
        let prefix = ".zerus/history/notes/" + noteID, folder = try url(for: prefix)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try Set(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]).filter {
            let values = try $0.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw VaultFailure(message: "History contains an unsupported linked file. Its data is preserved.") }
            return $0.pathExtension == "json" && values.isRegularFile == true
        }.map { prefix + "/" + $0.lastPathComponent })
    }
    func historySnapshot(notePath: String, identity: String? = nil) throws -> NativeHistorySnapshot {
        guard let text = String(data: try read(notePath), encoding: .utf8) else { throw VaultFailure(message: "The note is not UTF-8.") }
        let note = NoteDocument(path: notePath, content: text, modified: Date())
        let configuration = try historyConfiguration()
        let settings = configuration.bytes, enabled = configuration.enabled, limit = configuration.limit
        guard let noteID = identity ?? note.stableID else { return .init(root: root, note: note, versions: [], records: [:], problems: [], settingsBytes: settings, enabled: enabled, limit: limit) }
        var records: [String: Data] = [:]
        for path in try historyRecordPaths(noteID) { records[path] = try read(path) }
        let decoded = try historyVersions(noteID: noteID, records: records)
        return .init(root: root, note: note, versions: decoded.versions, records: records, problems: decoded.problems, settingsBytes: settings, enabled: enabled, limit: limit)
    }

    func historyVersions(noteID: String, records: [String: Data]) throws -> (versions: [NativeHistoryVersion], problems: [String]) {
        var versions: [NativeHistoryVersion] = [], problems: [String] = []
        for (path, data) in records.sorted(by: { $0.key < $1.key }) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], NativeHistory.integer(object["schema"]) == 1, object["noteId"] as? String == noteID,
                  let id = object["id"] as? String, NativeHistory.identity(id),
                  let time = object["timestamp"] as? String, NativeRevisionIndex.date(time) != nil,
                  let source = object["source"] as? String, let depth = NativeHistory.integer(object["depth"]),
                  let hash = object["resultHash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                  let kind = object["kind"] as? String, ["checkpoint", "delta"].contains(kind),
                  object["parentId"] is NSNull || object["parentId"] is String,
                  let kept = NativeRevisions.boolean(object["kept"]), object["label"] is NSNull || object["label"] is String,
                  object["images"] is [[String: Any]] else { problems.append("\((path as NSString).lastPathComponent): incomplete or unsupported record; its bytes are preserved."); continue }
            versions.append(.init(path: path, bytes: data, id: id, parentID: object["parentId"] as? String, timestamp: time, source: source, kept: kept, label: object["label"] as? String, checkpoint: kind == "checkpoint", depth: depth, hash: hash, content: nil))
        }
        let grouped = Dictionary(grouping: versions, by: \.id)
        var contents: [String: String] = [:], resolving = Set<String>()
        func resolve(_ id: String, depth: Int = 0) throws -> String {
            if let content = contents[id] { return content }
            guard depth < 1024, let rows = grouped[id], rows.count == 1, let version = rows.first, resolving.insert(id).inserted else { throw VaultFailure(message: "Missing, duplicate or circular history parent.") }
            defer { resolving.remove(id) }
            let object = version.object, content: String
            if version.checkpoint { guard let text = object["content"] as? String else { throw VaultFailure(message: "Missing checkpoint.") }; content = text }
            else {
                guard let parentID = version.parentID, let delta = object["delta"] as? [String: Any] else { throw VaultFailure(message: "Missing parent or delta.") }
                let parent = try resolve(parentID, depth: depth + 1)
                guard object["baseHash"] as? String == NativeHistory.hash(parent) else { throw VaultFailure(message: "History parent hash mismatch.") }
                content = try NativeHistory.apply(delta, to: parent)
            }
            guard NativeHistory.hash(content) == version.hash else { throw VaultFailure(message: "History content hash mismatch.") }
            contents[id] = content; return content
        }
        for version in versions { _ = try? resolve(version.id) }
        let children = Set(versions.compactMap(\.parentID))
        let tip = versions.filter { !children.contains($0.id) }.sorted { $0.timestamp > $1.timestamp }.first
        var ancestors = Set<String>(), cursor = tip?.id
        while let id = cursor, ancestors.insert(id).inserted { cursor = grouped[id]?.first?.parentID }
        var blobValidity: [String: Bool] = [:]
        for i in versions.indices {
            versions[i].content = contents[versions[i].id]; versions[i].alternate = !ancestors.contains(versions[i].id)
            versions[i].incomplete = versions[i].content == nil
            if let content = versions[i].content {
                let captured = Set((versions[i].object["images"] as! [[String: Any]]).compactMap { $0["path"] as? String })
                do {
                    for link in try NativeHistory.imageLinks(NoteDocument.split(content).body) where URL(string: link.value)?.scheme == nil {
                        if !captured.contains(link.value) { versions[i].incomplete = true }
                    }
                } catch { versions[i].incomplete = true }
            }
            for image in versions[i].object["images"] as! [[String: Any]] {
                guard let hash = image["hash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                      let path = image["path"] as? String, let url = URL(string: path), url.scheme == nil else { versions[i].incomplete = true; continue }
                if blobValidity[hash] == nil { blobValidity[hash] = (try? historyData(".zerus/history/blobs/" + hash)).map { NativeHistory.hash($0) == hash } ?? false }
                if blobValidity[hash] != true { versions[i].incomplete = true }
            }
        }
        if grouped.values.contains(where: { $0.count > 1 }) { problems.append("Duplicate history identities are preserved; affected versions cannot be restored.") }
        return (versions.sorted { $0.timestamp > $1.timestamp }, problems)
    }

    /// Builds the shared web-compatible history payload in the same journal as
    /// the note. An interrupted save cannot leave a note without its baseline.
    func includingAutomaticHistory(_ original: [VaultFileChange], source: String, observations: [String: NativeHistoryObservation] = [:]) throws -> [VaultFileChange] {
        var result = original, known = Set(original.map(\.path))
        for change in original where (change.before != change.after || observations[change.path] != nil) && (change.path as NSString).pathExtension.lowercased() == "md" && !change.path.hasPrefix(".zerus/history/") {
            guard let beforeData = change.before, let afterData = change.after, let expected = String(data: beforeData, encoding: .utf8), let after = String(data: afterData, encoding: .utf8), let noteID = NoteDocument(path: change.path, content: after, modified: Date()).stableID, NativeHistory.identity(noteID) else { continue }
            let observation = observations[change.path], before = observation?.before.content ?? expected
            guard NativeHistory.stripped(before) != NativeHistory.stripped(after) else { continue }
            let snapshot = try historySnapshot(notePath: change.path, identity: noteID)
            guard snapshot.enabled || source == "restore" else { continue }
            guard snapshot.note.content == expected else { throw VaultFailure(message: "\(change.path) changed outside Zerus. Reload before saving history.") }
            let settingsPath = ".zerus/history-settings.json"
            if known.insert(settingsPath).inserted { result.append(.init(path: settingsPath, before: snapshot.settingsBytes, after: snapshot.settingsBytes)) }
            let latest = snapshot.versions.first { $0.content != nil }
            let alreadyRecorded = observation != nil && latest?.content.map(NativeHistory.stripped) == NativeHistory.stripped(after)
            let beforeKnown = snapshot.versions.contains { $0.content.map(NativeHistory.stripped) == NativeHistory.stripped(before) }
            if alreadyRecorded && (observation?.retrying != true || beforeKnown) {
                for (path, bytes) in snapshot.records where known.insert(path).inserted { result.append(.init(path: path, before: bytes, after: bytes)) }
                continue
            }
            let earlier = snapshot.versions.first { $0.content.map(NativeHistory.stripped) == NativeHistory.stripped(before) }
            var additions: [VaultFileChange] = []
            var blobs = Set<String>()
            func images(_ text: String, historical: Bool) throws -> [[String: Any]] {
                var refs = Set<String>()
                return try NativeHistory.imageLinks(NoteDocument.split(text).body).compactMap { link in
                    guard refs.insert(link.value).inserted, let parsed = URL(string: link.value), parsed.scheme == nil else { return nil }
                    let ext = parsed.pathExtension.lowercased().range(of: #"^[a-z0-9]{1,12}$"#, options: .regularExpression) != nil ? parsed.pathExtension.lowercased() : "bin"
                    if observation != nil && historical {
                        // The file may already contain newer image bytes. Reuse
                        // a verified frozen image, never guess the earlier bytes.
                        if let previous = (earlier?.object["images"] as? [[String: Any]])?.first(where: { $0["path"] as? String == link.value }),
                           let hash = previous["hash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                           let bytes = try historyData(".zerus/history/blobs/" + hash), NativeHistory.hash(bytes) == hash {
                            let path = ".zerus/history/blobs/" + hash
                            if blobs.insert(path).inserted { additions.append(.init(path: path, before: bytes, after: bytes)) }
                            return previous
                        }
                        return ["path": link.value, "hash": NSNull(), "extension": ext]
                    }
                    let candidates = (try? Self.resourceCandidates(link.value, notePath: change.path, root: root)) ?? []
                    guard let location = candidates.first(where: { candidate in
                        let path = String(candidate.path.dropFirst(root.standardizedFileURL.path.count + 1))
                        return FileManager.default.fileExists(atPath: candidate.path) || original.contains(where: { $0.path == path && $0.after != nil })
                    }) else { return ["path": link.value, "hash": NSNull(), "extension": ext] }
                    let relative = String(location.path.dropFirst(root.standardizedFileURL.path.count + 1))
                    // If this transaction replaces an image, preserve each side's bytes.
                    let data: Data
                    if let transaction = original.first(where: { $0.path == relative }) {
                        guard let bytes = text == after ? transaction.after : transaction.before else { return ["path": link.value, "hash": NSNull(), "extension": ext] }
                        data = bytes
                    } else { data = try read(relative) }
                    let hash = NativeHistory.hash(data), path = ".zerus/history/blobs/" + hash
                    let existing = try historyData(path)
                    guard existing == nil || NativeHistory.hash(existing!) == hash else { throw VaultFailure(message: "A history image blob is corrupt. Its data is preserved.") }
                    if blobs.insert(path).inserted { additions.append(.init(path: path, before: existing, after: data)) }
                    if !known.contains(relative), !additions.contains(where: { $0.path == relative }) { let current = try read(relative); additions.append(.init(path: relative, before: current, after: current)) }
                    return ["path": link.value, "hash": hash, "extension": ext]
                }
            }
            let timestamp = NativeRevisionIndex.timestamp(), origin = historyOriginID
            var parent = snapshot.versions.first { $0.hash == NativeHistory.hash(before) && $0.content != nil }
            func entry(_ text: String, id: String, parentID: String?, depth: Int, time: String, baseline: Bool) throws -> NativeHistoryVersion {
                let checkpoint = depth % 3 == 0
                var object: [String: Any] = ["schema": 1, "id": id, "noteId": noteID, "timestamp": time, "source": source, "originId": origin, "parentId": parentID as Any? ?? NSNull(), "depth": depth, "kind": checkpoint ? "checkpoint" : "delta", "baseHash": checkpoint ? NSNull() : NativeHistory.hash(before) as Any, "resultHash": NativeHistory.hash(text), "images": try images(text, historical: baseline), "kept": false, "label": baseline ? "History started" as Any : NSNull()]
                if checkpoint { object["content"] = text } else { object["delta"] = NativeHistory.delta(before, text) }
                let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), path = ".zerus/history/notes/" + noteID + "/" + id + ".json"
                additions.append(.init(path: path, before: nil, after: bytes))
                return .init(path: path, bytes: bytes, id: id, parentID: parentID, timestamp: time, source: source, kept: false, label: baseline ? "History started" : nil, checkpoint: checkpoint, depth: depth, hash: NativeHistory.hash(text), content: text)
            }
            let baselineTime = alreadyRecorded
                ? NativeRevisionIndex.timestamp(min(observation!.before.modified, (latest.flatMap { NativeRevisionIndex.date($0.timestamp) } ?? Date()).addingTimeInterval(-0.001)))
                : timestamp
            if parent == nil { parent = try entry(before, id: UUID().uuidString.lowercased(), parentID: nil, depth: 0, time: baselineTime, baseline: true) }
            let nextTime = NativeRevisionIndex.timestamp(max(Date(), (NativeRevisionIndex.date(parent!.timestamp) ?? Date()).addingTimeInterval(0.001)))
            let next = alreadyRecorded ? nil : try entry(after, id: UUID().uuidString.lowercased(), parentID: parent!.id, depth: parent!.depth + 1, time: nextTime, baseline: false)
            // Use the same checkpoint-family retention contract. Unknown or
            // incomplete records suppress pruning rather than risking loss.
            let all = snapshot.versions + (snapshot.versions.contains(where: { $0.id == parent!.id }) ? [] : [parent!]) + (next.map { [$0] } ?? [])
            if let limit = snapshot.limit, snapshot.problems.isEmpty, !snapshot.versions.contains(where: \.incomplete) {
                let removed = NativeHistory.prunedPaths(all, limit: limit, preserving: source == "restore" || observation != nil ? [parent!.id] : [])
                if !removed.isEmpty, try scan().notes.filter({ $0.stableID == noteID }).count <= 1 {
                    for item in snapshot.versions where removed.contains(item.path) { additions.append(.init(path: item.path, before: item.bytes, after: nil)) }
                }
            }

            // Exact dependencies retain foreign edits and changed ancestry.
            let deleted = Set(additions.filter { $0.after == nil }.map(\.path))
            for (path, bytes) in snapshot.records where !deleted.contains(path) { additions.append(.init(path: path, before: bytes, after: bytes)) }
            for item in additions {
                if known.insert(item.path).inserted { result.append(item) }
                else if let index = result.firstIndex(where: { $0.path == item.path }), result[index].before != item.before || result[index].after != item.after {
                    guard result[index].before == result[index].after, result[index].before == item.before else { throw VaultFailure(message: "History files conflict with another prepared change.") }
                    result[index] = item
                }
            }
        }
        // Publish image blobs and history first, then note pointers.
        return result.filter { ($0.path as NSString).pathExtension.lowercased() != "md" } + result.filter { ($0.path as NSString).pathExtension.lowercased() == "md" }
    }
}

extension VaultFiles {
    func historyPreview(_ version: NativeHistoryVersion) throws -> String {
        guard let content = version.content else { throw VaultFailure(message: "This version has an incomplete parent chain.") }
        var paths: [String: String] = [:]
        for image in version.object["images"] as! [[String: Any]] {
            if let path = image["path"] as? String, let hash = image["hash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil { paths[path] = ".zerus/history/blobs/" + hash }
        }
        let body = NoteDocument.split(content).body
        return NoteDocument.split(content).header + MarkdownMoveLinks.replacing(body, edits: try NativeHistory.imageLinks(body).compactMap { link in
            if let frozen = paths[link.value] { return (link, frozen) }
            guard URL(string: link.value)?.scheme == nil else { return nil }
            // Never make an uncaptured image look historical by reading the
            // current live path. Keep its original spelling in the saved text.
            let unavailable = "zerus-history-unavailable:" + (link.value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "image")
            return (link, unavailable)
        })
    }
    func prepareHistory(_ snapshot: NativeHistorySnapshot, action: NativeHistoryAction) throws -> NativeHistoryPlan {
        guard root == snapshot.root, try read(snapshot.note.path) == Data(snapshot.note.content.utf8), try historyData(".zerus/history-settings.json") == snapshot.settingsBytes else { throw VaultFailure(message: "The note or its history settings changed. Reload history before continuing.") }
        if let id = snapshot.note.stableID {
            guard try historyRecordPaths(id) == Set(snapshot.records.keys) else { throw VaultFailure(message: "History changed. Reload it before continuing.") }
        }
        if case .clear = action, let id = snapshot.note.stableID {
            let maintenance = try prepareHistoryMaintenance(historyMaintenanceSnapshot(), intent: .clearNote(id))
            let records = maintenance.snapshot.records.filter { $0.key.hasPrefix(".zerus/history/notes/" + id + "/") }
            guard records == snapshot.records, maintenance.snapshot.notes.first(where: { $0.path == snapshot.note.path })?.content == snapshot.note.content else { throw VaultFailure(message: "The note or its history changed. Reload before reviewing permanent cleanup.") }
            return .init(snapshot: snapshot, action: action, changes: maintenance.changes, content: nil, maintenance: maintenance)
        }
        var changes = snapshot.records.map { VaultFileChange(path: $0.key, before: $0.value, after: $0.value) }, content: String?
        switch action {
        case .clear:
            changes = snapshot.records.map { .init(path: $0.key, before: $0.value, after: nil) }
        case .update(let id, let kept, let label):
            guard snapshot.versions.filter({ $0.id == id }).count == 1, let version = snapshot.versions.first(where: { $0.id == id }) else { throw VaultFailure(message: "This history identity is missing or ambiguous. Its original records are preserved.") }
            var object = version.object; object["kept"] = kept
            let label = label.trimmingCharacters(in: .whitespacesAndNewlines); object["label"] = label.isEmpty ? NSNull() : label as Any
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            changes = changes.map { $0.path == version.path ? .init(path: $0.path, before: $0.before, after: bytes) : $0 }
        case .restore(let id):
            guard !snapshot.note.trashed, let version = snapshot.versions.first(where: { $0.id == id }), !version.incomplete, var restored = version.content else { throw VaultFailure(message: "This version has missing text or image data and cannot be restored. Its records are preserved.") }
            var replacements: [String: String] = [:]
            for image in version.object["images"] as! [[String: Any]] {
                guard let path = image["path"] as? String, let hash = image["hash"] as? String, hash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { throw VaultFailure(message: "An image snapshot is incomplete.") }
                let blob = ".zerus/history/blobs/" + hash
                guard let bytes = try historyData(blob), NativeHistory.hash(bytes) == hash else { throw VaultFailure(message: "An image snapshot changed or is still syncing. Reload before restoring.") }
                if !changes.contains(where: { $0.path == blob }) { changes.append(.init(path: blob, before: bytes, after: bytes)) }
                let ext = (image["extension"] as? String).flatMap { $0.range(of: #"^[a-z0-9]{1,12}$"#, options: .regularExpression) == nil ? nil : $0 } ?? "bin"
                let target = "assets/restored-" + UUID().uuidString.lowercased() + "." + ext
                changes.append(.init(path: target, before: nil, after: bytes)); replacements[path] = target
            }
            let split = NoteDocument.split(restored)
            restored = split.header + MarkdownMoveLinks.replacing(split.body, edits: try NativeHistory.imageLinks(split.body).compactMap { link in replacements[link.value].map { (link, $0) } })
            content = try NativeHistory.preservingMetadata(restored, current: snapshot.note.content)
        }
        changes.append(.init(path: snapshot.note.path, before: Data(snapshot.note.content.utf8), after: Data((content ?? snapshot.note.content).utf8)))
        changes.append(.init(path: ".zerus/history-settings.json", before: snapshot.settingsBytes, after: snapshot.settingsBytes))
        return .init(snapshot: snapshot, action: action, changes: changes, content: content)
    }
    func applyHistory(_ plan: NativeHistoryPlan) throws -> VaultSnapshot {
        guard root == plan.snapshot.root else { throw VaultFailure(message: "The vault changed. Reopen history.") }
        if let id = plan.snapshot.note.stableID {
            guard try historyRecordPaths(id) == Set(plan.snapshot.records.keys), !(try scan()).notes.contains(where: { $0.path != plan.snapshot.note.path && $0.stableID == id }) else { throw VaultFailure(message: "History changed or this note has a duplicate identity. Reload before continuing.") }
        }
        let source: String
        if case .restore = plan.action { source = "restore" } else { source = "mobile" }
        try applyTransaction(plan.changes, historySource: source, historyCleanupSnapshot: plan.maintenance?.snapshot)
        if let maintenance = plan.maintenance { forgetExternalHistory(maintenance.intent) }
        return try scan()
    }
}
