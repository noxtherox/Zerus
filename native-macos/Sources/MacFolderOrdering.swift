import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let zerusFolderOrder = UTType(exportedAs: "com.zerus.notes.native.folder-order", conformingTo: .data)
}

struct MacFolderOrderScope: Codable, Equatable, Sendable {
    let workspace: UUID
    let folders: [String]
    let ordered: [String]
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workspace == rhs.workspace && lhs.folders.elementsEqual(rhs.folders, by: MacFolderOrdering.samePath) && lhs.ordered.elementsEqual(rhs.ordered, by: MacFolderOrdering.samePath)
    }
}
struct MacFolderOrderTransfer: Codable, Transferable, Sendable {
    let scope: MacFolderOrderScope
    let source: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .zerusFolderOrder).visibility(.ownProcess)
    }
}

/// Sidebar ordering is local to this Mac and vault, independent of per-window
/// tabs and filters. Children always travel with their folder.
struct MacFolderOrdering {
    let ordered: [String]
    let neighbors: [Data: (previous: String?, next: String?)]
    init(folders: [String], preference: [String]) {
        var ranks: [Data: Int] = [:]
        for (index, folder) in preference.enumerated() where ranks[Data(folder.utf8)] == nil { ranks[Data(folder.utf8)] = index }
        var seen = Set<Data>()
        let unique = folders.filter { !$0.isEmpty && seen.insert(Data($0.utf8)).inserted }
        var children = Dictionary(grouping: unique, by: { Data(Self.parent($0).utf8) })
        var neighbors: [Data: (previous: String?, next: String?)] = [:]
        for (parent, level) in children {
            let sorted = level.sorted { a, b in
                let ar = ranks[Data(a.utf8)] ?? Int.max, br = ranks[Data(b.utf8)] ?? Int.max
                return ar == br ? (a < b || a == b && a.utf8.lexicographicallyPrecedes(b.utf8)) : ar < br
            }
            children[parent] = sorted
            for (index, folder) in sorted.enumerated() { neighbors[Data(folder.utf8)] = (index > 0 ? sorted[index - 1] : nil, index + 1 < sorted.count ? sorted[index + 1] : nil) }
        }
        var result: [String] = []
        func append(_ parent: String) { for child in children[Data(parent.utf8)] ?? [] { result.append(child); append(child) } }
        append("")
        ordered = result; self.neighbors = neighbors
    }
    static func samePath(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
    static func within(_ path: String, _ parent: String) -> Bool { samePath(path, parent) || path.utf8.starts(with: (parent + "/").utf8) }
    static func parent(_ path: String) -> String { path.split(separator: "/").dropLast().joined(separator: "/") }
    static func key(_ root: URL) -> String { "zerus.mac.folderOrder.v1." + NativeHistory.hash(root.resolvingSymlinksInPath().standardizedFileURL.path) }
}
