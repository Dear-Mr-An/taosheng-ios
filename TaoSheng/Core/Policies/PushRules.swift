import Foundation

/// 推送通道的纯逻辑：URL 怎么拼、响应体算不算失败、正文按什么长度截断。
/// 放在 Policies 里是为了能在 CI 上跑单测（这几处以前都出过真实的推不出去的问题）。
public enum PushRules {

    /// ntfy：extra 是频道名；为空时把地址本身当频道地址。
    /// 以前的实现 base + "/" + topic 会把 `https://ntfy.sh/abc` 拼成 `/abc/abc`。
    public static func ntfyURL(url: String, extra: String) -> URL? {
        let rawURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = extra.trimmingCharacters(in: .whitespacesAndNewlines)

        if topic.isEmpty {
            guard let u = URL(string: rawURL),
                  let scheme = u.scheme, scheme.hasPrefix("http"),
                  !(u.path.isEmpty || u.path == "/") else { return nil }
            return u
        }
        let base = rawURL.isEmpty ? "https://ntfy.sh" : rawURL
        guard let u = URL(string: base),
              let host = u.host, let scheme = u.scheme else { return nil }
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = u.port
        comps.path = "/" + topic.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return comps.url
    }

    /// 各家的业务错误码：HTTP 200 不代表推成功
    public static func isFailure(kind: String, body: [String: Any]?) -> String? {
        guard let body else { return nil }
        switch kind {
        case "pushplus":
            if let code = int(body["code"]), code != 200 { return str(body["msg"]) ?? "code \(code)" }
        case "wecom":
            if let code = int(body["errcode"]), code != 0 { return str(body["errmsg"]) ?? "errcode \(code)" }
        case "feishu":
            if let code = int(body["code"]), code != 0 { return str(body["msg"]) ?? "code \(code)" }
        case "serverchan":
            if let code = int(body["code"]), code != 0 { return str(body["message"]) ?? "code \(code)" }
        case "telegram":
            if let ok = body["ok"] as? Bool, !ok { return str(body["description"]) ?? "ok=false" }
        case "bark":
            if let code = int(body["code"]), code != 200 { return str(body["message"]) ?? "code \(code)" }
        default:
            break
        }
        return nil
    }

    /// 按 UTF-8 字节截断（企微按字节算上限，超了整个请求会被拒）
    public static func clampBytes(_ text: String, _ max: Int) -> String {
        guard max > 0 else { return "" }
        let data = Data(text.utf8)
        guard data.count > max else { return text }
        // 从尾部退到合法的 UTF-8 边界，避免切出半个汉字
        var cut = max
        var head = ""
        let slice = data.prefix(max)
        while cut > 0 {
            if let s = String(data: Data(slice.prefix(cut)), encoding: .utf8) {
                head = s
                break
            }
            cut -= 1
        }
        return head + "…（内容过长已截断）"
    }

    public static func clampChars(_ text: String, _ max: Int) -> String {
        guard max > 0 else { return "" }
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…（内容过长已截断）"
    }

    /// 周几：Calendar 的 weekday 是 1=周日…7=周六，显示名从周日开始排
    public static func weekName(_ weekday: Int) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let n = weekday == 0 ? 1 : min(max(weekday, 1), 7)
        return names[(n + 6) % 7]
    }

    /// 整理失败后的重试间隔：逐次翻倍，最长 1 小时
    public static func retryDelay(streak: Int) -> TimeInterval {
        guard streak > 0 else { return 300 }
        let capped = min(streak, 8)
        return min(3600, 300 * pow(2, Double(capped - 1)))
    }

    /// LIKE 里的特殊字符要转义，否则用户搜 `%` 会把整库都搜出来
    public static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func str(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        return s
    }
}
