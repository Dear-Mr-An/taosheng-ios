import Foundation

/// 未知说话人聚类。
///
/// 声纹比对只能认出「已经建过人物卡」的人。会议里一堆没录入过的陌生人时，
/// 原版会照样给出「说话人 1 / 2 / 3」，靠的是把当天相似的声音聚成簇。
/// 这里按同一思路：先认熟人，认不出就按当天已有的簇做相似度匹配，
/// 匹配不上就新建一个簇，编号按当天出现顺序递增。
extension Store {
    func migrateVoiceCluster() {
        _ = exec("""
        CREATE TABLE IF NOT EXISTS voice_cluster (
            id TEXT PRIMARY KEY,
            day TEXT NOT NULL,
            no INTEGER NOT NULL,
            vector TEXT NOT NULL,
            hits INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL
        );
        """)
        _ = exec("CREATE INDEX IF NOT EXISTS idx_cluster_day ON voice_cluster(day, no);")
    }

    /// 当天已有的未知说话人簇（编号 + 中心向量）
    func clusters(day: String) -> [(no: Int, vector: [Double])] {
        var out: [(Int, [Double])] = []
        queue.sync {
            guard let db else { return }
            let sql = "SELECT no, vector FROM voice_cluster WHERE day = ? ORDER BY no"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let q = st else { return }
            bind(q, 1, day)
            while sqlite3_step(q) == SQLITE_ROW {
                let no = Int(sqlite3_column_int(q, 0))
                let raw = col(q, 1)
                let v = raw.split(separator: ",").compactMap { Double($0) }
                if !v.isEmpty { out.append((no, v)) }
            }
            sqlite3_finalize(q)
        }
        return out
    }

    func nextClusterNo(day: String) -> Int {
        var maxNo = 0
        queue.sync {
            guard let db else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(no), 0) FROM voice_cluster WHERE day = ?", -1, &st, nil) == SQLITE_OK, let q = st else { return }
            bind(q, 1, day)
            if sqlite3_step(q) == SQLITE_ROW { maxNo = Int(sqlite3_column_int(q, 0)) }
            sqlite3_finalize(q)
        }
        return maxNo + 1
    }

    func insertCluster(day: String, no: Int, vector: [Double]) {
        queue.sync {
            guard let db else { return }
            let sql = "INSERT OR REPLACE INTO voice_cluster (id, day, no, vector, hits, created_at) VALUES (?,?,?,?,1,?)"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let q = st else { return }
            bind(q, 1, "\(day)#\(no)")
            bind(q, 2, day)
            sqlite3_bind_int(q, 3, Int32(no))
            bind(q, 4, Self.encodeVector(vector))
            sqlite3_bind_double(q, 5, Date().timeIntervalSince1970)
            sqlite3_step(q)
            sqlite3_finalize(q)
        }
    }

    /// 命中已有簇时把中心向量往新样本挪一点，让后面的判断越来越稳
    func updateCluster(day: String, no: Int, vector: [Double]) {
        queue.sync {
            guard let db else { return }
            var st: OpaquePointer?
            let sql = "SELECT vector, hits FROM voice_cluster WHERE id = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let q = st else { return }
            bind(q, 1, "\(day)#\(no)")
            var old: [Double] = []
            var hits = 1
            if sqlite3_step(q) == SQLITE_ROW {
                old = col(q, 0).split(separator: ",").compactMap { Double($0) }
                hits = max(1, Int(sqlite3_column_int(q, 1)))
            }
            sqlite3_finalize(q)
            guard old.count == vector.count else { return }
            let w = 1.0 / Double(hits + 1)
            let merged = zip(old, vector).map { $0 * (1 - w) + $1 * w }

            var up: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE voice_cluster SET vector = ?, hits = ? WHERE id = ?", -1, &up, nil) == SQLITE_OK, let u = up else { return }
            bind(u, 1, Self.encodeVector(merged))
            sqlite3_bind_int(u, 2, Int32(hits + 1))
            bind(u, 3, "\(day)#\(no)")
            sqlite3_step(u)
            sqlite3_finalize(u)
        }
    }

    /// 把某一天已经写进 segment.speaker 的「说话人N」重排成人名，用于用户事后指认
    func renameSpeaker(day: String, from: String, to: String) {
        queue.sync {
            guard let db else { return }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE segment SET speaker = ? WHERE day = ? AND speaker = ?", -1, &st, nil) == SQLITE_OK, let q = st else { return }
            bind(q, 1, to)
            bind(q, 2, day)
            bind(q, 3, from)
            sqlite3_step(q)
            sqlite3_finalize(q)
        }
    }

    static func encodeVector(_ v: [Double]) -> String {
        v.map { String(format: "%.5f", $0) }.joined(separator: ",")
    }
}
