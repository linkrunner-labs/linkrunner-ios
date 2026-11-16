import Foundation
import SQLite3

/// A request waiting to be sent. The payload never contains the project token.
struct QueuedRequest: Equatable, Sendable {
    let id: Int64
    let kind: String
    let payload: String
    let createdAt: Int64
    let attempts: Int
    let nextAttemptAt: Int64
    let priority: Int
}

/// Durable FIFO of SDK requests backed by SQLite, with a bounded in-memory fallback.
final class EventQueueStore: @unchecked Sendable {
    static let maxRows = 5_000
    static let maxBytes = 5 * 1024 * 1024
    static let maxMemoryRows = 500
    static let ttlMs: Int64 = 7 * 24 * 60 * 60 * 1000

    static let priorityHigh = 0
    static let priorityLow = 1

    private let fileURLProvider: @Sendable () -> URL?
    private let rowLimit: Int
    private let byteLimit: Int
    private let memoryRowLimit: Int
    private let lock = NSLock()
    private var db: OpaquePointer?
    private var openAttempted = false
    private var memory: [QueuedRequest] = []
    private var nextMemoryId: Int64 = -1

    /// The path is resolved on first use; nil keeps everything in memory.
    init(fileURL: @escaping @Sendable () -> URL?, maxRows: Int = maxRows, maxBytes: Int = maxBytes, maxMemoryRows: Int = maxMemoryRows) {
        self.fileURLProvider = fileURL
        self.rowLimit = maxRows
        self.byteLimit = maxBytes
        self.memoryRowLimit = maxMemoryRows
    }

    convenience init(fileURL: URL?, maxRows: Int = maxRows, maxBytes: Int = maxBytes, maxMemoryRows: Int = maxMemoryRows) {
        self.init(fileURL: { fileURL }, maxRows: maxRows, maxBytes: maxBytes, maxMemoryRows: maxMemoryRows)
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    static func defaultFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        var dir = support.appendingPathComponent("Linkrunner", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("request_queue.sqlite")
    }

    var isPersistent: Bool {
        lock.lock(); defer { lock.unlock() }
        return openIfNeeded() != nil
    }

    // MARK: - Writes

    @discardableResult
    func insert(kind: String, payload: String, priority: Int, now: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let db = openIfNeeded() else {
            insertInMemory(kind: kind, payload: payload, priority: priority, now: now)
            return true
        }
        enforceCaps(db: db, incomingBytes: payload.utf8.count)
        let sql = "INSERT INTO queue (kind, payload, created_at, attempts, next_attempt_at, priority) VALUES (?, ?, ?, 0, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            failOver()
            insertInMemory(kind: kind, payload: payload, priority: priority, now: now)
            return true
        }
        bindText(stmt, 1, kind)
        bindText(stmt, 2, payload)
        sqlite3_bind_int64(stmt, 3, now)
        sqlite3_bind_int64(stmt, 4, now)
        sqlite3_bind_int(stmt, 5, Int32(priority))
        if sqlite3_step(stmt) != SQLITE_DONE {
            failOver()
            insertInMemory(kind: kind, payload: payload, priority: priority, now: now)
        }
        return true
    }

    func delete(id: Int64) {
        lock.lock(); defer { lock.unlock() }
        if id < 0 {
            memory.removeAll { $0.id == id }
            return
        }
        guard let db = openIfNeeded() else { return }
        execute(db, "DELETE FROM queue WHERE id = \(id)")
    }

    func scheduleRetry(id: Int64, attempts: Int, nextAttemptAt: Int64) {
        lock.lock(); defer { lock.unlock() }
        if id < 0 {
            if let i = memory.firstIndex(where: { $0.id == id }) {
                let r = memory[i]
                memory[i] = QueuedRequest(id: r.id, kind: r.kind, payload: r.payload, createdAt: r.createdAt,
                                          attempts: attempts, nextAttemptAt: nextAttemptAt, priority: r.priority)
            }
            return
        }
        guard let db = openIfNeeded() else { return }
        execute(db, "UPDATE queue SET attempts = \(attempts), next_attempt_at = \(nextAttemptAt) WHERE id = \(id)")
    }

    /// Makes every row due now, keeping its attempt count.
    func resetBackoff(now: Int64) {
        lock.lock(); defer { lock.unlock() }
        memory = memory.map {
            QueuedRequest(id: $0.id, kind: $0.kind, payload: $0.payload, createdAt: $0.createdAt,
                          attempts: $0.attempts, nextAttemptAt: min($0.nextAttemptAt, now), priority: $0.priority)
        }
        guard let db = openIfNeeded() else { return }
        execute(db, "UPDATE queue SET next_attempt_at = \(now) WHERE next_attempt_at > \(now)")
    }

