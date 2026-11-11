import Foundation
import SQLite3

// MARK: - 扩展表结构（人物 / 技能 / 通道 / 足迹 / 提醒 / 回顾 / 问问 / 热词）
extension Store {

    func migrateExtra() {
        queue.sync {
            exec("""
            CREATE TABLE IF NOT EXISTS person (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL DEFAULT '#F0833E',
                note TEXT NOT NULL DEFAULT '',
                is_me INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS voice_sample (
                id TEXT PRIMARY KEY,
                person_id TEXT NOT NULL,
                segment_id TEXT NOT NULL,
                vector TEXT NOT NULL DEFAULT '[]',
                created_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_vs_person ON voice_sample(person_id);")
            exec("""
            CREATE TABLE IF NOT EXISTS skill (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                symbol TEXT NOT NULL DEFAULT 'sparkles',
                desc TEXT NOT NULL DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 1,
                schedule TEXT NOT NULL DEFAULT 'manual',
                hour INTEGER NOT NULL DEFAULT 21,
                minute INTEGER NOT NULL DEFAULT 0,
                weekday INTEGER NOT NULL DEFAULT 1,
                prompt TEXT NOT NULL DEFAULT '',
                builtin INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS skill_run (
                id TEXT PRIMARY KEY,
                skill_id TEXT NOT NULL,
                skill_name TEXT NOT NULL,
                day TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                output TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_run_day ON skill_run(day);")
            exec("""
            CREATE TABLE IF NOT EXISTS channel (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                url TEXT NOT NULL DEFAULT '',
                extra TEXT NOT NULL DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 1,
                last_push_at REAL,
                last_status TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS place (
                id TEXT PRIMARY KEY,
                day TEXT NOT NULL,
                name TEXT NOT NULL,
                lat REAL NOT NULL DEFAULT 0,
                lon REAL NOT NULL DEFAULT 0,
                arrive_at REAL NOT NULL,
                leave_at REAL NOT NULL,
                is_home INTEGER NOT NULL DEFAULT 0
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_place_day ON place(day);")
            exec("""
            CREATE TABLE IF NOT EXISTS reminder (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                fire_at REAL NOT NULL,
                item_id TEXT NOT NULL DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 1,
                repeat_daily INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS review (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                day TEXT NOT NULL,
                headline TEXT NOT NULL DEFAULT '',
                text TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_review_day ON review(day);")
            exec("""
            CREATE TABLE IF NOT EXISTS ask (
                id TEXT PRIMARY KEY,
                role TEXT NOT NULL,
                text TEXT NOT NULL,
                citations TEXT NOT NULL DEFAULT '[]',
                created_at REAL NOT NULL
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS hotword (
                id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                replacement TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL
            );
            """)
            // segment 扩展列
            ensureColumn(table: "segment", column: "starred", ddl: "ALTER TABLE segment ADD COLUMN starred INTEGER NOT NULL DEFAULT 0;")
            ensureColumn(table: "segment", column: "place", ddl: "ALTER TABLE segment ADD COLUMN place TEXT NOT NULL DEFAULT '';")
            ensureColumn(table: "segment", column: "imported", ddl: "ALTER TABLE segment ADD COLUMN imported INTEGER NOT NULL DEFAULT 0;")
            ensureColumn(table: "segment", column: "kind_tag", ddl: "ALTER TABLE segment ADD COLUMN kind_tag TEXT NOT NULL DEFAULT '';")
        }
    }

    private func ensureColumn(table: String, column: String, ddl: String) {
        var st: OpaquePointer?
        var exists = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW {
                if col(st, 1) == column { exists = true }
            }
        }
        sqlite3_finalize(st)
        if !exists { exec(ddl) }
    }

    // MARK: - 人物

    func persons() -> [Person] {
        queue.sync { () -> [Person] in
            var st: OpaquePointer?
            let sql = """
            SELECT p.id, p.name, p.color_hex, p.note, p.is_me, p.created_at,
                   (SELECT COUNT(*) FROM voice_sample v WHERE v.person_id = p.id)
            FROM person p ORDER BY p.is_me DESC, p.created_at ASC;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Person] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Person(
                    id: col(st, 0),
                    name: col(st, 1),
                    colorHex: col(st, 2),
                    note: col(st, 3),
                    isMe: sqlite3_column_int64(st, 4) != 0,
                    sampleCount: Int(sqlite3_column_int64(st, 6)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 5))
                ))
            }
            return out
        }
    }

    func upsertPerson(_ p: Person) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO person (id,name,color_hex,note,is_me,created_at) VALUES (?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, p.id)
            bind(st, 2, p.name)
            bind(st, 3, p.colorHex)
            bind(st, 4, p.note)
            sqlite3_bind_int64(st, 5, p.isMe ? 1 : 0)
            sqlite3_bind_double(st, 6, p.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func deletePerson(id: String) {
        queue.sync {
            var a: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM voice_sample WHERE person_id=?;", -1, &a, nil) == SQLITE_OK {
                bind(a, 1, id); sqlite3_step(a)
            }
            sqlite3_finalize(a)
            var b: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM person WHERE id=?;", -1, &b, nil) == SQLITE_OK {
                bind(b, 1, id); sqlite3_step(b)
            }
            sqlite3_finalize(b)
        }
    }

    // MARK: - 声纹样本

    func insertVoiceSample(_ s: VoiceSample) {
        let json = (try? JSONSerialization.data(withJSONObject: s.vector, options: [])) ?? Data()
        let text = String(data: json, encoding: .utf8) ?? "[]"
        queue.sync {
            let sql = "INSERT OR REPLACE INTO voice_sample (id,person_id,segment_id,vector,created_at) VALUES (?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, s.id)
            bind(st, 2, s.personId)
            bind(st, 3, s.segmentId)
            bind(st, 4, text)
            sqlite3_bind_double(st, 5, s.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func voiceSamples(personId: String) -> [VoiceSample] {
        queue.sync { () -> [VoiceSample] in
            var st: OpaquePointer?
            let sql = "SELECT id,person_id,segment_id,vector,created_at FROM voice_sample WHERE person_id=? ORDER BY created_at ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, personId)
            var out: [VoiceSample] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let vec = Store.decodeVector(col(st, 3))
                out.append(VoiceSample(
                    id: col(st, 0),
                    personId: col(st, 1),
                    segmentId: col(st, 2),
                    vector: vec,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 4))
                ))
            }
            return out
        }
    }

    func allVoiceSamples() -> [VoiceSample] {
        queue.sync { () -> [VoiceSample] in
            var st: OpaquePointer?
            let sql = "SELECT id,person_id,segment_id,vector,created_at FROM voice_sample;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [VoiceSample] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(VoiceSample(
                    id: col(st, 0),
                    personId: col(st, 1),
                    segmentId: col(st, 2),
                    vector: Store.decodeVector(col(st, 3)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 4))
                ))
            }
            return out
        }
    }

    func deleteVoiceSample(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM voice_sample WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id); sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    static func decodeVector(_ text: String) -> [Double] {
        guard let data = text.data(using: .utf8) else { return [] }
        if let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Double] {
            return arr
        }
        if let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [NSNumber] {
            return arr.map { $0.doubleValue }
        }
        return []
    }

    // MARK: - 技能

    func skills() -> [SkillDef] {
        queue.sync { () -> [SkillDef] in
            var st: OpaquePointer?
            let sql = """
            SELECT id,name,symbol,desc,enabled,schedule,hour,minute,weekday,prompt,builtin,created_at
            FROM skill ORDER BY builtin DESC, created_at ASC;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [SkillDef] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(SkillDef(
                    id: col(st, 0),
                    name: col(st, 1),
                    symbol: col(st, 2),
                    desc: col(st, 3),
                    enabled: sqlite3_column_int64(st, 4) != 0,
                    schedule: SkillSchedule(rawValue: col(st, 5)) ?? .manual,
                    hour: Int(sqlite3_column_int64(st, 6)),
                    minute: Int(sqlite3_column_int64(st, 7)),
                    weekday: Int(sqlite3_column_int64(st, 8)),
                    prompt: col(st, 9),
                    builtin: sqlite3_column_int64(st, 10) != 0,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 11))
                ))
            }
            return out
        }
    }

    func upsertSkill(_ s: SkillDef) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO skill
            (id,name,symbol,desc,enabled,schedule,hour,minute,weekday,prompt,builtin,created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, s.id)
            bind(st, 2, s.name)
            bind(st, 3, s.symbol)
            bind(st, 4, s.desc)
            sqlite3_bind_int64(st, 5, s.enabled ? 1 : 0)
            bind(st, 6, s.schedule.rawValue)
            sqlite3_bind_int64(st, 7, Int64(s.hour))
            sqlite3_bind_int64(st, 8, Int64(s.minute))
            sqlite3_bind_int64(st, 9, Int64(s.weekday))
            bind(st, 10, s.prompt)
            sqlite3_bind_int64(st, 11, s.builtin ? 1 : 0)
            sqlite3_bind_double(st, 12, s.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func deleteSkill(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM skill WHERE id=? AND builtin=0;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id); sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func insertSkillRun(_ r: SkillRun) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO skill_run (id,skill_id,skill_name,day,title,output,created_at) VALUES (?,?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, r.id)
            bind(st, 2, r.skillId)
            bind(st, 3, r.skillName)
            bind(st, 4, r.day)
            bind(st, 5, r.title)
            bind(st, 6, r.output)
            sqlite3_bind_double(st, 7, r.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func skillRuns(day: String? = nil, limit: Int = 60) -> [SkillRun] {
        queue.sync { () -> [SkillRun] in
            var sql = "SELECT id,skill_id,skill_name,day,title,output,created_at FROM skill_run"
            if day != nil { sql += " WHERE day=?" }
            sql += " ORDER BY created_at DESC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            if let d = day { bind(st, 1, d) }
            var out: [SkillRun] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(SkillRun(
                    id: col(st, 0),
                    skillId: col(st, 1),
                    skillName: col(st, 2),
                    day: col(st, 3),
                    title: col(st, 4),
                    output: col(st, 5),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 6))
                ))
            }
            return out
        }
    }

    // MARK: - 通道

    func channels() -> [Channel] {
        queue.sync { () -> [Channel] in
            var st: OpaquePointer?
            let sql = "SELECT id,kind,name,url,extra,enabled,last_push_at,last_status,created_at FROM channel ORDER BY created_at ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Channel] = []
            while sqlite3_step(st) == SQLITE_ROW {
                var last: Date? = nil
                if sqlite3_column_type(st, 6) != SQLITE_NULL {
                    last = Date(timeIntervalSince1970: sqlite3_column_double(st, 6))
                }
                out.append(Channel(
                    id: col(st, 0),
                    kind: ChannelKind(rawValue: col(st, 1)) ?? .webhook,
                    name: col(st, 2),
                    url: col(st, 3),
                    extra: col(st, 4),
                    enabled: sqlite3_column_int64(st, 5) != 0,
                    lastPushAt: last,
                    lastStatus: col(st, 7),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 8))
                ))
            }
            return out
        }
    }

    func upsertChannel(_ c: Channel) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO channel (id,kind,name,url,extra,enabled,last_push_at,last_status,created_at) VALUES (?,?,?,?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, c.id)
            bind(st, 2, c.kind.rawValue)
            bind(st, 3, c.name)
            bind(st, 4, c.url)
            bind(st, 5, c.extra)
            sqlite3_bind_int64(st, 6, c.enabled ? 1 : 0)
            if let d = c.lastPushAt {
                sqlite3_bind_double(st, 7, d.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(st, 7)
            }
            bind(st, 8, c.lastStatus)
            sqlite3_bind_double(st, 9, c.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func deleteChannel(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM channel WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id); sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func markChannelPushed(id: String, status: String) {
        queue.sync {
            var st: OpaquePointer?
            let sql = "UPDATE channel SET last_push_at=?, last_status=? WHERE id=?;"
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_double(st, 1, Date().timeIntervalSince1970)
                bind(st, 2, status)
                bind(st, 3, id)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    // MARK: - 足迹

    func places(day: String) -> [PlaceVisit] {
        queue.sync { () -> [PlaceVisit] in
            var st: OpaquePointer?
            let sql = "SELECT id,day,name,lat,lon,arrive_at,leave_at,is_home FROM place WHERE day=? ORDER BY arrive_at ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, day)
            var out: [PlaceVisit] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(PlaceVisit(
                    id: col(st, 0),
                    day: col(st, 1),
                    name: col(st, 2),
                    latitude: sqlite3_column_double(st, 3),
                    longitude: sqlite3_column_double(st, 4),
                    arriveAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 5)),
                    leaveAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 6)),
                    isHome: sqlite3_column_int64(st, 7) != 0
                ))
            }
            return out
        }
    }

    func upsertPlace(_ p: PlaceVisit) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO place (id,day,name,lat,lon,arrive_at,leave_at,is_home) VALUES (?,?,?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, p.id)
            bind(st, 2, p.day)
            bind(st, 3, p.name)
            sqlite3_bind_double(st, 4, p.latitude)
            sqlite3_bind_double(st, 5, p.longitude)
            sqlite3_bind_double(st, 6, p.arriveAt.timeIntervalSince1970)
            sqlite3_bind_double(st, 7, p.leaveAt.timeIntervalSince1970)
            sqlite3_bind_int64(st, 8, p.isHome ? 1 : 0)
            sqlite3_step(st)
        }
    }

    // MARK: - 提醒

    func reminders() -> [Reminder] {
        queue.sync { () -> [Reminder] in
            var st: OpaquePointer?
            let sql = "SELECT id,title,fire_at,item_id,enabled,repeat_daily,created_at FROM reminder ORDER BY fire_at ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Reminder] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Reminder(
                    id: col(st, 0),
                    title: col(st, 1),
                    fireAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
                    itemId: col(st, 3),
                    enabled: sqlite3_column_int64(st, 4) != 0,
                    repeatDaily: sqlite3_column_int64(st, 5) != 0,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 6))
                ))
            }
            return out
        }
    }

    func upsertReminder(_ r: Reminder) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO reminder (id,title,fire_at,item_id,enabled,repeat_daily,created_at) VALUES (?,?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, r.id)
            bind(st, 2, r.title)
            sqlite3_bind_double(st, 3, r.fireAt.timeIntervalSince1970)
            bind(st, 4, r.itemId)
            sqlite3_bind_int64(st, 5, r.enabled ? 1 : 0)
            sqlite3_bind_int64(st, 6, r.repeatDaily ? 1 : 0)
            sqlite3_bind_double(st, 7, r.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func deleteReminder(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM reminder WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id); sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    // MARK: - 回顾

    func reviews(limit: Int = 40) -> [ReviewRecord] {
        queue.sync { () -> [ReviewRecord] in
            var st: OpaquePointer?
            let sql = "SELECT id,kind,day,headline,text,created_at FROM review ORDER BY created_at DESC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [ReviewRecord] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(ReviewRecord(
                    id: col(st, 0),
                    kind: ReviewKind(rawValue: col(st, 1)) ?? .daily,
                    day: col(st, 2),
                    headline: col(st, 3),
                    text: col(st, 4),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 5))
                ))
            }
            return out
        }
    }

    func saveReview(_ r: ReviewRecord) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO review (id,kind,day,headline,text,created_at) VALUES (?,?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, r.id)
            bind(st, 2, r.kind.rawValue)
            bind(st, 3, r.day)
            bind(st, 4, r.headline)
            bind(st, 5, r.text)
            sqlite3_bind_double(st, 6, r.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    // MARK: - 问问

    func askMessages(limit: Int = 200) -> [AskMessage] {
        queue.sync { () -> [AskMessage] in
            var st: OpaquePointer?
            let sql = "SELECT id,role,text,citations,created_at FROM ask ORDER BY created_at ASC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [AskMessage] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let cites = Store.decodeStringArray(col(st, 3))
                out.append(AskMessage(
                    id: col(st, 0),
                    role: AskRole(rawValue: col(st, 1)) ?? .me,
                    text: col(st, 2),
                    citations: cites,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 4))
                ))
            }
            return out
        }
    }

    func insertAsk(_ m: AskMessage) {
        let json = (try? JSONSerialization.data(withJSONObject: m.citations, options: [])) ?? Data()
        let text = String(data: json, encoding: .utf8) ?? "[]"
        queue.sync {
            let sql = "INSERT OR REPLACE INTO ask (id,role,text,citations,created_at) VALUES (?,?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, m.id)
            bind(st, 2, m.role.rawValue)
            bind(st, 3, m.text)
            bind(st, 4, text)
            sqlite3_bind_double(st, 5, m.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func clearAsk() {
        queue.sync { exec("DELETE FROM ask;") }
    }

    static func decodeStringArray(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8) else { return [] }
        if let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [String] {
            return arr
        }
        return []
    }

    // MARK: - 热词

    func hotwords() -> [Hotword] {
        queue.sync { () -> [Hotword] in
            var st: OpaquePointer?
            let sql = "SELECT id,word,replacement,created_at FROM hotword ORDER BY created_at ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Hotword] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Hotword(
                    id: col(st, 0),
                    word: col(st, 1),
                    replacement: col(st, 2),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 3))
                ))
            }
            return out
        }
    }

    func upsertHotword(_ h: Hotword) {
        queue.sync {
            let sql = "INSERT OR REPLACE INTO hotword (id,word,replacement,created_at) VALUES (?,?,?,?);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, h.id)
            bind(st, 2, h.word)
            bind(st, 3, h.replacement)
            sqlite3_bind_double(st, 4, h.createdAt.timeIntervalSince1970)
            sqlite3_step(st)
        }
    }

    func deleteHotword(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM hotword WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id); sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    // MARK: - 段扩展

    func setStar(id: String, starred: Bool) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE segment SET starred=? WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_int64(st, 1, starred ? 1 : 0)
                bind(st, 2, id)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func setSpeaker(id: String, speaker: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE segment SET speaker=? WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, speaker)
                bind(st, 2, id)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func setPlaceTag(id: String, place: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE segment SET place=? WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, place)
                bind(st, 2, id)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func starredSegments(limit: Int = 100) -> [Segment] {
        queue.sync { () -> [Segment] in
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at
            FROM segment WHERE starred=1 ORDER BY started_at DESC LIMIT \(limit);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSegRow(st)) }
            return out
        }
    }

    /// 某天所有已转写文本（按时间升序），给 LLM 用
    func transcriptLines(day: String) -> [(time: String, speaker: String, text: String, id: String)] {
        queue.sync { () -> [(time: String, speaker: String, text: String, id: String)] in
            let sql = """
            SELECT id,started_at,transcript,speaker FROM segment
            WHERE day=? AND state='transcribed' AND LENGTH(TRIM(transcript))>0
            ORDER BY started_at ASC;
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, day)
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            var out: [(time: String, speaker: String, text: String, id: String)] = []
            while sqlite3_step(st) == SQLITE_ROW {
                let d = Date(timeIntervalSince1970: sqlite3_column_double(st, 1))
                out.append((f.string(from: d), col(st, 3), col(st, 2), col(st, 0)))
            }
            return out
        }
    }

    /// 清空全部数据（含音频文件）
    func wipeAll() {
        queue.sync {
            for t in ["segment", "item", "digest", "person", "voice_sample", "skill",
                      "skill_run", "channel", "place", "reminder", "review", "ask", "hotword"] {
                exec("DELETE FROM \(t);")
            }
        }
        let dir = Store.audioDir
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// 关键词检索（给问问找原文出处）    func searchForAsk(_ q: String, limit: Int = 12) -> [Segment] {
        let kws = Store.keywords(from: q)
        guard !kws.isEmpty else { return [] }
        return queue.sync { () -> [Segment] in
            let clauses = Array(repeating: "transcript LIKE ?", count: kws.count).joined(separator: " OR ")
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at
            FROM segment WHERE state='transcribed' AND (\(clauses))
            ORDER BY started_at DESC LIMIT \(min(limit * 4, 80));
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            for (i, k) in kws.enumerated() { bind(st, Int32(i + 1), "%\(k)%") }
            var rows: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW { rows.append(readSegRow(st)) }
            // 命中词多的排前面，同分按时间新→旧
            let scored = rows.map { seg -> (Segment, Int) in
                (seg, kws.reduce(0) { $0 + (seg.transcript.contains($1) ? 1 : 0) })
            }
            let sorted = scored.sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.startedAt > b.0.startedAt
            }
            return sorted.prefix(limit).map { $0.0 }
        }
    }

    /// 把一句中文问句切成可检索的关键词：去疑问词 → 长串按 2-gram 切
    static func keywords(from q: String) -> [String] {
        let stop = ["请问", "帮我", "什么", "怎么", "哪些", "哪个", "哪儿", "哪里", "是否", "有没有",
                    "还记得", "记得", "上次", "之前", "那天", "时候", "我们", "他们", "一下",
                    "吗", "呢", "吧", "啊", "了", "的", "我", "你", "他", "她", "它", "是", "在",
                    "和", "有", "把", "给", "说", "过", "这", "那", "个", "就", "都", "还", "又"]
        var cleaned = q
        for s in stop { cleaned = cleaned.replacingOccurrences(of: s, with: " ") }
        let parts = cleaned
            .split(whereSeparator: { $0 == " " || $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 }
        var out: [String] = []
        func push(_ s: String) {
            if !out.contains(s) && out.count < 6 { out.append(s) }
        }
        for p in parts {
            if p.count <= 4 {
                push(p)
            } else {
                let chars = Array(p)
                var i = 0
                while i + 2 <= chars.count {
                    push(String(chars[i..<(i + 2)]))
                    i += 2
                }
            }
        }
        if out.isEmpty {
            let chars = Array(q.trimmingCharacters(in: .whitespacesAndNewlines))
            if chars.count >= 2 { out.append(String(chars.prefix(min(4, chars.count)))) }
        }
        return out
    }

    /// 最近 N 天的转写文本（给回顾 / 周报）
    func recentTranscripts(days: Int, limit: Int = 400) -> [Segment] {
        queue.sync { () -> [Segment] in
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at
            FROM segment WHERE state='transcribed' AND LENGTH(TRIM(transcript))>0
            ORDER BY started_at DESC LIMIT \(limit);
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSegRow(st)) }
            let cut = Date().addingTimeInterval(-Double(days) * 86400)
            return out.filter { $0.startedAt >= cut }
        }
    }

    func segment(id: String) -> Segment? {
        queue.sync { () -> Segment? in
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at
            FROM segment WHERE id=?;
            """
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            bind(st, 1, id)
            if sqlite3_step(st) == SQLITE_ROW { return readSegRow(st) }
            return nil
        }
    }

    func isStarred(id: String) -> Bool {
        queue.sync { () -> Bool in
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT starred FROM segment WHERE id=?;", -1, &st, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(st) }
            bind(st, 1, id)
            if sqlite3_step(st) == SQLITE_ROW { return sqlite3_column_int64(st, 0) != 0 }
            return false
        }
    }

    /// 重复灵感合并：把同一 kind 的条目按相似度归组
    func itemCount() -> Int {
        queue.sync { () -> Int in
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item;", -1, &st, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(st) }
            if sqlite3_step(st) == SQLITE_ROW { return Int(sqlite3_column_int64(st, 0)) }
            return 0
        }
    }

    func allItems(limit: Int = 800) -> [DigestItem] {
        queue.sync { () -> [DigestItem] in
            let sql = "SELECT id,day,kind,title,detail,due,status,created_at FROM item ORDER BY created_at DESC LIMIT \(limit);"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
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

    func deleteItem(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM item WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id); sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func setItemStatus(id: String, status: ItemStatus) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE item SET status=? WHERE id=?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, status.rawValue)
                bind(st, 2, id)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    func readSegRow(_ st: OpaquePointer?) -> Segment {
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
