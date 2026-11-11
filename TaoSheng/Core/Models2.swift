import Foundation

// MARK: - 人物（声纹认人）
struct Person: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var note: String
    var isMe: Bool
    var sampleCount: Int
    var createdAt: Date

    var color: (Double, Double, Double) { hexToRGB(colorHex) }
}

// MARK: - 声纹样本（一段话的声学特征向量，存 JSON 数组）
struct VoiceSample: Identifiable, Codable, Hashable {
    var id: String
    var personId: String
    var segmentId: String
    var vector: [Double]
    var createdAt: Date
}

// MARK: - 整理技能
enum SkillSchedule: String, Codable, CaseIterable, Identifiable {
    case manual        // 手动
    case daily         // 每天
    case weekly        // 每周
    case afterDigest   // 每次整理后

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: return "手动"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .afterDigest: return "每次整理后"
        }
    }
}

/// 技能卡片上的一个字段（原版 skill.json 的 fields[]）
struct SkillField: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var type: String        // text / paragraph / bullets / checklist / tags / quotes
    var required: Bool

    var id: String { key }

    var typeText: String {
        switch type {
        case "text": return "一句话"
        case "paragraph": return "一段话"
        case "bullets": return "要点"
        case "checklist": return "清单"
        case "tags": return "标签"
        case "quotes": return "原话"
        default: return "文本"
        }
    }

    static let text = SkillField(key: "text", label: "内容", type: "text", required: true)
    static let paragraph = SkillField(key: "text", label: "内容", type: "paragraph", required: true)
    static let bullets = SkillField(key: "points", label: "要点", type: "bullets", required: false)
}

struct SkillDef: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var desc: String
    var enabled: Bool
    var schedule: SkillSchedule
    var hour: Int
    var minute: Int
    var weekday: Int        // 1=周日
    var prompt: String      // 该技能的额外提示词
    var builtin: Bool
    var createdAt: Date
    var fields: [SkillField] = []

    var scheduleText: String {
        switch schedule {
        case .manual: return "手动运行"
        case .daily: return String(format: "每天 %02d:%02d", hour, minute)
        case .weekly: return String(format: "每周%@ %02d:%02d", SkillDef.weekName(weekday), hour, minute)
        case .afterDigest: return "每次整理后"
        }
    }

    static func weekName(_ w: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let i = min(max(w, 0), 6)
        return names[i]
    }
}

struct SkillRun: Identifiable, Codable, Hashable {
    var id: String
    var skillId: String
    var skillName: String
    var day: String
    var title: String
    var output: String
    var createdAt: Date
}

// MARK: - 推送通道
enum ChannelKind: String, Codable, CaseIterable, Identifiable {
    case agent          // 自定义接口（推给 Agent）
    case webhook        // 通用 Webhook
    case nutstore       // 坚果云同步文件夹
    case pushplus
    case wecom
    case feishu
    case telegram
    case bark
    case serverchan
    case ntfy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return "自定义接口"
        case .webhook: return "Webhook"
        case .nutstore: return "坚果云同步文件夹"
        case .pushplus: return "PushPlus"
        case .wecom: return "企业微信"
        case .feishu: return "飞书"
        case .telegram: return "Telegram"
        case .bark: return "Bark"
        case .serverchan: return "Server酱"
        case .ntfy: return "ntfy"
        }
    }

    var symbol: String {
        switch self {
        case .agent: return "square.stack.3d.up"
        case .webhook: return "link"
        case .nutstore: return "cloud"
        case .pushplus: return "paperplane"
        case .wecom: return "bubble.left.and.bubble.right"
        case .feishu: return "bird"
        case .telegram: return "paperplane.circle"
        case .bark: return "bell.badge"
        case .serverchan: return "envelope"
        case .ntfy: return "antenna.radiowaves.left.and.right"
        }
    }

    var detail: String {
        switch self {
        case .agent: return "增量：新增 / 修改 / 删除"
        case .webhook: return "POST JSON 到任意地址"
        case .nutstore: return "整理结果 5 类 · 原话 · 有变化就同步"
        case .pushplus: return "每日回顾 · 待办提醒"
        case .wecom: return "群机器人 Markdown"
        case .feishu: return "群机器人文本"
        case .telegram: return "Bot 私聊"
        case .bark: return "iPhone 推送"
        case .serverchan: return "微信推送"
        case .ntfy: return "自建 / 公共 topic"
        }
    }

    var needsURL: Bool { self != .nutstore }
    var urlHint: String {
        switch self {
        case .agent: return "https://your-agent.example.com/taosheng"
        case .webhook: return "https://..."
        case .pushplus: return "https://www.pushplus.plus/send"
        case .wecom: return "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=..."
        case .feishu: return "https://open.feishu.cn/open-apis/bot/v2/hook/..."
        case .telegram: return "https://api.telegram.org/bot<token>/sendMessage"
        case .bark: return "https://api.day.app/<key>"
        case .serverchan: return "https://sctapi.ftqq.com/<key>.send"
        case .ntfy: return "https://ntfy.sh/<topic>"
        case .nutstore: return "填账号与 WebDAV 路径"
        }
    }
}

struct Channel: Identifiable, Codable, Hashable {
    var id: String
    var kind: ChannelKind
    var name: String
    var url: String
    var extra: String        // token / topic / chat_id / 备注
    var enabled: Bool
    var lastPushAt: Date?
    var lastStatus: String
    var createdAt: Date
}

// MARK: - 足迹
struct PlaceVisit: Identifiable, Codable, Hashable {
    var id: String
    var day: String
    var name: String
    var latitude: Double
    var longitude: Double
    var arriveAt: Date
    var leaveAt: Date
    var isHome: Bool

    var durationText: String {
        let s = max(0, Int(leaveAt.timeIntervalSince(arriveAt).rounded()))
        if s < 60 { return "\(s)秒" }
        let m = s / 60
        if m < 60 { return "\(m)分钟" }
        return "\(m / 60)小时\(m % 60)分"
    }
}

// MARK: - 强提醒
struct Reminder: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var fireAt: Date
    var itemId: String
    var enabled: Bool
    var repeatDaily: Bool
    var createdAt: Date
}

// MARK: - 回顾
enum ReviewKind: String, Codable {
    case daily
    case weekly

    var title: String { self == .daily ? "每日回顾" : "每周回顾" }
}

struct ReviewRecord: Identifiable, Codable, Hashable {
    var id: String
    var kind: ReviewKind
    var day: String
    var headline: String
    var text: String
    var createdAt: Date
}

// MARK: - 问问
enum AskRole: String, Codable {
    case me
    case ai
}

struct AskMessage: Identifiable, Codable, Hashable {
    var id: String
    var role: AskRole
    var text: String
    var citations: [String]     // segment id
    var createdAt: Date
}

// MARK: - 热词
struct Hotword: Identifiable, Codable, Hashable {
    var id: String
    var word: String
    var replacement: String
    var createdAt: Date
}

// MARK: - 颜色工具
func hexToRGB(_ hex: String) -> (Double, Double, Double) {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    if s.count == 3 {
        s = s.map { "\($0)\($0)" }.joined()
    }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0.94, 0.51, 0.24) }
    let r = Double((v >> 16) & 0xFF) / 255.0
    let g = Double((v >> 8) & 0xFF) / 255.0
    let b = Double(v & 0xFF) / 255.0
    return (r, g, b)
}

let personPalette: [String] = [
    "#F0833E", "#4F8BE0", "#3FAE7B", "#D9695F",
    "#8C6FD1", "#D9A02C", "#4FB3C4", "#C46BA8"
]
