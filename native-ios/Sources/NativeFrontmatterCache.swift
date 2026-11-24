import Foundation

/// Shared by the iOS and Mac apps. Note values are immutable snapshots between edits. Share their parsed
/// metadata across collection, sidebar and editor reads without retaining an
/// unbounded vault. NSData keys compare exact UTF-8, including BOMs and Unicode
/// spellings; Swift String equality would merge canonically equivalent bytes.
enum NativeFrontmatterCache {
    private final class Parsed: NSObject {
        let value: NativeFrontmatter
        private let lock = NSLock()
        private var split: (header: String, body: String)?
        init(_ text: String) { value = NativeFrontmatter(text) }
        func parts() -> (header: String, body: String) {
            lock.lock(); defer { lock.unlock() }
            if let split { return split }
            let result = (header: value.header, body: value.body)
            split = result
            return result
        }
    }
    private static let cache: NSCache<NSData, Parsed> = {
        let cache = NSCache<NSData, Parsed>()
        cache.countLimit = 4096
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private static func parsed(_ text: String) -> Parsed {
        guard text.utf8.count <= 2 * 1024 * 1024 else { return Parsed(text) }
        let bytes = Data(text.utf8)
        let key = bytes as NSData
        if let parsed = cache.object(forKey: key) { return parsed }
        let parsed = Parsed(text)
        cache.setObject(parsed, forKey: key, cost: bytes.count * 4)
        return parsed
    }
    static func read(_ text: String) -> NativeFrontmatter {
        guard text.utf8.count <= 2 * 1024 * 1024 else { return NativeFrontmatter(text) }
        return parsed(text).value
    }
    /// Share immutable substrings too: rebuilding them through NSString on
    /// every title/editor read otherwise scales with the complete note body.
    static func parts(_ text: String) -> (header: String, body: String) { parsed(text).parts() }

}
