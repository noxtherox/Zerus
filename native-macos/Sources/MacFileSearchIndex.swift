import Foundation

struct MacFileSearchIndex: Sendable {
    let files: [NativeSearchFile]
    let indexed: Int
    let filenameOnly: Int
    static let fileLimit = 20 * 1024 * 1024
    static let textLimit = 2 * 1024 * 1024
    static let totalLimit = 32 * 1024 * 1024
    private static let readable = Set(["pdf", "txt", "text", "csv", "tsv", "json", "jsonl", "xml", "html", "htm", "css", "js", "jsx", "ts", "tsx", "swift", "py", "rs", "go", "java", "c", "h", "cpp", "hpp", "m", "mm", "sql", "sh", "zsh", "bash", "yaml", "yml", "toml", "ini", "log", "rtf", "tex", "rst", "md", "markdown"])
    static func build(_ files: [NativeSearchFile], root: URL) async throws -> Self {
        // Four independent coordinated reads keep cloud providers from blocking
        // the main thread or the vault file actor. No index is written to disk.
        let records = try await withThrowingTaskGroup(of: (Int, NativeSearchFile).self) { group in
            var iterator = files.enumerated().makeIterator()
            for _ in 0..<min(4, files.count) { if let (index, file) = iterator.next() { group.addTask { (index, try await read(file, root: root)) } } }
            var records: [(Int, NativeSearchFile)] = [], bytes = 0
            while var record = try await group.next() {
                try Task.checkCancellation()
                if bytes + record.1.content.utf8.count > totalLimit { record.1.content = ""; record.1.issue = "Filename only: the 32 MB search text budget was reached. Use the file’s own search." }
                else { bytes += record.1.content.utf8.count }
                records.append(record)
                if let (index, file) = iterator.next() { group.addTask { (index, try await read(file, root: root)) } }
            }
            return records.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let indexed = records.filter { !$0.content.isEmpty }.count
        return .init(files: records, indexed: indexed, filenameOnly: records.count - indexed)
    }

    private static func read(_ source: NativeSearchFile, root: URL) async throws -> NativeSearchFile {
        var file = source; file.content = ""; file.issue = nil
        guard readable.contains((file.path as NSString).pathExtension.lowercased()) else { file.issue = "Filename only: content search is not available for this format."; return file }
        // RTF is a container, not plain text. Do not index its control words.
        guard (file.path as NSString).pathExtension.lowercased() != "rtf" else { file.issue = "Filename only: rich text document extraction is not available yet."; return file }
        do {
            let url = root.appendingPathComponent(file.path)
            _ = try VaultFiles.confinedPath(for: url, root: root)
            let before = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard before.isSymbolicLink != true, before.isRegularFile == true else { throw VaultFailure(message: "The file is unavailable or is a symbolic link.") }
            guard (before.fileSize ?? Int.max) <= fileLimit else { throw VaultFailure(message: "The file exceeds the 20 MB search read limit.") }
            let document = try await MacChatDocument.prepare(url, maxFileBytes: fileLimit, maxTextBytes: textLimit, timeout: 12, allowedRoot: root)
            try Task.checkCancellation()
            // A replaced link or a changed provider file must not install old text.
            _ = try VaultFiles.confinedPath(for: url, root: root)
            let after = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard after.isSymbolicLink != true, before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else { throw VaultFailure(message: "The file changed while indexing. Refresh to retry.") }
            return .init(path: source.path, modified: after.contentModificationDate ?? source.modified, content: document.text, issue: nil)
        } catch is CancellationError { throw CancellationError() }
        catch { file.issue = "Filename only: " + error.localizedDescription }
        return file
    }
}
