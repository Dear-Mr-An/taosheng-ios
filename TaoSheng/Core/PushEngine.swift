import Foundation

/// 推送通道：把整理结果 / 回顾推到 Agent、坚果云、PushPlus 等
final class PushEngine {
    static let shared = PushEngine()

    private let store = Store.shared

    // MARK: - 对外

    func pushDigest(day: String, summary: String, items: [MemoryItem], transcript: String) {
        guard Settings.shared.pushOnDigest else { return }
        var md = "# 涛声 · \(day)\n\n\(summary)\n\n"
        if !items.isEmpty {
            md += "## 提取到的事\n"
            for i in items {
                let mark = i.status == .done ? "[x]" : "[ ]"
                md += "- \(mark) \(i.category)：\(i.content)"
                if let d = i.dueDisplay, !d.isEmpty { md += "（\(d)）" }
                md += "\n"
            }
        }
        md += "\n## 原话\n\(transcript)"
        broadcast(title: "涛声 · \(day) 整理完成", body: md)
    }

    func pushCard(_ c: SkillCard) {
        guard Settings.shared.pushOnDigest, !c.isNothing else { return }
        var md = "# \(c.skillName) · \(c.day)\n\n"
        for k in c.fields.keys.sorted() {
            md += "**\(k)**\n\(c.fields[k] ?? "")\n\n"
        }
        if !c.quotes.isEmpty {
            md += "## 原话\n" + c.quotes.map { "> \($0)" }.joined(separator: "\n")
        }
        broadcast(title: "涛声 · \(c.skillName)", body: md)
    }

    func pushReview(_ r: ReviewRecord) {
        broadcast(title: "涛声 · \(r.day) \(r.kind.title)", body: "# \(r.headline)\n\n\(r.text)")
    }

