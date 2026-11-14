import Foundation

/// 大模型侧的错误，文案要和「转写」区分开，否则用户会被误导去改转写设置
enum LLMError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case badReply(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没配置 DeepSeek。去 设置 → 模型与整理 → 编辑，填上 API Key。"
        case .http(let code, let body):
            return "大模型接口返回 \(code)：\(body.prefix(220))"
        case .badReply(let b):
            return "大模型返回看不懂：\(b.prefix(120))"
        }
    }
}

/// 整理、问问、回顾和技能统一走当前服务商（默认 DeepSeek），
/// 主服务商失败且开着「自动换备用」时，依次试备用的。
extension LLMClient {
    static func auto() -> LLMClient? {
        let s = Settings.shared
        let eff = s.effectiveLLM
        guard !eff.key.isEmpty else { return nil }
        return LLMClient(baseURL: eff.base, apiKey: eff.key, model: eff.model)
    }

    private static func run(_ client: LLMClient, system: String, user: String,
                            temperature: Double, thinking: Bool) async throws -> String {
        let text = try await client.complete(system: system, user: user,
                                             temperature: temperature, thinking: thinking)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.badReply("空回复")
        }
        return text
    }

    static func completeAny(system: String, user: String, temperature: Double = 0.3, thinking: Bool = false) async throws -> String {
        guard let primary = auto() else { throw LLMError.notConfigured }
        return try await run(primary, system: system, user: user,
                             temperature: temperature, thinking: thinking)
    }
}

/// 热词纠错：人名 / 公司名 / 行业词，转写后按表替换
enum HotwordFix {
    static func apply(_ text: String) -> String {
        guard Settings.shared.hotwordEnabled else { return text }
        let list = Store.shared.hotwords()
        guard !list.isEmpty else { return text }
        var out = text
        for h in list where !h.word.isEmpty {
            let target = h.replacement.isEmpty ? h.word : h.replacement
            if h.word != target {
                out = out.replacingOccurrences(of: h.word, with: target)
            }
        }
        return out
    }
}
