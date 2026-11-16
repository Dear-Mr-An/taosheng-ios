import Foundation

/// 原话与转写页上「语音转写」「多久转写一次」两个控件和真实设置值之间的映射。
/// 单独抽出来是因为这两个映射写错过一次（豆包档写到了 asrKey，引擎读不到）。
public enum ASRRules {
    /// 分段控件顺序：豆包 / 本地 / 自定义
    public static let kindIndex: [String] = ["doubao", "appleSpeech", "openAICompatible"]

    public static func index(kind: String) -> Int {
        kindIndex.firstIndex(of: kind) ?? 0
    }

    public static func kind(index: Int) -> String {
        guard index >= 0, index < kindIndex.count else { return kindIndex[0] }
        return kindIndex[index]
    }

    /// 分段顺序：实时 / 15 分钟 / 30 分钟 / 自定义
    public static let cadenceChoices: [Int] = [1, 15, 30, 0]

    public static func cadenceIndex(minutes: Int) -> Int {
        if minutes == 1 { return 0 }
        if minutes == 15 { return 1 }
        if minutes == 30 { return 2 }
        return 3
    }

    /// index == 3 时用用户自定义的分钟数（页面里 5…240，默认 45）
    public static func cadenceMinutes(index: Int, custom: Int) -> Int {
        guard index >= 0, index < cadenceChoices.count else { return 30 }
        let v = cadenceChoices[index]
        return v == 0 ? max(5, custom) : v
    }
}

/// 「有新待办就推」的判定：只推真正要做的事，事件不算。
public enum PushRules {
    public static func todoItems(_ categories: [String]) -> [Int] {
        var out: [Int] = []
        for (idx, c) in categories.enumerated() where c != "事件" { out.append(idx) }
        return out
    }

    public static func shouldPushTodo(enabled: Bool, categories: [String]) -> Bool {
        enabled && !todoItems(categories).isEmpty
    }
}

/// 「清空所有数据」时要一起清掉的密钥（Secure Enclave 之外的普通 Keychain 项）。
public enum WipeRules {
    public static let secrets: [String] = ["asrKey", "doubaoApiKey", "llmKey", "llm2Key", "backupPass"]

    /// 私密项之外的本地偏好：清空数据时一并删，避免残留账号信息。
    public static let defaultsKeys: [String] = [
        "rsQuietUntil", "rsQuietHeldWanted", "rsLastPauseMinutes",
        "rsAmapKey", "rsImportedFiles", "rsInstallAt"
    ]
}