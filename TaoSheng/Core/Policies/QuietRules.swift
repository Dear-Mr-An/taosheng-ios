import Foundation

/// 「暂停收音」的跨进程恢复规则（原版 QuickPause）。
///
/// 暂停时把 `captureWanted` 置 false，并把恢复时间写进本地。
/// App 被杀掉再打开时，只有这里能决定「还该不该继续停着」：
/// - 恢复时间还没到 → 继续暂停，等计时器到点；
/// - 恢复时间已经过了 → 必须把 `captureWanted` 设回 true 并重新拉起录音，
///   否则用户看到的是「暂停 15 分钟」，过了半小时仍然不录。
public enum QuietRules {

    public enum OnLaunch: Equatable {
        /// 暂停还没到期：继续保持暂停
        case stillPaused(until: Date)
        /// 暂停已经到期：启动时要把录音拉回来
        case expiredResume
        /// 没有暂停记录
        case idle
    }

    /// - Parameters:
    ///   - savedUntil: 本地记下的恢复时间
    ///   - heldByPause: 记下的时间是不是「暂停」写进去的（避免别的流程写坏同一个键时误开录音）
    ///   - now: 当前时间
    public static func onLaunch(savedUntil: Date?, heldByPause: Bool, now: Date) -> OnLaunch {
        guard let until = savedUntil else { return .idle }
        if until > now { return .stillPaused(until: until) }
        return heldByPause ? .expiredResume : .idle
    }
}
