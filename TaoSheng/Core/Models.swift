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

    var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: startedAt)
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
