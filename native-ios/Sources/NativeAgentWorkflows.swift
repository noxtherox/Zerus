import Foundation

struct NativeAgentWorkflow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let instructions: String
    static let directory = ".zerus/ai/workflows"
    static let builtins: [Self] = [
        .init(id: "meeting", title: "Clean up meeting notes", instructions: "Find the meeting notes in scope. Preserve decisions, names and dates. Organize discussion, decisions, questions and action items into clear sections. Do not invent owners or deadlines. Patch existing notes and verify the result."),
        .init(id: "synthesis", title: "Synthesize related notes", instructions: "Search and read the relevant notes completely using ranged reads. Compare agreements, disagreements and gaps. Create a source-linked synthesis note in the permitted type. Cite actual notes and identify incomplete coverage."),
        .init(id: "duplicates", title: "Review duplicate notes", instructions: "Search for duplicate or overlapping notes. Read each candidate. Prepare a merged note that preserves unique content and stable links. Propose patches to referring notes and archive redundant notes only after a concrete review. Verify every changed reference."),
        .init(id: "weekly", title: "Review this week", instructions: "Review notes and their updated dates in scope. Summarize decisions, progress, outstanding questions and existing action items. Create a dated review with links to sources. Do not invent completion, dates or task owners.")
    ]
    static func customPath(_ id: String) -> Bool {
        id.hasPrefix(directory + "/") && id.hasSuffix(".md") && id.utf8.count <= 1024 && !id.contains("\\") &&
        !id.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
    func validate() throws {
        guard (Self.builtins.contains { $0.id == id } || Self.customPath(id)), !title.isEmpty, title.utf16.count <= 12_000, instructions.utf16.count <= 12_000 else { throw VaultFailure(message: "This saved workflow is unsupported. Its original journal is kept.") }
    }
    static func sourcePrefix(_ source: String) -> String {
        let units = source.utf16
        guard units.count > 12_000 else { return source }
        var end = units.index(units.startIndex, offsetBy: 12_000)
        // Keep the shared UTF-16 bound, without creating an invalid surrogate.
        if (0xDC00...0xDFFF).contains(units[end]) { end = units.index(before: end) }
        return String(decoding: units[..<end], as: UTF16.self)
    }
    static func custom(_ id: String, source: String) -> Self {
        let prefix = sourcePrefix(source), range = NSRange(prefix.startIndex..., in: prefix)
        let match = try? NSRegularExpression(pattern: "^#\\s+(.+)$", options: .anchorsMatchLines).firstMatch(in: prefix, range: range)
        let title = match.flatMap { Range($0.range(at: 1), in: prefix) }.map { String(prefix[$0]).trimmingCharacters(in: .newlines) } ?? URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
        return .init(id: id, title: title, instructions: prefix)
    }
    static func selectedID(_ bytes: Data?) throws -> String {
        guard let bytes else { return "" }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String:Any] else { throw VaultFailure(message: "AI settings must be a JSON object. Their original bytes are kept.") }
        guard let raw = object["workflow"] else { return "" }
        guard let id = raw as? String, id.utf8.count <= 1024 else { throw VaultFailure(message: "The saved workflow selection is unsupported. Correct AI settings in Files; their original bytes are kept.") }
        return id
    }
}

struct NativeAgentWorkflowDocument: Identifiable, Sendable {
    let root: URL
    let id: String
    let bytes: Data?
    let source: String
    var workflow: NativeAgentWorkflow { .custom(id, source: source) }
}
struct NativeAgentWorkflowCatalog: Sendable {
    let root: URL
    let settingsBytes: Data?
    let selectedID: String
    let custom: [NativeAgentWorkflowDocument]
    let notices: [String]
    var workflows: [NativeAgentWorkflow] { NativeAgentWorkflow.builtins + custom.map(\.workflow) }
}
private final class NativeAgentWorkflowListing: @unchecked Sendable {
    var paths: [String] = []
    var notices: [String] = []
}

