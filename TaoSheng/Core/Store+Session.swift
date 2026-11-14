import Foundation
import SQLite3

/// 聆听会话与话轮的存储。
///
/// 这两张表是新加的，跟着 segment.session_id 一起在启动时迁移；
/// 老库没有这些列也能直接加，不用重建表。
extension Store {

    // MARK: - 迁移

    func migrateSession() {
        queue.sync {
            _ = exec("""
            CREATE TABLE IF NOT EXISTS listen_session(
                id TEXT PRIMARY KEY,
                mode TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL,
                state TEXT NOT NULL,
                speakers_json TEXT NOT NULL DEFAULT '{}',
                event_id TEXT,
                error TEXT,
                created_at REAL NOT NULL
            );
            """)
            _ = exec("CREATE INDEX IF NOT EXISTS idx_session_started ON listen_session(started_at DESC);")
            _ = exec("""
            CREATE TABLE IF NOT EXISTS utterance(
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                speaker TEXT NOT NULL,
                start_sec REAL NOT NULL,
                end_sec REAL NOT NULL,
                text TEXT NOT NULL,
                order_index INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            """)
            _ = exec("CREATE INDEX IF NOT EXISTS idx_utterance_session ON utterance(session_id, order_index);")
            ensureColumn(table: "segment", column: "session_id", ddl: "ALTER TABLE segment ADD COLUMN session_id TEXT;")
        }
    }

    // MARK: - 会话

    func insertSession(_ s: ListenSession) {
        queue.sync {
            var st: OpaquePointer?
            let sql = """
            INSERT OR REPLACE INTO listen_session
            (id, mode, started_at, ended_at, state, speakers_json, event_id, error, created_at)
            VALUES (?,?,?,?,?,?,?,?,?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, s.id)
            bind(st, 2, s.modeRaw)
            sqlite3_bind_double(st, 3, s.startedAt.timeIntervalSince1970)
            if let e = s.endedAt {
                sqlite3_bind_double(st, 4, e.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(st, 4)
            }
            bind(st, 5, s.stateRaw)
            bind(st, 6, s.speakersJSON.isEmpty ? "{}" : s.speakersJSON)
            if let ev = s.eventId, !ev.isEmpty { bind(st, 7, ev) } else { sqlite3_bind_null(st, 7) }
            if let err = s.error, !err.isEmpty { bind(st, 8, err) } else { sqlite3_bind_null(st, 8) }
            sqlite3_bind_double(st, 9, Date().timeIntervalSince1970)
            if sqlite3_step(st) != SQLITE_DONE {
                NSLog("涛声: 写入会话失败 \(s.id)")
            }
            sqlite3_finalize(st)
        }
    }

    /// 只更新状态相关字段：录音中会频繁写，不想整行重写。
    func updateSessionState(id: String, state: SessionState, error: String? = nil, eventId: String? = nil, endedAt: Date? = nil) {
        queue.sync {
            var st: OpaquePointer?
            let sql = """
            UPDATE listen_session
            SET state = ?, error = ?, event_id = COALESCE(?, event_id), ended_at = COALESCE(?, ended_at)
            WHERE id = ?;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, state.rawValue)
            if let e = error, !e.isEmpty { bind(st, 2, e) } else { sqlite3_bind_null(st, 2) }
            if let ev = eventId, !ev.isEmpty { bind(st, 3, ev) } else { sqlite3_bind_null(st, 3) }
            if let end = endedAt {
                sqlite3_bind_double(st, 4, end.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(st, 4)
            }
            bind(st, 5, id)
            _ = sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func updateSessionSpeakers(id: String, speakers: [String: String]) {
        queue.sync {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE listen_session SET speakers_json = ? WHERE id = ?;", -1, &st, nil) == SQLITE_OK else { return }
            bind(st, 1, JSONList.encodeMap(speakers))
            bind(st, 2, id)
            _ = sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    func session(id: String) -> ListenSession? {
        queue.sync {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT \(Self.sessionCols) FROM listen_session WHERE id = ? LIMIT 1;", -1, &st, nil) == SQLITE_OK else { return nil }
            bind(st, 1, id)
            defer { sqlite3_finalize(st) }
            return sqlite3_step(st) == SQLITE_ROW ? readSession(st) : nil
        }
    }

    /// 最近一场会话（英雄卡与「重试」用）。
    func latestSession() -> ListenSession? {
        queue.sync {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT \(Self.sessionCols) FROM listen_session ORDER BY started_at DESC LIMIT 1;", -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            return sqlite3_step(st) == SQLITE_ROW ? readSession(st) : nil
        }
    }

    /// 还没收尾的会话（重启后要接着处理）。
    func unfinishedSessions() -> [ListenSession] {
        queue.sync {
            var st: OpaquePointer?
            let sql = "SELECT \(Self.sessionCols) FROM listen_session WHERE state IN ('recording','finalizing','digesting') ORDER BY started_at ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [ListenSession] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSession(st)) }
            return out
        }
    }

    func sessions(day: String, limit: Int = 50) -> [ListenSession] {
        queue.sync {
            var st: OpaquePointer?
            let sql = "SELECT \(Self.sessionCols) FROM listen_session WHERE started_at >= ? AND started_at < ? ORDER BY started_at DESC LIMIT \(limit);"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            let dayStart = DayKey.date(from: day) ?? Date()
            sqlite3_bind_double(st, 1, dayStart.timeIntervalSince1970)
            sqlite3_bind_double(st, 2, dayStart.addingTimeInterval(24 * 3600).timeIntervalSince1970)
            var out: [ListenSession] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSession(st)) }
            return out
        }
    }

    func deleteSession(id: String) {
        queue.sync {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM listen_session WHERE id = ?;", -1, &st, nil) == SQLITE_OK {
                bind(st, 1, id)
                _ = sqlite3_step(st)
            }
            sqlite3_finalize(st)
            var st2: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM utterance WHERE session_id = ?;", -1, &st2, nil) == SQLITE_OK {
                bind(st2, 1, id)
                _ = sqlite3_step(st2)
            }
            sqlite3_finalize(st2)
        }
    }

