import Foundation

/// 只有两种用法：开会、培训。持久化仍用英文值。
///
/// 0.6.1 起去掉「日常」和「通话」：董事长只用这两种场景，多一个模式只会让录音静默、
/// 让统计和提醒多一种分支。老数据里的 daily / script / call 一律按会议处理——
/// 会议是最接近「一段有内容的对话」的默认，宁可算进会议，也不要让它变成没人认领的账。
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case meeting
    case training

    var id: String { rawValue }

    static func restored(_ raw: String) -> CaptureMode {
        switch raw {
        case CaptureMode.training.rawValue: return .training
        default: return .meeting   // meeting / daily / script / call / 未知值
        }
    }

    /// 会话中段的切分：停顿满 0.8 秒或长度满 20 秒就切，切完立刻转写。
    /// 会议里等 2.5 秒判停会让实时字幕迟到半分钟，所以实时转写用另一套更短的阈值。
    static let liveSilenceGap: Double = 0.8
    static let liveMaxSegment: Double = 20

    var title: String {
        switch self {
        case .meeting: return "会议"
        case .training: return "培训"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: return "person.2.wave.2"
        case .training: return "graduationcap"
        }
    }

    var hint: String {
        switch self {
        case .meeting: return "多人讨论，结束后分清谁说的，出会议速记"
        case .training: return "一人主讲，不分说话人，出培训笔记"
        }
    }

    /// 速记的名字：会议速记 / 培训笔记
    var noteTitle: String { NoteRules.noteTitle(forMode: rawValue) }

    /// 时间线上的小标签：速记 / 笔记
    var noteTag: String { NoteRules.tag(forMode: rawValue) }

    /// 事件场景由代码按模式写死，不让大模型改
    var scene: String { NoteRules.scene(forMode: rawValue) }

    var maxSegment: Double {
        switch self {
        case .meeting: return 300
        case .training: return 600
        }
    }

    var silenceGap: Double {
        switch self {
        case .meeting: return 2.5
        case .training: return 3
        }
    }

    /// 培训是一人主讲，不区分说话人（分人反而把一个讲师拆成好几个人）
    var separateSpeakers: Bool { self == .meeting }

    func sensitivity(_ configured: Double) -> Double {
        switch self {
        case .meeting: return min(configured, 0.014)
        case .training: return min(configured, 0.018)
        }
    }
}
