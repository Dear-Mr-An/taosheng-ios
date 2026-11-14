import Foundation

/// 持久化使用英文值。历史上还有 daily（日常）与 script，现在都归到会议：
/// 董事长只用「开会」这一种用法，留着日常模式只会让录音静默、节律统计算错。
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case meeting
    case training
    case call

    var id: String { rawValue }

    static func restored(_ raw: String) -> CaptureMode {
        switch raw {
        case CaptureMode.training.rawValue: return .training
        case CaptureMode.call.rawValue: return .call
        default: return .meeting   // meeting / daily / script / 未知值
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
        case .call: return "通话"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: return "person.2.wave.2"
        case .training: return "graduationcap"
        case .call: return "phone.arrow.up.right"
        }
    }

    var hint: String {
        switch self {
        case .meeting: return "多人讨论，结束后分清谁说的，出会议纪要"
        case .training: return "一人主讲，不区分说话人，出培训笔记"
        case .call: return "两人一来一回，出通话记录"
        }
    }

    var maxSegment: Double {
        switch self {
        case .meeting: return 300
        case .training: return 600
        case .call: return 240
        }
    }

    var silenceGap: Double {
        switch self {
        case .meeting: return 2.5
        case .training: return 3
        case .call: return 1.8
        }
    }

    var separateSpeakers: Bool { self != .training }

    func sensitivity(_ configured: Double) -> Double {
        switch self {
        case .meeting, .call: return min(configured, 0.014)
        case .training: return min(configured, 0.018)
        }
    }
}
