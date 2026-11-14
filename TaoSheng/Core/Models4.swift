import Foundation

/// 一场聆听会话：从「点开始」到「整理并推送完」的全过程都挂在这条记录上。
///
/// 为什么要落库而不是放内存：董事长是在会议里用，App 被杀、切走被系统回收都很常见，
/// 重启后必须能凭这条记录知道自己还有一场没处理完的会，而不是把录音和时间轴一起丢掉。
struct ListenSession: Identifiable, Hashable {
    var id: String
    var modeRaw: String
    var startedAt: Date
    var endedAt: Date?
    var stateRaw: String
    /// 说话人编号 → 显示名，例如 {"说话人1":"老王"}
    var speakersJSON: String
    var eventId: String?
    var error: String?

    var mode: CaptureMode { CaptureMode.restored(modeRaw) }
    var state: SessionState { SessionState(rawValue: stateRaw) ?? .failed }
    var day: String { DayKey.of(startedAt) }

    var speakers: [String: String] { JSONList.decodeMap(speakersJSON) }

    /// 显示名：改过名就用名字，没改过就是「说话人N」。
    func name(_ label: String) -> String {
        let n = speakers[label]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? label : n
    }

    var duration: Double {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    var durationText: String {
        let m = Int(duration / 60)
        if m < 1 { return "不到 1 分钟" }
        if m < 60 { return "\(m) 分钟" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }

    var timeRangeText: String {
        let a = Fmt.hm.string(from: startedAt)
        guard let e = endedAt else { return a }
        return "\(a) – \(Fmt.hm.string(from: e))"
    }

    /// 事件的场景由会话模式写死，避免整理时被大模型写成别的。
    var scene: String { SceneRules.scene(forMode: modeRaw) }
}

/// 一句话轮：整场识别出来的一段原话，带说话人和时间。
///
/// 段的转写是按段存的（粒度粗、说话人不可信），事件详情与原话页改用 utterance 显示，
/// 这样「谁在第几分钟说了什么」才是准的。
struct Utterance: Identifiable, Hashable {
    var id: String
    var sessionId: String
    var speaker: String      // 中文编号标签「说话人1」
    var start: Double        // 相对本场开始，秒
    var end: Double
    var text: String
    var orderIndex: Int

    var duration: Double { max(0, end - start) }

    var timeText: String {
        let total = Int(start)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func display(_ session: ListenSession) -> String { session.name(speaker) }
}

/// 会话在界面上的实时状态，录音中的英雄卡直接读它。
struct SessionProgress: Equatable {
    var session: ListenSession
    var liveLines: [String]     // 最近几行实时转写（没有说话人）
    var speakers: Int
    var pendingSegments: Int
}
