import Foundation
import CryptoKit

/// On-device o200k_base BPE. Ordinary text never becomes a control/special token.
/// The bundled rank data is MIT licensed; see ThirdPartyNotices.txt.
actor NativeAgentTokenizer {
    static let shared = NativeAgentTokenizer()
    private var ranks: [Data: Int] = [:]
    private var pattern: NSRegularExpression?
    private struct Metadata: Decodable { let version: Int; let encoding: String; let sha256: String; let count: Int; let pattern: String }
    private static let problem = VaultFailure(message: "The native token counter is unavailable. Its resources must be restored before sending this AI request.")

    private func load() throws {
        guard pattern == nil else { return }
        guard let dataURL = Bundle.main.url(forResource: "NativeO200k", withExtension: "bin"), let metadataURL = Bundle.main.url(forResource: "NativeO200k", withExtension: "json") else { throw Self.problem }
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL)), data = try Data(contentsOf: dataURL)
        guard metadata.version == 1, metadata.encoding == "o200k_base", metadata.count == 199998,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == metadata.sha256,
              data.count >= 12, data.prefix(8) == Data("ZTOK200K".utf8) else { throw Self.problem }
        let bytes = [UInt8](data)
        guard (0..<4).reduce(0, { $0 | Int(bytes[8 + $1]) << ($1 * 8) }) == metadata.count else { throw Self.problem }
        var offset = 12, loaded: [Data: Int] = [:]; loaded.reserveCapacity(metadata.count)
        for rank in 0..<metadata.count {
            if rank % 4096 == 0 { try Task.checkCancellation() }
            guard offset + 2 <= bytes.count else { throw Self.problem }
            let length = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8; offset += 2
            guard length > 0, offset + length <= bytes.count else { throw Self.problem }
            let token = Data(bytes[offset..<(offset + length)]); offset += length
            guard loaded.updateValue(rank, forKey: token) == nil else { throw Self.problem }
        }
        guard offset == bytes.count, (0..<256).allSatisfy({ loaded[Data([UInt8($0)])] != nil }) else { throw Self.problem }
        let expression = try NSRegularExpression(pattern: metadata.pattern)
        ranks = loaded; pattern = expression
    }
    func count(_ text: String) throws -> Int {
        try load(); try Task.checkCancellation()
        let string = text as NSString, matches = pattern!.matches(in: text, range: NSRange(location: 0, length: string.length))
        var total = 0, cursor = 0
        for match in matches {
            try Task.checkCancellation()
            guard match.range.location == cursor, match.range.length > 0 else { throw Self.problem }
            let piece = Data(string.substring(with: match.range).utf8)
            total += ranks[piece] == nil ? try mergedCount(piece) : 1
            cursor = NSMaxRange(match.range)
        }
        guard cursor == string.length else { throw Self.problem }; return total
    }
    private struct Pair {
        let rank: Int; let left: Int; let right: Int; let leftEnd: Int; let rightEnd: Int
        func precedes(_ other: Self) -> Bool { rank == other.rank ? left < other.left : rank < other.rank }
    }
    private func mergedCount(_ data: Data) throws -> Int {
        let bytes = [UInt8](data), n = bytes.count
        guard n > 1 else { return n }
        var ends = Array(1...n), next = Array(1...n), previous = Array(-1..<(n - 1)), heap: [Pair] = []
        func offer(_ left: Int) {
            guard left >= 0, left < n, next[left] < n, next[left] >= 0 else { return }
            let right = next[left]
            guard let rank = ranks[Data(bytes[left..<ends[right]])] else { return }
            heap.append(.init(rank: rank, left: left, right: right, leftEnd: ends[left], rightEnd: ends[right]))
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard heap[index].precedes(heap[parent]) else { break }; heap.swapAt(index, parent); index = parent
            }
        }
        func pop() -> Pair? {
            guard !heap.isEmpty else { return nil }
            let first = heap[0], last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last; var index = 0
                while index * 2 + 1 < heap.count {
                    var child = index * 2 + 1
                    if child + 1 < heap.count, heap[child + 1].precedes(heap[child]) { child += 1 }
                    guard heap[child].precedes(heap[index]) else { break }; heap.swapAt(child, index); index = child
                }
            }
            return first
        }
        for index in 0..<(n - 1) { if index % 512 == 0 { try Task.checkCancellation() }; offer(index) }
        var count = n, iterations = 0
        while let pair = pop() {
            iterations += 1; if iterations % 512 == 0 { try Task.checkCancellation() }
            let left = pair.left, right = pair.right
            guard next[left] == right, ends[left] == pair.leftEnd, ends[right] == pair.rightEnd else { continue }
            ends[left] = ends[right]; next[left] = next[right]
            if next[right] < n { previous[next[right]] = left }
            next[right] = -1; previous[right] = -1; count -= 1
            offer(previous[left]); offer(left)
        }
        return count
    }
}
