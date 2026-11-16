import Foundation

/// 专题（会议 / 培训 / 通话·访谈 / 口播稿 / 普通）的计划结束规则。
/// 与 Android 原版 TopicUi 的「什么时候结束」四选对应：0 = 我来结束，其余为分钟数。
public enum TopicRules {
    /// 0 分钟表示「我来结束」→ 没有计划结束时间。
    public static func endAt(start: Date, minutes: Int) -> Date? {
        guard minutes > 0 else { return nil }
        return start.addingTimeInterval(Double(minutes) * 60)
    }

    /// 到点该不该自动收尾。只有「还在录音」且计划时间已过才返回 true。
    public static func shouldAutoFinish(endAt: Date?, now: Date, isRecording: Bool) -> Bool {
        guard isRecording, let endAt else { return false }
        return now >= endAt
    }

    /// 记录标题：用户写的名字优先，没写就用类型名。
    public static func displayName(_ name: String, kind: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind : trimmed
    }
}