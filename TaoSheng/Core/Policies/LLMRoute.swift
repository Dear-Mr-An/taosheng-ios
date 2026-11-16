import Foundation

/// 大模型服务商的地址与模型解析规则。
/// 以前 `Settings.effectiveLLM` 固定返回 DeepSeek 官方地址与 deepseek-flash，
/// 页面却允许改成火山 / 硅基，结果「存了不用」——这里把规则收敛成一处，页面与执行共用。
public enum LLMRoute {
    public static let deepSeekBase = "https://api.deepseek.com"

    /// 规范化：去空白、去尾部斜杠
    public static func normalize(_ base: String) -> String {
        var v = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while v.hasSuffix("/") { v.removeLast() }
        return v
    }

    public static func isOfficialDeepSeek(_ base: String) -> Bool {
        guard let url = URL(string: normalize(base)) else { return false }
        return url.scheme == "https" && url.host?.lowercased() == "api.deepseek.com" && url.user == nil
    }

    /// 只有官方 DeepSeek 才能查余额；别的服务商一律不发请求，避免把 Key 送到 DeepSeek。
    public static func balanceSupported(base: String) -> Bool { isOfficialDeepSeek(base) }

    /// 执行时用的地址：用户保存的优先；没保存才回退官方默认。
    public static func resolveBase(stored: String) -> String {
        let v = normalize(stored)
        return v.isEmpty ? deepSeekBase : v
    }

    /// 执行时用的模型：原样使用（不强制替换成 deepseek-flash），空则给一个官方默认。
    public static func resolveModel(stored: String, official: Bool) -> String {
        let v = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { return v }
        return official ? "deepseek-flash" : ""
    }

    /// 拼 chat/completions 地址；已经带了就原样用。
    public static func chatURL(base: String) -> URL? {
        let b = resolveBase(stored: base)
        if b.lowercased().hasSuffix("/chat/completions") { return URL(string: b) }
        return URL(string: b + "/chat/completions")
    }
}