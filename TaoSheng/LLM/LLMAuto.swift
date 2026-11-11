import Foundation

/// 多模型自动切换：主模型失败（断网 / 余额 / 密钥失效）按顺序换备用
extension LLMClient {
    static func auto() -> LLMClient? {
        let s = Settings.shared
        let eff = s.effectiveLLM
        guard !eff.key.isEmpty else { return nil }
        return LLMClient(baseURL: eff.base, apiKey: eff.key, model: eff.model)
    }

    /// 依次尝试所有已配置服务商，全失败才抛错
    static func completeAny(system: String, user: String, temperature: Double = 0.3) async throws -> String {
        let s = Settings.shared
        var chain = s.activeProviders
        if chain.isEmpty {
            let eff = s.effectiveLLM
            if !eff.key.isEmpty {
                chain = [LLMProvider(id: "main", name: "主模型", baseURL: eff.base, model: eff.model, key: eff.key, note: "", builtin: false)]
            }
        }
        guard !chain.isEmpty else { throw TranscribeError.notConfigured }

        var lastError: Error = TranscribeError.notConfigured
        for p in chain {
            do {
                let client = LLMClient(baseURL: p.baseURL, apiKey: p.key, model: p.model)
                let text = try await client.complete(system: system, user: user, temperature: temperature)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                lastError = TranscribeError.empty
            } catch {
                lastError = error
                NSLog("涛声: 模型 \(p.name) 失败，尝试下一个 — \(error.localizedDescription)")
            }
        }
        throw lastError
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
