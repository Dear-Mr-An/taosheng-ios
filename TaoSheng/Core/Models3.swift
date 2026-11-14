import Foundation

// MARK: - 事件（对应原版 memory_events）

struct MemoryEvent: Identifiable, Hashable {
    var id: String
    var day: String
    var startAt: Date
    var endAt: Date?
    var scene: String          // 会议 上课 闲聊 电话 独白 媒体 其他
    var title: String
    var summary: String
    var points: [String]
    var people: [String]
    var place: String?
    var emotion: String
    var intensity: Int
    var important: Bool
    var starred: Bool
    var starredAt: Date?
    var entityId: String?
    var lineFrom: Int
    var lineTo: Int
    var createdAt: Date
    /// 这一件事是哪个「聆听会话」整理出来的；散段整理的为 nil
    var sessionId: String? = nil
    /// 速记里的关键原话（3–5 条，带说话人和时间）；老数据为空
    var quotes: [EventQuote] = []

    var timeText: String {
        Fmt.hm.string(from: startAt)
    }

    /// 这一件是不是「一场会/一场培训」的速记（按场整理的才有 sessionId）
    var isNote: Bool {
        guard let s = sessionId else { return false }
        return !s.isEmpty
    }

    /// 会议速记 / 培训笔记（场景写死，0.6.0 起会话事件就是这样）
    var noteTitle: String {
        NoteRules.noteTitle(forMode: scene == "培训" ? "training" : "meeting")
    }

    /// 时间线上的小标签：速记 / 笔记
    var noteTag: String { NoteRules.tag(forScene: scene) }

    /// 结论第一句（「刚结束」卡、时间线两行摘要都用它）
    var conclusion: String { NoteRules.conclusion(summary) }

    /// 速记的分段（议题/结论先行/要点/决定 或 主题/核心要点/知识点/行动）
    var noteSections: [NoteSection] {
        NoteRules.sections(forMode: scene == "培训" ? "training" : "meeting", points: points)
    }

    var durationText: String {
        guard let e = endAt else { return "" }
        let m = Int(e.timeIntervalSince(startAt) / 60)
        if m < 1 { return "不到 1 分钟" }
        if m < 60 { return "\(m) 分钟" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }

    /// 「三分 12 秒」这种时长说法，纪要里标每人发言时长用
    /// 「14:51–15:00」这种起止时间，速记卡片和抽屉的副标题用
    var timeRangeText: String {
        let s = Fmt.hm.string(from: startAt)
        guard let end = endAt else { return s }
        let e = Fmt.hm.string(from: end)
        return s == e ? s : "\(s)–\(e)"
    }

    static func durationLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) 秒" }
        let m = s / 60
        if m < 60 { return s % 60 == 0 ? "\(m) 分钟" : "\(m) 分 \(s % 60) 秒" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }

    static let scenes = ["会议", "上课", "闲聊", "电话", "独白", "媒体", "其他"]
    static let emotions = ["平静", "愉快", "兴奋", "焦虑", "烦躁", "低落", "生气", "疲惫", "紧张"]

    static func sceneSymbol(_ scene: String) -> String {
        switch scene {
        case "会议": return "person.3.fill"
        case "上课": return "book.fill"
        case "电话": return "phone.fill"
        case "独白": return "person.fill"
        case "媒体": return "play.rectangle.fill"
        case "闲聊": return "bubble.left.and.bubble.right.fill"
        default: return "circle.grid.2x2.fill"
        }
    }
}

// MARK: - 提取项（对应原版 memory_items，四态）

enum MemItemStatus: String {
    case pending    // 待确认
    case accepted   // 进行中
    case done       // 已完成
    case ignored    // 已忽略

    var title: String {
        switch self {
        case .pending: return "待确认"
        case .accepted: return "进行中"
        case .done: return "已完成"
        case .ignored: return "已忽略"
        }
    }
}

struct MemoryItem: Identifiable, Hashable {
    var id: String
    var eventId: String?
    var day: String
    var category: String       // 待办 约定 备忘 灵感 关键信息 决定 知识
    var kind: String?          // 我要做 我答应别人 别人答应我
    var content: String
    var status: MemItemStatus
    var dueText: String?
    var dueAt: Date?
    var who: String?
    var sourceText: String?
    var createdAt: Date
    var updatedAt: Date

    static let categories = ["待办", "约定", "备忘", "灵感", "关键信息", "决定", "知识"]

    static func categorySymbol(_ c: String) -> String {
        switch c {
        case "待办": return "checkmark.circle"
        case "约定": return "calendar"
        case "备忘": return "pin"
        case "灵感": return "lightbulb"
        case "关键信息": return "key"
        case "决定": return "flag"
        default: return "book"
        }
    }

    static func categoryColor(_ c: String) -> String {
        switch c {
        case "待办": return "#F0833E"
        case "约定": return "#457ACF"
        case "备忘": return "#8B8279"
        case "灵感": return "#E5962D"
        case "关键信息": return "#34A669"
        case "决定": return "#8B5CF6"
        default: return "#ADA59C"
        }
    }

    var dueDisplay: String? {
        if let t = dueText, !t.isEmpty { return t }
        guard let d = dueAt else { return nil }
        return Fmt.monthDayTime.string(from: d)
    }
}

// MARK: - 技能卡（对应原版 skill_cards）

struct SkillCard: Identifiable, Hashable {
    var id: String
    var skillId: String
    var skillName: String
    var day: String
    var startAt: Date?
    var endAt: Date?
    var entityId: String?
    var fields: [String: String]
    var quotes: [String]
    var nothingReason: String?
    var createdAt: Date

    var isNothing: Bool { (nothingReason?.isEmpty == false) }

    func value(_ key: String) -> String { fields[key] ?? "" }
}

// MARK: - 寻物（对应原版 things / thing_facts）

struct Thing: Identifiable, Hashable {
    var id: String
    var name: String
    var aliases: [String]
    var owner: String          // Mine Family Others
    var place: String?
    var holder: String?
    var updatedAt: Date

    var ownerText: String {
        switch owner {
        case "Mine": return "我的"
        case "Family": return "家里的"
        default: return "别人的"
        }
    }
}

struct ThingFact: Identifiable, Hashable {
    var id: String
    var thingId: String
    var action: String         // Placed Lent Returned TakenAway
    var place: String?
    var who: String?
    var lineId: String?
    var confident: Bool
    var at: Date

    var actionText: String {
        switch action {
        case "Placed": return "放在"
        case "Lent": return "借给"
        case "Returned": return "归还"
        case "TakenAway": return "带走"
        default: return action
        }
    }

    var actionSymbol: String {
        switch action {
        case "Placed": return "mappin.and.ellipse"
        case "Lent": return "arrow.right.circle"
        case "Returned": return "arrow.uturn.left.circle"
        default: return "figure.walk"
        }
    }
}

// MARK: - JSON 小工具

enum JSONList {
    static func encode(_ arr: [String]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: arr, options: []),
              let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    static func decode(_ s: String?) -> [String] {
        guard let s, let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return o
    }

    static func encodeMap(_ m: [String: String]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: m, options: []),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    static func decodeMap(_ s: String?) -> [String: String] {
        guard let s, let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }
}
