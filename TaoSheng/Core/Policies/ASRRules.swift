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

    /// 自定义转写地址以页面保存的 asrBaseURL 为准；
    /// asrFullURL 只在老数据没有新地址时兜底，避免旧值悄悄覆盖用户刚改的地址。
    public static func endpoint(base: String, legacyFull: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty { return b }
        return legacyFull.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 需要联网上传的引擎（本地 Apple 识别不需要网络门禁）
    public static func needsNetwork(kind: String) -> Bool {
        kind != "appleSpeech"
    }

    /// OpenAI 兼容接口 2xx 的响应怎么算「真的识别成功」。
    /// 只认 JSON 里非空 text，或明确 text/plain 的非空纯文本；
    /// HTML、{"error":…}、{text:""} 都要按坏回复算，保留 failed 可重试。
    public enum Reply: Equatable {
        case text(String)
        case bad(String)
    }

    public static func parseReply(contentType: String, body: Data) -> Reply {
        let ctype = contentType.lowercased()
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let text = obj["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return .text(trimmed) }
                return .bad("返回的 text 是空的")
            }
            let detail = (obj["error"] as? [String: Any])?["message"] as? String
                ?? (obj["error"] as? String)
                ?? "返回里没有 text"
            return .bad(detail)
        }
        if ctype.contains("text/plain"), let text = String(data: body, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return .text(trimmed) }
            return .bad("纯文本响应是空的")
        }
        let raw = String(data: body, encoding: .utf8) ?? ""
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
        return .bad(head.isEmpty ? "空响应" : "不是识别结果：\(head)")
    }
}

/// 「有新待办就推」的判定：只推真正要做的事，事件不算。
/// 注意：`PushRules` 这个名字已经被推送通道的纯逻辑占用，这里叫 `PushGate`。
public enum PushGate {
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