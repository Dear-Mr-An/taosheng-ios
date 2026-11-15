import Foundation

/// 原版 0.4.0 的五种专题：会议、培训、通话·访谈、口播稿、普通。
/// 持久化仍用英文值；老数据里的 daily / 未知值一律按会议处理。
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case meeting
    case training
    case call
    case script
    case normal

    var id: String { rawValue }

    static func restored(_ raw: String) -> CaptureMode {
        switch raw {
        case CaptureMode.training.rawValue: return .training
        case CaptureMode.call.rawValue: return .call
        case CaptureMode.script.rawValue: return .script
        case CaptureMode.normal.rawValue: return .normal
        default: return .meeting   // meeting / daily / 未知值
        }
    }

    var title: String {
        switch self {
        case .meeting: return "会议"
        case .training: return "培训"
        case .call: return "通话·访谈"
        case .script: return "口播稿"
        case .normal: return "普通"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: return "person.2.wave.2"
        case .training: return "lightbulb"
        case .call: return "bubble.left.and.bubble.right"
        case .script: return "mic"
        case .normal: return "chart.bar.xaxis"
        }
    }

    var hint: String {
        switch self {
        case .meeting: return "多人讨论，结束后出会议纪要"
        case .training: return "一人主讲，不区分说话人，出培训笔记"
        case .call: return "两人一来一回，出通话记录"
        case .script: return "对着手机口述，出整理版和原话版两份稿子"
        case .normal: return "合成一件事，不出纪要"
        }
    }

    /// 速记的名字：会议速记 / 培训笔记 / 通话记录 / 口播稿 / 记录
    var noteTitle: String { NoteRules.noteTitle(forMode: rawValue) }

    /// 时间线上的小标签：速记 / 笔记 / 通话 / 口播 / 记录
    var noteTag: String { NoteRules.tag(forMode: rawValue) }

    /// 事件场景由代码按模式写死，不让大模型改
    var scene: String { NoteRules.scene(forMode: rawValue) }

    var maxSegment: Double {
        switch self {
        case .meeting: return 300
        case .training: return 600
        case .call: return 240
        case .script: return 180
        case .normal: return 300
        }
    }

    var silenceGap: Double {
        switch self {
        case .meeting: return 2.5
        case .training: return 3
        case .call: return 1.8
        case .script: return 1.5
        case .normal: return 2.5
        }
    }

    /// 会议和通话要分清谁说的；培训是一人主讲，口播稿和普通不需要分人
    var separateSpeakers: Bool { self == .meeting || self == .call }

    func sensitivity(_ configured: Double) -> Double {
        switch self {
        case .meeting: return min(configured, 0.014)
        case .training: return min(configured, 0.018)
        case .call: return min(configured, 0.012)
        case .script: return min(configured, 0.020)
        case .normal: return min(configured, 0.016)
        }
    }
}