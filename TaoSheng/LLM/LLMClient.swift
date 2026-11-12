import Foundation

/// DeepSeek chat/completions 客户端。
struct LLMClient {
    let baseURL: String
    let apiKey: String
    let model: String

    struct Message: Codable {
        let role: String
        let content: String
    }

    func complete(system: String, user: String, temperature: Double = 0.3, thinking: Bool = false) async throws -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
        guard let url = URL(string: base) else {
            throw LLMError.http(0, "接口地址不对：\(baseURL)")
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "thinking": ["type": thinking ? "enabled" : "disabled"],
            "max_tokens": thinking ? 32768 : 8192,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 180
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let choice = choices.first,
              let msg = choice["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw LLMError.badReply(String(data: data, encoding: .utf8) ?? "")
        }
        guard choice["finish_reason"] as? String != "length" else {
            throw LLMError.badReply("输出过长被截断，请减少本次整理内容后重试")
        }
        try Task.checkCancellation()
        return content
    }

    /// 连通性测试：发一条最小请求，验证地址 / 模型 / Key 三样都对
    func ping() async throws -> String {
        let reply = try await complete(
            system: "你是连通性测试助手，只回答被要求的那几个字。",
            user: "只回复两个字：正常",
            temperature: 0
        )
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw LLMError.badReply("空回复") }
        return t
    }
}

/// 从模型回复里抠出 JSON（容忍 ```json 包裹、前后废话）
enum JSONExtract {
    static func object(from text: String) -> [String: Any]? {
        var s = text
        if let r = s.range(of: "```json") {
            s = String(s[r.upperBound...])
            if let end = s.range(of: "```") { s = String(s[..<end.lowerBound]) }
        } else if let r = s.range(of: "```") {
            s = String(s[r.upperBound...])
            if let end = s.range(of: "```") { s = String(s[..<end.lowerBound]) }
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            s = String(s[start...end])
        }
        guard let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
