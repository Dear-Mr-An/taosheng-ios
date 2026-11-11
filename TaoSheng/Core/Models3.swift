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

    var timeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: startAt)
    }

    var durationText: String {
        guard let e = endAt else { return "" }
        let m = Int(e.timeIntervalSince(startAt) / 60)
        if m < 1 { return "不到 1 分钟" }
        if m < 60 { return "\(m) 分钟" }
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
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
