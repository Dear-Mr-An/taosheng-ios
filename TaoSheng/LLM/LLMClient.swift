import Foundation

/// OpenAI 兼容 chat/completions 客户端（DeepSeek / 豆包 / Kimi / 通义 / 本地 ollama 都能用）
struct LLMClient {
    let baseURL: String
    let apiKey: String
    let model: String

    struct Message: Codable {
        let role: String
        let content: String
    }

    func complete(system: String, user: String, temperature: Double = 0.3) async throws -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
        guard let url = URL(string: base) else {
            throw TranscribeError.http(0, "整理服务地址不对：\(baseURL)")
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
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
            throw TranscribeError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw TranscribeError.http(0, "整理结果解析失败")
        }
        return content
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