    /// 本场所有段（按时间正序）。拼音频、兜底分人都用它。
    func sessionSegments(sessionId: String) -> [Segment] {
        queue.sync {
            var st: OpaquePointer?
            let sql = """
            SELECT id,started_at,ended_at,duration,file_name,byte_size,transcript,speaker,state,day,created_at,capture_mode,starred,session_id
            FROM segment WHERE session_id = ? ORDER BY started_at ASC;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, sessionId)
            var out: [Segment] = []
            while sqlite3_step(st) == SQLITE_ROW { out.append(readSegment(st)) }
            return out
        }
    }

    // MARK: - 话轮

    /// 整场覆盖写：重新分辨说话人时旧的按本场清掉再写。
    func replaceUtterances(sessionId: String, _ list: [Utterance]) {
        queue.sync {
            _ = exec("BEGIN IMMEDIATE;")
            var del: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM utterance WHERE session_id = ?;", -1, &del, nil) == SQLITE_OK {
                bind(del, 1, sessionId)
                _ = sqlite3_step(del)
            }
            sqlite3_finalize(del)
            let sql = "INSERT OR REPLACE INTO utterance (id, session_id, speaker, start_sec, end_sec, text, order_index, created_at) VALUES (?,?,?,?,?,?,?,?);"
            for (i, u) in list.enumerated() {
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { continue }
                bind(st, 1, u.id)
                bind(st, 2, sessionId)
                bind(st, 3, u.speaker)
                sqlite3_bind_double(st, 4, u.start)
                sqlite3_bind_double(st, 5, u.end)
                bind(st, 6, u.text)
                sqlite3_bind_int(st, 7, Int32(i))
                sqlite3_bind_double(st, 8, Date().timeIntervalSince1970)
                _ = sqlite3_step(st)
                sqlite3_finalize(st)
            }
            _ = exec("COMMIT;")
        }
    }

    func utterances(sessionId: String) -> [Utterance] {
        queue.sync {
            var st: OpaquePointer?
            let sql = "SELECT id, session_id, speaker, start_sec, end_sec, text, order_index FROM utterance WHERE session_id = ? ORDER BY order_index ASC, start_sec ASC;"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, 1, sessionId)
            var out: [Utterance] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Utterance(
                    id: col(st, 0),
                    sessionId: col(st, 1),
                    speaker: col(st, 2),
                    start: sqlite3_column_double(st, 3),
                    end: sqlite3_column_double(st, 4),
                    text: col(st, 5),
                    orderIndex: Int(sqlite3_column_int(st, 6))
                ))
            }
            return out
        }
    }

    func utteranceCount(sessionId: String) -> Int {
        queue.sync {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM utterance WHERE session_id = ?;", -1, &st, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(st) }
            bind(st, 1, sessionId)
            return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int(st, 0)) : 0
        }
    }

    // MARK: - 内部

    static let sessionCols = "id, mode, started_at, ended_at, state, speakers_json, event_id, error"

    private func readSession(_ st: OpaquePointer?) -> ListenSession {
        ListenSession(
            id: col(st, 0),
            modeRaw: col(st, 1),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
            endedAt: sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 3)),
            stateRaw: col(st, 4),
            speakersJSON: col(st, 5),
            eventId: sqlite3_column_type(st, 6) == SQLITE_NULL ? nil : col(st, 6),
            error: sqlite3_column_type(st, 7) == SQLITE_NULL ? nil : col(st, 7)
        )
    }
}
