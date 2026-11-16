import Foundation

/// 停止 / 恢复的判定。
/// 两种停止必须区分：用户明确点「停止」就该一直停着；
/// 一场专题自己结束则按「默认一直聆听」恢复普通收音。
public enum StopReason: String {
    case userStop
    case sessionEnd
}

public enum StopRules {
    /// 回前台 / 重启时要不要自动拉起录音：用户手动停过就不拉。
    public static func shouldAutoStart(captureWanted: Bool, userStopped: Bool) -> Bool {
        captureWanted && !userStopped
    }

    /// 一场会结束时要不要接着普通聆听：默认一直听、且不是用户停的就恢复。
    public static func shouldResumeAfterSessionEnd(reason: StopReason, alwaysListening: Bool) -> Bool {
        reason == .sessionEnd && alwaysListening
    }

    /// 用户点停止后要落的状态
    public static func stateAfterUserStop() -> (captureWanted: Bool, userStopped: Bool) {
        (false, true)
    }
}

/// 录音输入的选择规则（手机麦克风 / 自动 / 指定设备）。
public enum MicChoice: Equatable {
    case systemDefault
    case builtIn
    case external
    case specific(String)
}

public enum MicRules {
    /// uid 为空 = 明确要手机麦克风；"auto" = 有外接就用外接；其它 = 指定设备。
    public static func choice(uid: String, hasExternal: Bool) -> MicChoice {
        let v = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return .builtIn }
        if v == "auto" { return hasExternal ? .external : .builtIn }
        return .specific(v)
    }

    /// 「自动」在插拔后要保留偏好，不能把 auto 清成空串
    public static func keepUidAfterReplug(_ uid: String) -> String { uid }

    /// 路由变化时只清掉已经不存在的具体设备；auto 是策略值，不是设备 UID。
    public static func uidAfterRouteChange(preferredUID: String, availableUIDs: [String]) -> String {
        let uid = preferredUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, uid != "auto" else { return uid }
        return availableUIDs.contains(uid) ? uid : ""
    }
}