    func broadcast(title: String, body: String) {
        let list = store.channels().filter { $0.enabled }
        guard !list.isEmpty else { return }
        // 多通道时只发一次全局刷新，避免 N 个通道触发 N 次全量 AppState.refresh()
        Task {
            await withTaskGroup(of: Void.self) { group in
                for c in list {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        do {
                            try await self.send(c, title: title, body: body)
                            self.store.markChannelPushed(id: c.id, status: "已送达")
                        } catch {
                            self.store.markChannelPushed(id: c.id, status: "失败：\(error.localizedDescription.prefix(40))")
                        }
                    }
                }
                await group.waitForAll()
            }
            NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        }
    }

    func test(_ c: Channel) async -> String {
        do {
            try await send(c, title: "涛声 · 测试", body: "这是一条测试消息，收到说明通道配好了。")
            store.markChannelPushed(id: c.id, status: "已送达")
            return "已送达"
        } catch {
            store.markChannelPushed(id: c.id, status: "失败")
            return "失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 发送

    private func send(_ c: Channel, title: String, body: String) async throws {
        switch c.kind {
        case .agent, .webhook:
            _ = try await postJSON(c.url, headers: [:], payload: [
                "title": title,
                "body": body,
                "source": "taosheng",
                "extra": c.extra
            ])

        case .pushplus:
            let token = c.extra.isEmpty ? tokenFromURL(c.url) : c.extra
            guard !token.isEmpty else { throw TranscribeError.http(0, "PushPlus 需要 token") }
            let data = try await postJSON(c.url.isEmpty ? "https://www.pushplus.plus/send" : c.url,
                                          headers: [:],
                                          payload: ["token": token,
                                                    "title": title,
                                                    "content": clampChars(body, 18000),
                                                    "template": "markdown"])
            // PushPlus 用 200 表示成功，HTTP 200 但 code=999 是 token 错
            try checkJSON(data, codeKey: "code", ok: 200, messageKey: "msg")

        case .wecom:
            // 企微 markdown 正文上限 4096 字节，超了整个请求会被拒
            let text = "**\(title)**\n" + clampBytes(body, 3900)
            let data = try await postJSON(c.url, headers: [:], payload: [
                "msgtype": "markdown",
                "markdown": ["content": text]
            ])
            try checkJSON(data, codeKey: "errcode", ok: 0, messageKey: "errmsg")

        case .feishu:
            let data = try await postJSON(c.url, headers: [:], payload: [
                "msg_type": "text",
                "content": ["text": "\(title)\n" + clampChars(body, 3000)]
            ])
            try checkJSON(data, codeKey: "code", ok: 0, messageKey: "msg")

        case .telegram:
            let data = try await postJSON(c.url, headers: [:], payload: [
                "chat_id": c.extra,
                "text": "\(title)\n" + clampChars(body, 3800)
            ])
            // Telegram 的失败是 HTTP 200 + {"ok": false}
            if let o = jsonObject(data), let ok = o["ok"] as? Bool, !ok {
                let msg = (o["description"] as? String) ?? "发送失败"
                throw TranscribeError.http(0, msg)
            }

        case .bark:
            var url = c.url
            if url.hasSuffix("/") { url.removeLast() }
            // .urlPathAllowed 允许 "/"，正文里出现斜杠会把 URL 拆成多段路径，Bark 端直接 404
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%")
            let encTitle = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encBody = String(body.prefix(600)).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let data = try await get("\(url)/\(encTitle)/\(encBody)")
            try checkJSON(data, codeKey: "code", ok: 200, messageKey: "message")

        case .serverchan:
            let data = try await postForm(c.url, fields: ["title": clampChars(title, 32), "desp": clampBytes(body, 30000)])
            try checkJSON(data, codeKey: "code", ok: 0, messageKey: "message")

        case .ntfy:
            // 频道地址怎么拼是纯逻辑，放在 PushRules 里单测；这里只负责发
            guard let target = PushRules.ntfyURL(url: c.url, extra: c.extra) else {
                throw TranscribeError.http(0, "ntfy 需要频道名：https://ntfy.sh/你的频道")
            }
            let head = PushRules.clampChars(title, 120)
            _ = try await postRaw(target.absoluteString,
                                  body: head + "\n" + PushRules.clampBytes(body, 3500),
                                  headers: ["Title": head, "Markdown": "yes"])

        case .nutstore:
            let path = c.extra.isEmpty ? "taosheng/digest.md" : c.extra
            try await putWebDAV(c, path: path, text: "# \(title)\n\n" + clampBytes(body, 200_000))
        }
    }

    private func tokenFromURL(_ url: String) -> String {
        url.split(separator: "/").last.map(String.init) ?? ""
    }

    // MARK: - 响应判定

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 企微/飞书/Server酱/PushPlus 都是 HTTP 200 + 业务错误码，只看状态码会把失败显示成「已送达」
    private func checkJSON(_ data: Data, codeKey: String, ok: Int, messageKey: String) throws {
        guard let obj = jsonObject(data) else { return }   // 有的网关回纯文本，交给状态码判断
        var code = ok
        if let n = obj[codeKey] as? Int {
            code = n
        } else if let s = obj[codeKey] as? String, let n = Int(s) {
            code = n
        }
        guard code == ok else {
            let msg = (obj[messageKey] as? String) ?? "服务端返回 \(codeKey)=\(code)"
            throw TranscribeError.http(code, msg)
        }
    }

    private func clampBytes(_ s: String, _ limit: Int) -> String {
        guard s.utf8.count > limit else { return s }
        var out = ""
        var used = 0
        for ch in s {
            let n = String(ch).utf8.count
            if used + n > limit { break }
            out.append(ch)
            used += n
        }
        return out + "\n…（内容过长已截断）"
    }

    private func clampChars(_ s: String, _ limit: Int) -> String {
        s.count <= limit ? s : String(s.prefix(limit)) + "\n…（内容过长已截断）"
    }

    // MARK: - 坚果云 WebDAV

    private func putWebDAV(_ c: Channel, path: String, text: String) async throws {
        let raw = c.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: raw), base.scheme != nil, let host = base.host, !host.isEmpty else {
            throw TranscribeError.http(0, "坚果云通道要填 WebDAV 地址")
        }
        let user = (c.user ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = c.pass ?? ""
        guard !user.isEmpty else { throw TranscribeError.http(401, "坚果云通道要填账号与密码") }

        let target = base.appendingPathComponent(path)
        var req = URLRequest(url: target)
        req.httpMethod = "PUT"
        req.timeoutInterval = 30
        req.setValue("text/markdown; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(basicAuth(user, pass), forHTTPHeaderField: "Authorization")
        req.httpBody = text.data(using: .utf8)

        do {
            _ = try await fire(req)
        } catch let e as TranscribeError {
            // 目录还没建：先 MKCOL 再补一次
            if case .http(let code, _) = e, code == 409 || code == 404 {
                try? await mkcol(target.deletingLastPathComponent(), user: user, pass: pass)
                _ = try await fire(req)
            } else {
                throw e
            }
        }
    }

    private func mkcol(_ url: URL, user: String, pass: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "MKCOL"
        req.timeoutInterval = 30
        req.setValue(basicAuth(user, pass), forHTTPHeaderField: "Authorization")
        _ = try? await fire(req)   // 已存在会回 405，忽略
    }

    private func basicAuth(_ user: String, _ pass: String) -> String {
        "Basic " + Data("\(user):\(pass)".utf8).base64EncodedString()
    }

    // MARK: - HTTP

    @discardableResult
    private func postJSON(_ urlString: String, headers: [String: String], payload: [String: Any]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对：\(urlString)") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await fire(req)
    }

    @discardableResult
    private func postForm(_ urlString: String, fields: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        var parts: [String] = []
        for (k, v) in fields {
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            parts.append("\(ek)=\(ev)")
        }
        req.httpBody = parts.joined(separator: "&").data(using: .utf8)
        return try await fire(req)
    }

    @discardableResult
    private func postRaw(_ urlString: String, body: String, headers: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 30
        req.httpBody = body.data(using: .utf8)
        return try await fire(req)
    }

    @discardableResult
    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        return try await fire(req)
    }

    @discardableResult
    private func fire(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TranscribeError.http(0, "无响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscribeError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

}
