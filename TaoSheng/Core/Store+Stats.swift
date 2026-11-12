import Foundation
import SQLite3

extension Store {
    /// 近 days 天里已经转写好的总时长（分钟），用来算云端转写的花费。
    func transcribedMinutes(days: Int) -> Double {
        let since = DayKey.of(Date().addingTimeInterval(-Double(max(days, 1)) * 86_400))
        var total: Double = 0
        queue.sync {
            let sql = "SELECT COALESCE(SUM(duration), 0) FROM segment WHERE transcript <> '' AND day >= ?"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let q = st else { return }
            defer { sqlite3_finalize(q) }
            bind(q, 1, since)
            if sqlite3_step(q) == SQLITE_ROW {
                total = sqlite3_column_double(q, 0)
            }
        }
        return total
    }

    /// 原始录音占用的字节数
    func audioBytes() -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Store.audioDir,
                                                     includingPropertiesForKeys: [.fileSizeKey],
                                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for u in items {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(v?.fileSize ?? 0)
        }
        return total
    }

    /// 今天录了几段、其中转好几段
    func todayTranscribeProgress() -> (total: Int, done: Int) {
        var total = 0
        var done = 0
        let day = DayKey.of(Date())
        queue.sync {
            let sql = "SELECT COUNT(*), SUM(CASE WHEN transcript <> '' THEN 1 ELSE 0 END) FROM segment WHERE day = ?"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let q = st else { return }
            defer { sqlite3_finalize(q) }
            bind(q, 1, day)
            if sqlite3_step(q) == SQLITE_ROW {
                total = Int(sqlite3_column_int(q, 0))
                done = Int(sqlite3_column_int(q, 1))
            }
        }
        return (total, done)
    }
}

enum ByteText {
    static func short(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}
