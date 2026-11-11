import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 极简 SQLite 封装。串行队列 + 直连 C API，无第三方依赖。
final class Store {
    static let shared = Store()

    var db: OpaquePointer?
    let queue = DispatchQueue(label: "app.taosheng.db")

    private init() {
        let dir = Store.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("taosheng.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("涛声: 打开数据库失败 \(path)")
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        migrate()
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TaoSheng", isDirectory: true)
    }

    static var audioDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let d = base.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: - 底层

    @discardableResult
    func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let e = err { NSLog("涛声 SQL 错误: \(String(cString: e)) — \(sql)") }
            sqlite3_free(err)
            return false
        }
        return true
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS segment (
            id TEXT PRIMARY KEY,
            started_at REAL NOT NULL,
            ended_at REAL NOT NULL,
            duration REAL NOT NULL,
            file_name TEXT NOT NULL,
            byte_size INTEGER NOT NULL DEFAULT 0,
            transcript TEXT NOT NULL DEFAULT '',
            speaker TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT 'recorded',
            day TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_segment_day ON segment(day, started_at);")
        exec("CREATE INDEX IF NOT EXISTS idx_segment_state ON segment(state);")
        exec("""
        CREATE TABLE IF NOT EXISTS item (
            id TEXT PRIMARY KEY,
            day TEXT NOT NULL,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            due TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'open',
            created_at REAL NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_item_day ON item(day);")
        exec("""
        CREATE TABLE IF NOT EXISTS digest (
            day TEXT PRIMARY KEY,
            summary TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL
        );
        """)
    }

    // MARK: - 段

    func insert(_ s: Segment) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO segment
            (id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, s.id)
            sqlite3_bind_double(st, 2, s.startedAt.timeIntervalSince1970)
            sqlite3_bind_double(st, 3, s.endedAt.timeIntervalSince1970)
            sqlite3_bind_double(st, 4, s.duration)
            bind(st, 5, s.fileName)
            sqlite3_bind_int64(st, 6, Int64(s.byteSize))
            bind(st, 7, s.transcript)
            bind(st, 8, s.speaker)
            bind(st, 9, s.state.rawValue)
            bind(st, 10, s.day)
            sqlite3_bind_double(st, 11, s.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func updateTranscript(id: String, transcript: String, state: SegmentState) {
        queue.sync {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE segment SET transcript=?, state=? WHERE id=?;", -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, transcript)
            bind(st, 2, state.rawValue)
            bind(st, 3, id)
            sqlite3_step(st)
        }
    }

    func deleteSegment(id: String, removeFile: Bool) {
        var name: String?
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT file_name FROM segment WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id)
                if sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) {
                    name = String(cString: c)
                }
            }
            sqlite3_finalize(st)
            var d: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM segment WHERE id=?;", -1, &d, nil) == SQLITE_OK {
                bind(d, 1, id)
                sqlite3_step(d)
            }
            sqlite3_finalize(d)
        }
        if removeFile, let n = name {
            try? FileManager.default.removeItem(at: Store.audioDir.appendingPathComponent(n))
        }
    }

    func segments(day: String? = nil, limit: Int = 500) -> [Segment] {
        queue.sync { () -> [Segment] in
            var sql = "SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at FROM segment"
            if day != nil { sql += " WHERE day=?" }
            sql += " ORDER BY started_at DESC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            if let d = day { bind(st, 1, d) }
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readSegment(st))
            }
            return out
        }
    }

    func pendingSegments(limit: Int = 20) -> [Segment] {
        queue.sync { () -> [Segment] in
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at
            FROM segment WHERE state IN ('recorded','failed') ORDER BY started_at ASC LIMIT \(limit);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSegment(st)) }
            return out
        }
    }

    func dayKeys(limit: Int = 60) -> [String] {
        queue.sync { () -> [String] in
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT day, MAX(started_at) m FROM segment GROUP BY day ORDER BY m DESC LIMIT \(limit);", -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [String] = []
            while sqlite3_step(st) == SQLITE_ROW {
                if let c = sqlite3_column_text(st, 0) { out.append(String(cString: c)) }
            }
            return out
        }
    }

    func search(_ q: String, limit: Int = 100) -> [Segment] {
        let kw = "%\(q)%"
        return queue.sync { () -> [Segment] in
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at
            FROM segment WHERE transcript LIKE ? ORDER BY started_at DESC LIMIT \(limit);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, kw)
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSegment(st)) }
            return out
        }
    }

    func todayStats() -> (segments: Int, transcribed: Int, pending: Int, seconds: Double) {
        let day = DayKey.of(Date())
        return queue.sync { () -> (segments: Int, transcribed: Int, pending: Int, seconds: Double) in
            var st: OpaquePointer?
            var count = 0, transcribed = 0, pending = 0
            var seconds = 0.0
            let sql = "SELECT COUNT(*), SUM(duration), SUM(CASE WHEN state='transcribed' THEN 1 ELSE 0 END), SUM(CASE WHEN state!='transcribed' THEN 1 ELSE 0 END) FROM segment WHERE day=?;"
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                bind(st, 1, day)
                if sqlite3_step(st) == SQLITE_ROW {
                    count = Int(sqlite3_column_int64(st, 0))
                    seconds = sqlite3_column_double(st, 1)
                    transcribed = Int(sqlite3_column_int64(st, 2))
                    pending = Int(sqlite3_column_int64(st, 3))
                }
            }
            sqlite3_finalize(st)
            return (count, transcribed, pending, seconds)
        }
    }

    // MARK: - 条目

    func replaceItems(day: String, items: [DigestItem]) {
        queue.sync {
            var d: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM item WHERE day=?;", -1, &d, nil) == SQLITE_OK {
                bind(d, 1, day)
                sqlite3_step(d)
            }
            sqlite3_finalize(d)
        }
        items.forEach { insert($0) }
    }

    func insert(_ i: DigestItem) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO item (id,day,kind,title,detail,due,status,created_at) VALUES (?,?,?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, i.id)
            bind(st, 2, i.day)
            bind(st, 3, i.kind.rawValue)
            bind(st, 4, i.title)
            bind(st, 5, i.detail)
            bind(st, 6, i.due)
            bind(st, 7, i.status.rawValue)
            sqlite3_bind_double(st, 8, i.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func toggleItem(id: String) {
        queue.sync {
            var st: OpaquePointer?
            let sql = "UPDATE item SET status = CASE WHEN status='open' THEN 'done' ELSE 'open' END WHERE id=?;"
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func items(day: String? = nil, openOnly: Bool = false) -> [DigestItem] {
        queue.sync { () -> [DigestItem] in
            var sql = "SELECT id,day,kind,title,detail,due,status,created_at FROM item"
            var conds: [String] = []
            if day != nil { conds.append("day=?") }
            if openOnly { conds.append("status='open'") }
            if !conds.isEmpty { sql += " WHERE " + conds.joined(separator: " AND ") }
            sql += " ORDER BY CASE kind WHEN 'todo' THEN 0 WHEN 'promise' THEN 1 WHEN 'event' THEN 2 ELSE 3 END, created_at DESC;"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            if let d = day { bind(st, 1, d) }
            var out: [DigestItem] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(DigestItem(
                    id: col(st, 0),
                    day: col(st, 1),
                    kind: ItemKind(rawValue: col(st, 2)) ?? .event,
                    title: col(st, 3),
                    detail: col(st, 4),
                    due: col(st, 5),
                    status: ItemStatus(rawValue: col(st, 6)) ?? .open,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 7))
                ))
            }
            return out
        }
    }

    func saveDigest(day: String, summary: String) {
        queue.sync {
            var st: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO digest (day,summary,created_at) VALUES (?,?,?);"
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                bind(st, 1, day)
                bind(st, 2, summary)
                sqlite3_bind_double(st, 3, Date().timeIntervalSince1970)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func digest(day: String) -> DigestRecord? {
        queue.sync { () -> DigestRecord? in
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT day,summary,created_at FROM digest WHERE day=?;", -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            bind(st, 1, day)
            if sqlite3_step(st) == SQLITE_ROW {
                return DigestRecord(day: col(st, 0), summary: col(st, 1), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)))
            }
            return nil
        }
    }

    // MARK: - 助手

    func bind(_ st: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(st, idx, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    func col(_ st: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(st, idx) else { return "" }
        return String(cString: c)
    }

    private func readSegment(_ st: OpaquePointer?) -> Segment {
        Segment(
            id: col(st, 0),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)),
            endedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
            duration: sqlite3_column_double(st, 3),
            fileName: col(st, 4),
            byteSize: Int(sqlite3_column_int64(st, 5)),
            transcript: col(st, 6),
            speaker: col(st, 7),
            state: SegmentState(rawValue: col(st, 8)) ?? .recorded,
            day: col(st, 9),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 10))
        )
    }
}