extension VaultFiles {
    func agentWorkflowDocument(_ id: String) throws -> NativeAgentWorkflowDocument {
        guard NativeAgentWorkflow.customPath(id) else { throw VaultFailure(message: "Choose an ordinary Markdown file inside this vault’s AI workflows folder.") }
        guard let bytes = try agentMetadata([(id, 256_000)])[0], let source = String(data: bytes, encoding: .utf8) else { throw VaultFailure(message: "This workflow is missing or is not readable UTF-8 Markdown. Its original file is kept; reload or choose another workflow.") }
        return .init(root: root, id: id, bytes: bytes, source: source)
    }
    func agentSelectedWorkflow(settings: Data?) throws -> NativeAgentWorkflow? {
        let id = try NativeAgentWorkflow.selectedID(settings)
        guard !id.isEmpty else { return nil }
        if let builtin = NativeAgentWorkflow.builtins.first(where: { $0.id == id }) { return builtin }
        let workflow = try agentWorkflowDocument(id).workflow; try workflow.validate(); return workflow
    }
    func agentWorkflows() throws -> NativeAgentWorkflowCatalog {
        let settings = try agentMetadata([(".zerus/ai/settings.json", 256_000)])[0], selected = try NativeAgentWorkflow.selectedID(settings)
        let folder = try url(for: NativeAgentWorkflow.directory), result = NativeAgentWorkflowListing(), root = root
        try Self.coordinateTransaction(locations: [folder], root: root, reading: [0]) { urls in
            let folder = urls[0]
            guard FileManager.default.fileExists(atPath: folder.path) else { return }
            let folderPath = try Self.confinedPath(for: folder, root: root)
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw VaultFailure(message: "The AI workflows folder must be an ordinary folder. Its original files are kept.") }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
            guard let iterator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, error in result.notices.append("Some workflows could not be listed: " + error.localizedDescription); return false }) else { throw VaultFailure(message: "Could not list this vault’s workflows. Try again when its files are available.") }
            var visited = 0
            for case let location as URL in iterator {
                try Task.checkCancellation(); visited += 1
                if visited > 512 { result.notices.append("The workflow folder is large. Only the first 512 entries were inspected; a saved selection is opened separately."); break }
                let values = try location.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true { iterator.skipDescendants(); result.notices.append("A linked workflow entry was skipped: " + location.lastPathComponent); continue }
                // Device coordination can return /private/var for a /var root.
                // Compare canonical paths, retaining the ordinary relative file ID.
                let path = try Self.confinedPath(for: location, root: root)
                guard path.hasPrefix(folderPath + "/") else { iterator.skipDescendants(); continue }
                let suffix = String(path.dropFirst(folderPath.count + 1))
                if iterator.level > 8 { iterator.skipDescendants(); result.notices.append("A deeply nested workflow folder was skipped."); continue }
                if values.isRegularFile == true, suffix.hasSuffix(".md") { result.paths.append(NativeAgentWorkflow.directory + "/" + suffix) }
            }
        }
        let sorted = result.paths.sorted()
        var paths = Array(sorted.prefix(30))
        if sorted.count > 30 { result.notices.append("Showing the first 30 custom workflows. The saved selection is also included when available.") }
        if NativeAgentWorkflow.customPath(selected), !paths.contains(selected) { paths.append(selected) }
        var documents: [NativeAgentWorkflowDocument] = []
        for id in paths {
            do { documents.append(try agentWorkflowDocument(id)) }
            catch { if error is CancellationError { throw error }; result.notices.append(id + ": " + error.localizedDescription) }
        }
        return .init(root: root, settingsBytes: settings, selectedID: selected, custom: documents, notices: result.notices)
    }
    func saveAgentWorkflowSelection(_ id: String, expected: NativeAgentWorkflowCatalog) throws -> NativeAgentWorkflowCatalog {
        guard expected.root == root else { throw VaultFailure(message: "These workflows belong to another vault. Reopen its workflow settings.") }
        guard id.isEmpty || expected.workflows.contains(where: { $0.id == id }) else { throw VaultFailure(message: "Reload workflows before choosing this item. Its file is kept.") }
        var bytes = expected.settingsBytes
        if id != expected.selectedID {
            var object: [String:Any] = [:]
            if let original = expected.settingsBytes {
                guard let decoded = try JSONSerialization.jsonObject(with: original) as? [String:Any] else { throw VaultFailure(message: "AI settings changed format. Their original bytes are kept.") }
                object = decoded
            }
            object["workflow"] = id
            bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
            guard bytes!.count <= 256_000 else { throw VaultFailure(message: "AI settings are too large. Their original bytes are kept.") }
        }
        var changes = [VaultFileChange(path: ".zerus/ai/settings.json", before: expected.settingsBytes, after: bytes)]
        if let document = expected.custom.first(where: { $0.id == id }) { changes.append(.init(path: id, before: document.bytes, after: document.bytes)) }
        try applyTransaction(changes, historySource: "ai-settings")
        return .init(root: root, settingsBytes: bytes, selectedID: id, custom: expected.custom, notices: expected.notices)
    }
    func newAgentWorkflow(title: String) throws -> NativeAgentWorkflowDocument {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf16.count <= 100, !title.contains("\n"), !title.contains("\r") else { throw VaultFailure(message: "Give this workflow a one-line name within 100 characters.") }
        let id = NativeAgentWorkflow.directory + "/workflow-" + UUID().uuidString.lowercased() + ".md"
        return .init(root: root, id: id, bytes: nil, source: "# " + title + "\n\n")
    }
    func saveAgentWorkflow(_ source: String, expected: NativeAgentWorkflowDocument) throws -> NativeAgentWorkflowDocument {
        guard expected.root == root, NativeAgentWorkflow.customPath(expected.id) else { throw VaultFailure(message: "This workflow belongs to another vault. Reopen it before saving.") }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.utf16.count <= 12_000 else { throw VaultFailure(message: "Keep this workflow within 12,000 characters. Its original file and your draft are kept.") }
        let bytes = source == expected.source && expected.bytes != nil ? expected.bytes! : Data(source.utf8)
        try applyTransaction([.init(path: expected.id, before: expected.bytes, after: bytes)], historySource: "ai-workflow")
        return .init(root: root, id: expected.id, bytes: bytes, source: source)
    }
}
