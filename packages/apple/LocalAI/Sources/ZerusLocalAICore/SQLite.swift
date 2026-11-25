import Foundation
import SQLite3

/// Minimal SQLite wrapper for the local index. Not thread-safe; owned by the
/// `LocalAISearchIndex` actor.
final class SQLiteDatabase {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { "Search index: \(message)" }
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw Failure(message: message)
        }
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;")
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "error"
            sqlite3_free(error)
            throw Failure(message: message)
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    final class Statement {
        fileprivate var raw: OpaquePointer?
        private let db: SQLiteDatabase

        fileprivate init(_ db: SQLiteDatabase, _ sql: String) throws {
            self.db = db
            guard sqlite3_prepare_v2(db.handle, sql, -1, &raw, nil) == SQLITE_OK else {
                throw Failure(message: String(cString: sqlite3_errmsg(db.handle)))
            }
        }

        deinit { sqlite3_finalize(raw) }

        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        @discardableResult
        func bind(_ values: [Any?]) throws -> Statement {
            sqlite3_reset(raw)
            sqlite3_clear_bindings(raw)
            for (i, value) in values.enumerated() {
                let index = Int32(i + 1)
                switch value {
                case nil: sqlite3_bind_null(raw, index)
                case let v as Int: sqlite3_bind_int64(raw, index, Int64(v))
                case let v as Int64: sqlite3_bind_int64(raw, index, v)
                case let v as Double: sqlite3_bind_double(raw, index, v)
                case let v as String: sqlite3_bind_text(raw, index, v, -1, Self.transient)
                case let v as Data:
                    _ = v.withUnsafeBytes { sqlite3_bind_blob(raw, index, $0.baseAddress, Int32(v.count), Self.transient) }
                default: throw Failure(message: "unsupported binding \(type(of: value))")
                }
            }
            return self
        }

        func run() throws {
            let rc = sqlite3_step(raw)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw Failure(message: String(cString: sqlite3_errmsg(db.handle))) }
        }

        /// Steps through rows, calling `row` for each.
        func rows(_ row: (Statement) throws -> Void) throws {
            while true {
                let rc = sqlite3_step(raw)
                if rc == SQLITE_DONE { return }
                guard rc == SQLITE_ROW else { throw Failure(message: String(cString: sqlite3_errmsg(db.handle))) }
                try row(self)
            }
        }

        func string(_ column: Int32) -> String {
            sqlite3_column_text(raw, column).map { String(cString: $0) } ?? ""
        }

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(raw, column)) }

        func data(_ column: Int32) -> Data {
            let count = Int(sqlite3_column_bytes(raw, column))
            guard count > 0, let bytes = sqlite3_column_blob(raw, column) else { return Data() }
            return Data(bytes: bytes, count: count)
        }
    }

    func prepare(_ sql: String) throws -> Statement { try Statement(self, sql) }
}
