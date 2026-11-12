import Foundation

/// 所有访问由调用方串行化。权限弹窗等异步工作只可提交到仍有效的会话。
struct VoiceSessionState {
    private var generation: UInt64 = 0
    private var active = false

    mutating func begin() -> UInt64 {
        generation &+= 1
        active = true
        return generation
    }

    mutating func cancel() {
        generation &+= 1
        active = false
    }

    func isCurrent(_ token: UInt64) -> Bool {
        active && generation == token
    }
}
