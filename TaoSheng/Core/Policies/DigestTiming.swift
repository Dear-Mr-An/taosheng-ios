import Foundation

/// 什么时候整理：转写完就整理 / 按间隔 / 按时间点。
///
/// 0.6.5 之前只有「按间隔」和「按时间点」，董事长真机上的用法是「转出文字就要整理」，
/// 所以加了第一档并作为默认：录音落一段、转完一段，整理立刻跟上，不再等 30 分钟的定时器。
/// 会话（点开始聆听那一场）仍然留到点「结束」时整场整理，这里只处理没有会话的零散段。
public enum DigestTiming: String, CaseIterable, Identifiable {
    /// 转写完就整理（默认）
    case afterTranscribe
    /// 按间隔（多久整理一次）
    case interval
    /// 按时间点（每天几点）
    case clock

    public var id: String { rawValue }

    /// 老版本只存了 digestByInterval（true=按间隔）；没有记录时按「转写完就整理」算。
    public static func restored(_ raw: String?) -> DigestTiming {
        guard let raw = raw, let t = DigestTiming(rawValue: raw) else { return .afterTranscribe }
        return t
    }

    /// 迁移老数据：0.6.5 之前没有 digestTimingRaw，用 digestByInterval 推。
    /// - 没存过：新装的默认「转写完就整理」
    /// - true：老版本的默认值就是「按间隔」，用户多半没动过，直接升级到「转写完就整理」，
    ///   否则董事长升级完还是 30 分钟才整理一次
    /// - false：能存成 false 说明用户主动切到了「按时间点」，那是明确选择，保留
    public static func migrated(byInterval: Bool?) -> DigestTiming {
        guard let byInterval = byInterval else { return .afterTranscribe }
        return byInterval ? .afterTranscribe : .clock
    }

    public var title: String {
        switch self {
        case .afterTranscribe: return "转写完就整理"
        case .interval: return "按间隔"
        case .clock: return "按时间点"
        }
    }

    public var detail: String {
        switch self {
        case .afterTranscribe: return "转出一段文字就整理一次，会议中也能马上看到纪要"
        case .interval: return "隔一段时间把攒下的原话一起整理"
        case .clock: return "每天固定一个时间点整理"
        }
    }

    /// 定时器还要不要跑：第一档是靠转写完成事件驱动的，定时器空转只会白跑 SQL
    public var usesTimer: Bool { self != .afterTranscribe }
}

/// 转写完成之后要不要顺手整理一遍。纯逻辑，放这里是为了能单测。
public enum DigestTrigger {
    public static func afterTranscribe(timing: DigestTiming,
                                       newText: Bool,
                                       hasKey: Bool,
                                       working: Bool) -> Bool {
        timing == .afterTranscribe && newText && hasKey && !working
    }
}
