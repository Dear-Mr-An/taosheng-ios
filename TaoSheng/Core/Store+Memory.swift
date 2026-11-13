import Foundation
import SQLite3

// MARK: - 记忆层（事件 / 提取项 / 技能卡 / 寻物）

extension Store {

    func migrateMemory() {
        queue.sync { () -> Void in
            exec("""
            CREATE TABLE IF NOT EXISTS memory_event (
                id TEXT PRIMARY KEY,
                day TEXT NOT NULL,
                start_at REAL NOT NULL,
                end_at REAL,
                scene TEXT NOT NULL DEFAULT '其他',
                title TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '',
                points_json TEXT NOT NULL DEFAULT '[]',
                people_json TEXT NOT NULL DEFAULT '[]',
                place TEXT,
                emotion TEXT NOT NULL DEFAULT '平静',
                intensity INTEGER NOT NULL DEFAULT 3,
                important INTEGER NOT NULL DEFAULT 0,
                starred INTEGER NOT NULL DEFAULT 0,
                starred_at REAL,
                entity_id TEXT,
                line_from INTEGER NOT NULL DEFAULT 0,
                line_to INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_ev_day ON memory_event(day);")
            exec("CREATE INDEX IF NOT EXISTS idx_ev_start ON memory_event(start_at);")

            exec("""
            CREATE TABLE IF NOT EXISTS memory_item (
                id TEXT PRIMARY KEY,
                event_id TEXT,
                day TEXT NOT NULL,
                category TEXT NOT NULL,
                kind TEXT,
                content TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                due_text TEXT,
                due_at REAL,
                who TEXT,
                source_text TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_it_day ON memory_item(day);")
            exec("CREATE INDEX IF NOT EXISTS idx_it_status ON memory_item(status);")

            exec("""
            CREATE TABLE IF NOT EXISTS skill_card (
                id TEXT PRIMARY KEY,
                skill_id TEXT NOT NULL,
                skill_name TEXT NOT NULL,
                day TEXT NOT NULL,
                start_at REAL,
                end_at REAL,
                entity_id TEXT,
                fields_json TEXT NOT NULL DEFAULT '{}',
                quotes_json TEXT NOT NULL DEFAULT '[]',
                nothing_reason TEXT,
                created_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_card_day ON skill_card(day);")

            exec("""
            CREATE TABLE IF NOT EXISTS thing (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                aliases_json TEXT NOT NULL DEFAULT '[]',
                owner TEXT NOT NULL DEFAULT 'Mine',
                place TEXT,
                holder TEXT,
                updated_at REAL NOT NULL,
                created_at REAL NOT NULL
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS thing_fact (
                id TEXT PRIMARY KEY,
                thing_id TEXT NOT NULL,
                action TEXT NOT NULL,
                place TEXT,
                who TEXT,
                line_id TEXT,
                confident INTEGER NOT NULL DEFAULT 1,
                at REAL NOT NULL,
                created_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_fact_thing ON thing_fact(thing_id);")

            exec("""
            CREATE TABLE IF NOT EXISTS env_tag (
                segment_id TEXT PRIMARY KEY,
                tag TEXT NOT NULL,
                at REAL NOT NULL
            );
            """)

            ensureColumn(table: "segment", column: "capture_mode", ddl: "ALTER TABLE segment ADD COLUMN capture_mode TEXT NOT NULL DEFAULT 'daily';")
            ensureColumn(table: "segment", column: "digested", ddl: "ALTER TABLE segment ADD COLUMN digested INTEGER NOT NULL DEFAULT 0;")
            ensureColumn(table: "segment", column: "bigram", ddl: "ALTER TABLE segment ADD COLUMN bigram TEXT NOT NULL DEFAULT '';")
        ensureColumn(table: "memory_event", column: "edited", ddl: "ALTER TABLE memory_event ADD COLUMN edited INTEGER NOT NULL DEFAULT 0;")
        }
    }

    // MARK: 环境音标签

    func setEnvTag(segmentId: String, tag: String) {
        queue.sync { () -> Void in
            // 用参数绑定，别拼字符串：段 id 里出现单引号会让整条 SQL 失败
            let sql = "INSERT OR REPLACE INTO env_tag (segment_id,tag,at) VALUES (?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, segmentId)
            bind(st, 2, tag)
            sqlite3_bind_double(st, 3, Date().timeIntervalSince1970)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func envTags(day: String) -> [String: String] {
        queue.sync { () -> [String: String] in
            var out: [String: String] = [:]
            let sql = """
            SELECT e.segment_id, e.tag FROM env_tag e
            JOIN segment s ON s.id = e.segment_id
            WHERE s.day = ?;
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let q = st else { return out }
            bind(q, 1, day)
            while sqlite3_step(q) == SQLITE_ROW {
                let key = col(q, 0)
                let val = col(q, 1)
                out[key] = val
            }
            sqlite3_finalize(q)
            return out
        }
    }

    // MARK: 事件

    func upsertEvent(_ e: MemoryEvent) {
        queue.sync { () -> Void in
            let sql = """
            INSERT OR REPLACE INTO memory_event
            (id,day,start_at,end_at,scene,title,summary,points_json,people_json,place,emotion,intensity,important,starred,starred_at,entity_id,line_from,line_to,deleted,created_at,edited)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            // 同一段原话被重新整理时，entity_id 不变 —— 复用旧行的 id，
            // 否则「重新整理」会把同一件事再插一遍，时间线翻倍。
            var eventID = e.id
            var keepStarred = e.starred
            var keepStarredAt = e.starredAt
            // INSERT OR REPLACE 是「删掉整行再插入」，edited 不在列清单里就会被重置成 0，
            // 于是用户手改过的标题/摘要下一次自动整理又被覆盖 —— 这里连 title/summary 一起保住。
            var keepEdited = false
            var keepTitle = e.title
            var keepSummary = e.summary
            if let en = e.entityId, !en.isEmpty {
                var q: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT id,starred,starred_at,edited,title,summary FROM memory_event WHERE entity_id=? AND deleted=0 LIMIT 1;", -1, &q, nil) == SQLITE_OK {
                    bind(q, 1, en)
                    if sqlite3_step(q) == SQLITE_ROW {
                        eventID = col(q, 0)
                        keepStarred = sqlite3_column_int(q, 1) == 1
                        keepStarredAt = sqlite3_column_type(q, 2) == SQLITE_NULL
                            ? nil : Date(timeIntervalSince1970: sqlite3_column_double(q, 2))
                        keepEdited = sqlite3_column_int(q, 3) == 1
                        if keepEdited {
                            keepTitle = col(q, 4)
                            keepSummary = col(q, 5)
                        }
                    }
                }
                sqlite3_finalize(q)
            }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, eventID)
            bind(st, 2, e.day)
            sqlite3_bind_double(st, 3, e.startAt.timeIntervalSince1970)
            if let end = e.endAt { sqlite3_bind_double(st, 4, end.timeIntervalSince1970) } else { sqlite3_bind_null(st, 4) }
            bind(st, 5, e.scene)
            bind(st, 6, keepTitle)
            bind(st, 7, keepSummary)
            bind(st, 8, JSONList.encode(e.points))
            bind(st, 9, JSONList.encode(e.people))
            if let p = e.place, !p.isEmpty { bind(st, 10, p) } else { sqlite3_bind_null(st, 10) }
            bind(st, 11, e.emotion)
            sqlite3_bind_int(st, 12, Int32(e.intensity))
            sqlite3_bind_int(st, 13, e.important ? 1 : 0)
            sqlite3_bind_int(st, 14, keepStarred ? 1 : 0)
            if let s = keepStarredAt { sqlite3_bind_double(st, 15, s.timeIntervalSince1970) } else { sqlite3_bind_null(st, 15) }
            if let en = e.entityId { bind(st, 16, en) } else { sqlite3_bind_null(st, 16) }
            sqlite3_bind_int(st, 17, Int32(e.lineFrom))
            sqlite3_bind_int(st, 18, Int32(e.lineTo))
            sqlite3_bind_int(st, 19, 0)
            sqlite3_bind_double(st, 20, e.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(st, 21, keepEdited ? 1 : 0)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func events(day: String? = nil, limit: Int = 200) -> [MemoryEvent] {
        queue.sync { () -> [MemoryEvent] in
            var sql = "SELECT id,day,start_at,end_at,scene,title,summary,points_json,people_json,place,emotion,intensity,important,starred,starred_at,entity_id,line_from,line_to,created_at FROM memory_event WHERE deleted=0"
            if day != nil { sql += " AND day=?" }
            sql += " ORDER BY start_at DESC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            if let d = day { bind(st, 1, d) }
            var out: [MemoryEvent] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readEvent(st))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    func events(from: Date, to: Date, starredOnly: Bool = false, limit: Int = 100) -> [MemoryEvent] {
        queue.sync { () -> [MemoryEvent] in
            var sql = "SELECT id,day,start_at,end_at,scene,title,summary,points_json,people_json,place,emotion,intensity,important,starred,starred_at,entity_id,line_from,line_to,created_at FROM memory_event WHERE deleted=0 AND start_at>=? AND start_at<=?"
            if starredOnly { sql += " AND starred=1" }
            sql += " ORDER BY start_at DESC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_double(st, 1, from.timeIntervalSince1970)
            sqlite3_bind_double(st, 2, to.timeIntervalSince1970)
            var out: [MemoryEvent] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readEvent(st))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    func setEventStar(id: String, starred: Bool) {
        queue.sync { () -> Void in
            let sql = "UPDATE memory_event SET starred=?, starred_at=? WHERE id=?;"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            sqlite3_bind_int(st, 1, starred ? 1 : 0)
            if starred { sqlite3_bind_double(st, 2, Date().timeIntervalSince1970) } else { sqlite3_bind_null(st, 2) }
            bind(st, 3, id)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    /// 用户在详情页手改了标题/摘要，标记成人工编辑，自动整理时不再覆盖
    func updateEventTitle(id: String, title: String, summary: String) {
        queue.sync { () -> Void in
            let sql = "UPDATE memory_event SET title=?, summary=?, edited=1 WHERE id=?;"
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                bind(st, 1, title)
                bind(st, 2, summary)
                bind(st, 3, id)
                sqlite3_step(st)
                sqlite3_finalize(st)
            } else {
                let fallback = "UPDATE memory_event SET title=?, summary=? WHERE id=?;"
                var s2: OpaquePointer?
                guard sqlite3_prepare_v2(db, fallback, -1, &s2, nil) == SQLITE_OK else { return }
                bind(s2, 1, title)
                bind(s2, 2, summary)
                bind(s2, 3, id)
                sqlite3_step(s2)
                sqlite3_finalize(s2)
            }
        }
    }

    func deleteEvent(id: String) {
        queue.sync { () -> Void in
            let sql = "UPDATE memory_event SET deleted=1 WHERE id=?;"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, id)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    private func readEvent(_ st: OpaquePointer?) -> MemoryEvent {
        let id = col(st, 0)
        let day = col(st, 1)
        let start = Date(timeIntervalSince1970: sqlite3_column_double(st, 2))
        let end: Date? = sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 3))
        let scene = col(st, 4)
        let title = col(st, 5)
        let summary = col(st, 6)
        let points = JSONList.decode(col(st, 7))
        let people = JSONList.decode(col(st, 8))
        let place: String? = sqlite3_column_type(st, 9) == SQLITE_NULL ? nil : col(st, 9)
        let emotion = col(st, 10)
        let intensity = Int(sqlite3_column_int(st, 11))
        let important = sqlite3_column_int(st, 12) == 1
        let starred = sqlite3_column_int(st, 13) == 1
        let starredAt: Date? = sqlite3_column_type(st, 14) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 14))
        let entityId: String? = sqlite3_column_type(st, 15) == SQLITE_NULL ? nil : col(st, 15)
        let lineFrom = Int(sqlite3_column_int(st, 16))
        let lineTo = Int(sqlite3_column_int(st, 17))
        let created = Date(timeIntervalSince1970: sqlite3_column_double(st, 18))
        return MemoryEvent(id: id, day: day, startAt: start, endAt: end, scene: scene, title: title,
                           summary: summary, points: points, people: people, place: place,
                           emotion: emotion, intensity: intensity, important: important,
                           starred: starred, starredAt: starredAt, entityId: entityId,
                           lineFrom: lineFrom, lineTo: lineTo, createdAt: created)
    }

    // MARK: 提取项

    func insertItems(_ items: [MemoryItem]) {
        queue.sync { () -> Void in
            let sql = """
            INSERT OR REPLACE INTO memory_item
            (id,event_id,day,category,kind,content,status,due_text,due_at,who,source_text,created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            for it in items {
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { continue }
                bind(st, 1, it.id)
                if let e = it.eventId { bind(st, 2, e) } else { sqlite3_bind_null(st, 2) }
                bind(st, 3, it.day)
                bind(st, 4, it.category)
                if let k = it.kind, !k.isEmpty { bind(st, 5, k) } else { sqlite3_bind_null(st, 5) }
                bind(st, 6, it.content)
                bind(st, 7, it.status.rawValue)
                if let d = it.dueText, !d.isEmpty { bind(st, 8, d) } else { sqlite3_bind_null(st, 8) }
                if let d = it.dueAt { sqlite3_bind_double(st, 9, d.timeIntervalSince1970) } else { sqlite3_bind_null(st, 9) }
                if let w = it.who, !w.isEmpty { bind(st, 10, w) } else { sqlite3_bind_null(st, 10) }
                if let s = it.sourceText, !s.isEmpty { bind(st, 11, s) } else { sqlite3_bind_null(st, 11) }
                sqlite3_bind_double(st, 12, it.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(st, 13, it.updatedAt.timeIntervalSince1970)
                sqlite3_step(st)
                sqlite3_finalize(st)
            }
        }
    }

    func items(day: String? = nil, status: MemItemStatus? = nil, category: String? = nil, limit: Int = 300) -> [MemoryItem] {
        queue.sync { () -> [MemoryItem] in
            var sql = "SELECT id,event_id,day,category,kind,content,status,due_text,due_at,who,source_text,created_at,updated_at FROM memory_item WHERE 1=1"
            if day != nil { sql += " AND day=?" }
            if status != nil { sql += " AND status=?" }
            if category != nil { sql += " AND category=?" }
            sql += " ORDER BY COALESCE(due_at, created_at) ASC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            var idx: Int32 = 1
            if let d = day { bind(st, idx, d); idx += 1 }
            if let s = status { bind(st, idx, s.rawValue); idx += 1 }
            if let c = category { bind(st, idx, c); idx += 1 }
            var out: [MemoryItem] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readItem(st))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    func setItemStatus(id: String, status: MemItemStatus) {
        queue.sync { () -> Void in
            let sql = "UPDATE memory_item SET status=?, updated_at=? WHERE id=?;"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, status.rawValue)
            sqlite3_bind_double(st, 2, Date().timeIntervalSince1970)
            bind(st, 3, id)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    /// 模型请求返回时重新核对当前状态，不能覆盖用户刚做的忽略或完成操作。
    func completeOpenItem(id: String) {
        queue.sync {
            let sql = "UPDATE memory_item SET status='done', updated_at=? WHERE id=? AND status IN ('pending','accepted');"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
            bind(st, 2, id)
            sqlite3_step(st)
        }
    }

    func itemCounts() -> (pending: Int, accepted: Int, done: Int) {
        queue.sync { () -> (pending: Int, accepted: Int, done: Int) in
            var p = 0, a = 0, d = 0
            var st: OpaquePointer?
            let sql = "SELECT status, COUNT(*) FROM memory_item GROUP BY status;"
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                while sqlite3_step(st) == SQLITE_ROW {
                    let s = col(st, 0)
                    let c = Int(sqlite3_column_int(st, 1))
                    if s == "pending" { p = c }
                    else if s == "accepted" { a = c }
                    else if s == "done" { d = c }
                }
                sqlite3_finalize(st)
            }
            return (p, a, d)
        }
    }

    /// 把真实编号与内容一起交给整理模型，完成提示只能引用这些未完成事项。
    func openItemContents(days: Int = 30) -> [String] {
        queue.sync { () -> [String] in
            let since = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
            var st: OpaquePointer?
            let sql = "SELECT id,content FROM memory_item WHERE status IN ('pending','accepted') AND created_at>=?;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_double(st, 1, since)
            var out: [String] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let item = ["id": col(st, 0), "content": col(st, 1)]
                if let data = try? JSONSerialization.data(withJSONObject: item),
                   let text = String(data: data, encoding: .utf8) {
                    out.append(text)
                }
            }
            sqlite3_finalize(st)
            return out
        }
    }

    /// 用户明确忽略过的内容（整理时作为 ignored_items，避免重复提取）
    func ignoredItemContents(days: Int = 60) -> [String] {
        queue.sync { () -> [String] in
            let since = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
            var st: OpaquePointer?
            let sql = "SELECT content FROM memory_item WHERE status='ignored' AND created_at>=? LIMIT 60;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_double(st, 1, since)
            var out: [String] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let v = col(st, 0)
                out.append(v)
            }
            sqlite3_finalize(st)
            return out
        }
    }

    private func readItem(_ st: OpaquePointer?) -> MemoryItem {
        let id = col(st, 0)
        let eventId: String? = sqlite3_column_type(st, 1) == SQLITE_NULL ? nil : col(st, 1)
        let day = col(st, 2)
        let category = col(st, 3)
        let kind: String? = sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : col(st, 4)
        let content = col(st, 5)
        let status = MemItemStatus(rawValue: col(st, 6)) ?? .pending
        let dueText: String? = sqlite3_column_type(st, 7) == SQLITE_NULL ? nil : col(st, 7)
        let dueAt: Date? = sqlite3_column_type(st, 8) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 8))
        let who: String? = sqlite3_column_type(st, 9) == SQLITE_NULL ? nil : col(st, 9)
        let source: String? = sqlite3_column_type(st, 10) == SQLITE_NULL ? nil : col(st, 10)
        let created = Date(timeIntervalSince1970: sqlite3_column_double(st, 11))
        let updated = Date(timeIntervalSince1970: sqlite3_column_double(st, 12))
        return MemoryItem(id: id, eventId: eventId, day: day, category: category, kind: kind,
                          content: content, status: status, dueText: dueText, dueAt: dueAt,
                          who: who, sourceText: source, createdAt: created, updatedAt: updated)
    }

    // MARK: 技能卡

    func insertCard(_ c: SkillCard) {
        queue.sync { () -> Void in
            let sql = """
            INSERT OR REPLACE INTO skill_card
            (id,skill_id,skill_name,day,start_at,end_at,entity_id,fields_json,quotes_json,nothing_reason,created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, c.id)
            bind(st, 2, c.skillId)
            bind(st, 3, c.skillName)
            bind(st, 4, c.day)
            if let s = c.startAt { sqlite3_bind_double(st, 5, s.timeIntervalSince1970) } else { sqlite3_bind_null(st, 5) }
            if let e = c.endAt { sqlite3_bind_double(st, 6, e.timeIntervalSince1970) } else { sqlite3_bind_null(st, 6) }
            if let en = c.entityId { bind(st, 7, en) } else { sqlite3_bind_null(st, 7) }
            bind(st, 8, JSONList.encodeMap(c.fields))
            bind(st, 9, JSONList.encode(c.quotes))
            if let n = c.nothingReason { bind(st, 10, n) } else { sqlite3_bind_null(st, 10) }
            sqlite3_bind_double(st, 11, c.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func cards(day: String? = nil, skillId: String? = nil, limit: Int = 60) -> [SkillCard] {
        queue.sync { () -> [SkillCard] in
            var sql = "SELECT id,skill_id,skill_name,day,start_at,end_at,entity_id,fields_json,quotes_json,nothing_reason,created_at FROM skill_card WHERE 1=1"
            if day != nil { sql += " AND day=?" }
            if skillId != nil { sql += " AND skill_id=?" }
            sql += " ORDER BY created_at DESC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            var idx: Int32 = 1
            if let d = day { bind(st, idx, d); idx += 1 }
            if let s = skillId { bind(st, idx, s); idx += 1 }
            var out: [SkillCard] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let id = col(st, 0)
                let sid = col(st, 1)
                let sname = col(st, 2)
                let d = col(st, 3)
                let sa: Date? = sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 4))
                let ea: Date? = sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 5))
                let en: String? = sqlite3_column_type(st, 6) == SQLITE_NULL ? nil : col(st, 6)
                let fields = JSONList.decodeMap(col(st, 7))
                let quotes = JSONList.decode(col(st, 8))
                let nr: String? = sqlite3_column_type(st, 9) == SQLITE_NULL ? nil : col(st, 9)
                let created = Date(timeIntervalSince1970: sqlite3_column_double(st, 10))
                out.append(SkillCard(id: id, skillId: sid, skillName: sname, day: d,
                                     startAt: sa, endAt: ea, entityId: en, fields: fields,
                                     quotes: quotes, nothingReason: nr, createdAt: created))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    // MARK: 寻物

    func upsertThing(_ t: Thing) {
        queue.sync { () -> Void in
            // created_at 只在首次插入时写，更新时不能覆盖，
            // 否则每改一次寻物记录，创建时间就被改成最后修改时间。
            let sql = """
            INSERT INTO thing (id,name,aliases_json,owner,place,holder,updated_at,created_at)
            VALUES (?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                name=excluded.name,
                aliases_json=excluded.aliases_json,
                owner=excluded.owner,
                place=excluded.place,
                holder=excluded.holder,
                updated_at=excluded.updated_at;
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, t.id)
            bind(st, 2, t.name)
            bind(st, 3, JSONList.encode(t.aliases))
            bind(st, 4, t.owner)
            if let p = t.place { bind(st, 5, p) } else { sqlite3_bind_null(st, 5) }
            if let h = t.holder { bind(st, 6, h) } else { sqlite3_bind_null(st, 6) }
            sqlite3_bind_double(st, 7, t.updatedAt.timeIntervalSince1970)
            sqlite3_bind_double(st, 8, t.updatedAt.timeIntervalSince1970)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func things(limit: Int = 200) -> [Thing] {
        queue.sync { () -> [Thing] in
            var st: OpaquePointer?
            let sql = "SELECT id,name,aliases_json,owner,place,holder,updated_at FROM thing ORDER BY updated_at DESC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            var out: [Thing] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let place: String? = sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : col(st, 4)
                let holder: String? = sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : col(st, 5)
                out.append(Thing(id: col(st, 0), name: col(st, 1), aliases: JSONList.decode(col(st, 2)),
                                 owner: col(st, 3), place: place, holder: holder,
                                 updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 6))))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    func thing(named name: String) -> Thing? {
        let all = things()
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // 空名字曾导致 name.contains("") 恒真、直接命中第一件物品；这里直接返回 nil
        guard !key.isEmpty else { return nil }
        for t in all {
            if t.name.lowercased() == key { return t }
            for a in t.aliases where a.lowercased() == key { return t }
        }
        return all.first { $0.name.lowercased().contains(key) || key.contains($0.name.lowercased()) }
    }

    func insertFact(_ f: ThingFact) {
        queue.sync { () -> Void in
            let sql = "INSERT OR REPLACE INTO thing_fact (id,thing_id,action,place,who,line_id,confident,at,created_at) VALUES (?,?,?,?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, f.id)
            bind(st, 2, f.thingId)
            bind(st, 3, f.action)
            if let p = f.place { bind(st, 4, p) } else { sqlite3_bind_null(st, 4) }
            if let w = f.who { bind(st, 5, w) } else { sqlite3_bind_null(st, 5) }
            if let l = f.lineId { bind(st, 6, l) } else { sqlite3_bind_null(st, 6) }
            sqlite3_bind_int(st, 7, f.confident ? 1 : 0)
            sqlite3_bind_double(st, 8, f.at.timeIntervalSince1970)
            sqlite3_bind_double(st, 9, Date().timeIntervalSince1970)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func facts(thingId: String, limit: Int = 20) -> [ThingFact] {
        queue.sync { () -> [ThingFact] in
            var st: OpaquePointer?
            let sql = "SELECT id,thing_id,action,place,who,line_id,confident,at FROM thing_fact WHERE thing_id=? ORDER BY at DESC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            bind(st, 1, thingId)
            var out: [ThingFact] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let place: String? = sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : col(st, 3)
                let who: String? = sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : col(st, 4)
                let line: String? = sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : col(st, 5)
                out.append(ThingFact(id: col(st, 0), thingId: col(st, 1), action: col(st, 2),
                                     place: place, who: who, lineId: line,
                                     confident: sqlite3_column_int(st, 6) == 1,
                                     at: Date(timeIntervalSince1970: sqlite3_column_double(st, 7))))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    // MARK: 待整理的段

    /// 定时整理包含之前积压的日期，不只处理当天。
    func undigestedDays(through day: String) -> [String] {
        queue.sync {
            let sql = "SELECT DISTINCT day FROM segment WHERE day<=? AND digested=0 AND state='transcribed' AND transcript<>'' ORDER BY day ASC;"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, day)
            var days: [String] = []
            while sqlite3_step(st) == SQLITE_ROW { days.append(col(st, 0)) }
            return days
        }
    }

    func undigestedSegments(day: String, limit: Int = 400) -> [Segment] {
        queue.sync { () -> [Segment] in
            var st: OpaquePointer?
            let sql = "SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at,capture_mode FROM segment WHERE day=? AND digested=0 AND state='transcribed' AND transcript<>'' ORDER BY started_at ASC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            bind(st, 1, day)
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readSegRow(st))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    func markDigested(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.sync { () -> Void in
            for id in ids {
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE segment SET digested=1 WHERE id=?;", -1, &st, nil) == SQLITE_OK else { continue }
                bind(st, 1, id)
                sqlite3_step(st)
                sqlite3_finalize(st)
            }
        }
    }

    /// 供整理使用：某天全部已转写原话（按时间）
    func transcriptRows(day: String, limit: Int = 600) -> [Segment] {
        queue.sync { () -> [Segment] in
            var st: OpaquePointer?
            let sql = "SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at,capture_mode FROM segment WHERE day=? AND state='transcribed' AND transcript<>'' ORDER BY started_at ASC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            bind(st, 1, day)
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readSegRow(st))
            }
            sqlite3_finalize(st)
            return out
        }
    }

    /// 标星的事件里用到的原话（记忆-重点页）
    func starredEvents(limit: Int = 100) -> [MemoryEvent] {
        queue.sync { () -> [MemoryEvent] in
            var st: OpaquePointer?
            let sql = "SELECT id,day,start_at,end_at,scene,title,summary,points_json,people_json,place,emotion,intensity,important,starred,starred_at,entity_id,line_from,line_to,created_at FROM memory_event WHERE deleted=0 AND starred=1 ORDER BY starred_at DESC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            var out: [MemoryEvent] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(readEvent(st))
            }
            sqlite3_finalize(st)
            return out
        }
    }
}
