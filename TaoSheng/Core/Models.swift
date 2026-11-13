import Foundation

// MARK: - 段（一段人声录音）
enum SegmentState: String, Codable {
    case recorded      // 已录音，等待转写
    case transcribing  // 转写中
    case transcribed   // 已转写
    case failed        // 转写失败
}

struct Segment: Identifiable, Codable, Hashable {
    var id: String
    var startedAt: Date
    var endedAt: Date
    var duration: Double          // 秒
    var fileName: String          // 相对 Audio 目录
    var byteSize: Int
    var transcript: String
    var speaker: String
    var state: SegmentState
    var day: String               // yyyy-MM-dd（本机时区）
    var createdAt: Date
    var captureModeRaw: String? = nil
    /// 是否标了重点（只有从库里读出来的段才有值，新录的段是 nil）
    var starred: Bool? = nil

    var captureMode: CaptureMode { CaptureMode.restored(captureModeRaw ?? "") }

    var timeText: String {
        Fmt.hm.string(from: startedAt)
    }

    var durationText: String {
        let s = Int(duration.rounded())
        return s < 60 ? "\(s)秒" : "\(s / 60)分\(s % 60)秒"
    }

    var isEmptySpeech: Bool {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 整理出来的条目（事件 / 待办 / 约定 / 灵感 / 记忆）
enum ItemKind: String, Codable, CaseIterable {
    case event      // 发生的事
    case todo       // 待办
    case promise    // 约定
    case idea       // 灵感
    case memory     // 值得记住的信息（号码、地址、偏好）

    var title: String {
        switch self {
        case .event: return "事件"
        case .todo: return "待办"
        case .promise: return "约定"
        case .idea: return "灵感"
        case .memory: return "记忆"
        }
    }

    var symbol: String {
        switch self {
        case .event: return "clock"
        case .todo: return "checklist"
        case .promise: return "hand.raised"
        case .idea: return "lightbulb"
        case .memory: return "bookmark"
        }
    }
}

enum ItemStatus: String, Codable {
    case open
    case done
}

struct DigestItem: Identifiable, Codable, Hashable {
    var id: String
    var day: String
    var kind: ItemKind
    var title: String
    var detail: String
    var due: String          // 可读时间，如 "明天 15:00"
    var status: ItemStatus
    var createdAt: Date
}

// MARK: - 日整理记录
struct DigestRecord: Codable, Hashable {
    var day: String
    var summary: String
    var createdAt: Date
}

// MARK: - 工具
enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }

    static func date(from key: String) -> Date? { formatter.date(from: key) }

    static func display(_ key: String) -> String {
        guard let d = date(from: key) else { return key }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: d)
    }
}

func shortID() -> String {
    String(UUID().uuidString.prefix(8)).lowercased()
}

// MARK: - 待办时间解析（due 可能是 "明天 15:00" / "2026-11-12 15:00" / "15:00"）
extension DigestItem {
    static func parseHM(_ s: String) -> (Int, Int)? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " 点时"))
        let parts = t.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let m = Int(parts[1].prefix(2).trimmingCharacters(in: .whitespaces)) else { return nil }
        guard h >= 0, h < 24, m >= 0, m < 60 else { return nil }
        return (h, m)
    }

    var dueDate: Date? {
        let s = due.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for (prefix, offset) in [("今天", 0), ("明天", 1), ("后天", 2)] {
            guard s.hasPrefix(prefix) else { continue }
            let rest = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let base = cal.date(byAdding: .day, value: offset, to: today) ?? today
            if let hm = DigestItem.parseHM(rest) {
                return cal.date(bySettingHour: hm.0, minute: hm.1, second: 0, of: base) ?? base
            }
            return base
        }

        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = f1.date(from: s) { return d }

        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "zh_CN")
        f2.defaultDate = Date()
        f2.dateFormat = "M月d日 HH:mm"
        if let d = f2.date(from: s) { return d }

        if let hm = DigestItem.parseHM(s) {
            return cal.date(bySettingHour: hm.0, minute: hm.1, second: 0, of: Date())
        }
        return nil
    }

    var dueDisplay: String {
        guard let d = dueDate else { return due }
        let cal = Calendar.current
        let g = DateFormatter()
        g.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(d) { g.dateFormat = "今天 HH:mm" }
        else if cal.isDateInTomorrow(d) { g.dateFormat = "明天 HH:mm" }
        else { g.dateFormat = "M月d日 HH:mm" }
        return g.string(from: d)
    }

    /// 排序键：解析不出来的排最后
    var dueSortKey: Double { dueDate?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude }
}
