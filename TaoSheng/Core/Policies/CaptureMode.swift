import Foundation

/// 持久化使用英文值；旧口播稿及未知模式安全回退为日常。
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case daily
    case meeting
    case training
    case call

    var id: String { rawValue }

    static func restored(_ raw: String) -> CaptureMode {
        CaptureMode(rawValue: raw) ?? .daily
    }

    var title: String {
        switch self {
        case .daily: return "日常"
        case .meeting: return "会议"
        case .training: return "培训"
        case .call: return "通话"
        }
    }

    var symbol: String {
        switch self {
        case .daily: return "sun.max"
        case .meeting: return "person.2.wave.2"
        case .training: return "graduationcap"
        case .call: return "phone.arrow.up.right"
        }
    }

    var hint: String {
        switch self {
        case .daily: return "合成一件事，不出纪要"
        case .meeting: return "多人讨论，结束后出会议纪要"
        case .training: return "一人主讲，不区分说话人，出培训笔记"
        case .call: return "两人一来一回，出通话记录"
        }
    }

    var maxSegment: Double {
        switch self {
        case .daily: return 180
        case .meeting: return 300
        case .training: return 600
        case .call: return 240
        }
    }

    var silenceGap: Double {
        switch self {
        case .daily: return 1.5
        case .meeting: return 2.5
        case .training: return 3
        case .call: return 1.8
        }
    }

    var separateSpeakers: Bool { self != .training }

    func sensitivity(_ configured: Double) -> Double {
        switch self {
        case .daily: return configured
        case .meeting, .call: return min(configured, 0.014)
        case .training: return min(configured, 0.018)
        }
    }
}