    @discardableResult
    func purgeExpired(now: Int64) -> Int {
        lock.lock(); defer { lock.unlock() }
        let cutoff = now - Self.ttlMs
        let before = memory.count
        memory.removeAll { $0.createdAt < cutoff }
        var removed = before - memory.count
        guard let db = openIfNeeded() else { return removed }
        execute(db, "DELETE FROM queue WHERE created_at < \(cutoff)")
        removed += Int(sqlite3_changes(db))
        return removed
    }

    // MARK: - Reads

    /// Oldest row overall, or the oldest row of `kind` when given. Memory rows come after disk rows.
    func first(kind: String? = nil) -> QueuedRequest? {
        lock.lock(); defer { lock.unlock() }
        if let db = openIfNeeded() {
            var sql = "SELECT id, kind, payload, created_at, attempts, next_attempt_at, priority FROM queue"
            if kind != nil { sql += " WHERE kind = ?" }
            sql += " ORDER BY id ASC LIMIT 1"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if let kind = kind { bindText(stmt, 1, kind) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    return QueuedRequest(
                        id: sqlite3_column_int64(stmt, 0),
                        kind: String(cString: sqlite3_column_text(stmt, 1)),
                        payload: String(cString: sqlite3_column_text(stmt, 2)),
                        createdAt: sqlite3_column_int64(stmt, 3),
                        attempts: Int(sqlite3_column_int(stmt, 4)),
                        nextAttemptAt: sqlite3_column_int64(stmt, 5),
                        priority: Int(sqlite3_column_int(stmt, 6))
                    )
                }
            }
        }
        return memory.first { kind == nil || $0.kind == kind }
    }

    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        var total = memory.count
        if let db = openIfNeeded() {
            total += Int(scalar(db, "SELECT COUNT(*) FROM queue"))
        }
        return total
    }

    // MARK: - Internals

    private func openIfNeeded() -> OpaquePointer? {
        if let db = db { return db }
        guard !openAttempted else { return nil }
        openAttempted = true
        guard let fileURL = fileURLProvider() else { return nil }
        if let handle = open(fileURL) { db = handle; return handle }
        // An unreadable file is recreated once; a second failure stays in memory.
        removeFiles(fileURL)
        if let handle = open(fileURL) { db = handle; return handle }
        return nil
    }

    private func open(_ url: URL) -> OpaquePointer? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let db = handle else {
            if let handle = handle { sqlite3_close(handle) }
            return nil
        }
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL,
            priority INTEGER NOT NULL
        );
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK,
              quickCheckPasses(db) else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func quickCheckPasses(_ db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              let text = sqlite3_column_text(stmt, 0) else { return false }
        return String(cString: text) == "ok"
    }

    private func removeFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    /// Moves to memory for the rest of the process after a failed disk write.
    private func failOver() {
        if let handle = db { sqlite3_close(handle) }
        db = nil
    }

    private func insertInMemory(kind: String, payload: String, priority: Int, now: Int64) {
        if memory.count >= memoryRowLimit {
            if let i = memory.firstIndex(where: { $0.priority == Self.priorityLow }) {
                memory.remove(at: i)
            } else {
                memory.removeFirst()
            }
        }
        memory.append(QueuedRequest(id: nextMemoryId, kind: kind, payload: payload, createdAt: now,
                                    attempts: 0, nextAttemptAt: now, priority: priority))
        nextMemoryId -= 1
    }

    private func enforceCaps(db: OpaquePointer, incomingBytes: Int) {
        var rows = Int(scalar(db, "SELECT COUNT(*) FROM queue"))
        var bytes = Int(scalar(db, "SELECT COALESCE(SUM(LENGTH(payload)), 0) FROM queue"))
        while rows > 0 && (rows + 1 > rowLimit || bytes + incomingBytes > byteLimit) {
            var victim = scalar(db, "SELECT id FROM queue WHERE priority = \(Self.priorityLow) ORDER BY id ASC LIMIT 1")
            if victim == 0 {
                victim = scalar(db, "SELECT id FROM queue ORDER BY id ASC LIMIT 1")
            }
            guard victim != 0 else { return }
            let size = Int(scalar(db, "SELECT LENGTH(payload) FROM queue WHERE id = \(victim)"))
            execute(db, "DELETE FROM queue WHERE id = \(victim)")
            rows -= 1
            bytes -= size
        }
    }

    private func scalar(_ db: OpaquePointer, _ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, Self.transient)
    }
}
