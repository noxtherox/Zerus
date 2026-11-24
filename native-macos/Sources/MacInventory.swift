import Foundation

extension VaultFiles {
    /// Batch presenter preparation avoids one interprocess negotiation per note.
    /// Each note that changed since the last read (or every note, on a full
    /// read) receives its own coordinated, fresh-byte read. Unchanged notes reuse
    /// the text from that read; see `NativeInventoryCache`.
    func macReadInventory(_ entries: [NativeInventoryEntry]) throws -> [NoteDocument] {
        let cache = NativeInventoryCache.shared, key = root.standardizedFileURL.path, now = Date()
        let full = cache.needsFullRead(root: key, now: now)
        var notes: [NoteDocument?] = Array(repeating: nil, count: entries.count)
        var missing: [Int] = []
        for (index, entry) in entries.enumerated() {
            if !full, let content = cache.content(root: key, entry: entry, now: now) {
                notes[index] = NoteDocument(path: entry.path, content: content, modified: entry.modified, created: entry.created)
            } else { missing.append(index) }
        }
        // Bound preparation so a large vault does not notify all presenters at
        // once. Only the individual accessor holds the read claim for a file.
        for start in stride(from: 0, to: missing.count, by: 256) {
            let batch = missing[start..<min(start + 256, missing.count)]
            let locations = try batch.map { try url(for: entries[$0].path) }
            let coordinator = NSFileCoordinator()
            var preparationError: NSError?
            var result: Result<Void, Error> = .success(())
            coordinator.prepare(forReadingItemsAt: locations, options: [], writingItemsAt: [], options: [], error: &preparationError) { completion in
                defer { completion() }
                result = Result {
                    for (index, location) in zip(batch, locations) {
                        let entry = entries[index]
                        var itemError: NSError?
                        var content: Result<Data, Error> = .failure(VaultFailure(message: "Could not read this file."))
                        coordinator.coordinate(readingItemAt: location, options: [], error: &itemError) { coordinated in
                            content = Result { try Data(contentsOf: coordinated) }
                        }
                        if let itemError { throw itemError }
                        let bytes = try content.get()
                        guard let text = NoteDocument.decodeUTF8(bytes) else {
                            throw VaultFailure(message: "\(entry.path) is not a UTF-8 Markdown file.")
                        }
                        notes[index] = NoteDocument(path: entry.path, content: text, modified: entry.modified, created: entry.created)
                    }
                }
            }
            if let preparationError { throw preparationError }
            try result.get()
        }
        let read = notes.map { $0! }
        cache.store(root: key, entries: entries, notes: read, full: full, now: now)
        return read
    }
}
