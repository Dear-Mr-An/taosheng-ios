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
            try await postJSON(c.url, headers: [:], payload: [
                "title": title,
                "body": body,
                "source": "taosheng",
                "extra": c.extra
            ])
        case .pushplus:
            let token = c.extra.isEmpty ? tokenFromURL(c.url) : c.extra
            try await postJSON(c.url.isEmpty ? "https://www.pushplus.plus/send" : c.url, headers: [:], payload: [
                "token": token,
                "title": title,
                "content": body,
                "template": "markdown"
            ])
        case .wecom:
            try await postJSON(c.url, headers: [:], payload: [
                "msgtype": "markdown",
                "markdown": ["content": "**\(title)**\n\(body)"]
            ])
        case .feishu:
            try await postJSON(c.url, headers: [:], payload: [
                "msg_type": "text",
                "content": ["text": "\(title)\n\(body)"]
            ])
        case .telegram:
            try await postJSON(c.url, headers: [:], payload: [
                "chat_id": c.extra,
                "text": "\(title)\n\(body)"
            ])
        case .bark:
            var url = c.url
            if url.hasSuffix("/") { url.removeLast() }
            // .urlPathAllowed 允许 "/"，正文里出现斜杠会把 URL 拆成多段路径，Bark 端直接 404
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%")
            let encTitle = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encBody = String(body.prefix(600)).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            try await get("\(url)/\(encTitle)/\(encBody)")
        case .serverchan:
            try await postForm(c.url, fields: ["title": title, "desp": body])
        case .ntfy:
            let topic = c.extra.isEmpty ? tokenFromURL(c.url) : c.extra
            let base = c.url.isEmpty ? "https://ntfy.sh" : c.url
            try await postRaw("\(base)/\(topic)", body: "\(title)\n\(body)", headers: ["Title": title, "Markdown": "yes"])
        case .nutstore:
            let path = c.extra.isEmpty ? "taosheng/digest.md" : c.extra
            try await BackupEngine.shared.putText(path: path, text: "# \(title)\n\n\(body)")
        }
    }

    private func tokenFromURL(_ url: String) -> String {
        url.split(separator: "/").last.map(String.init) ?? ""
    }

    // MARK: - HTTP

    private func postJSON(_ urlString: String, headers: [String: String], payload: [String: Any]) async throws {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对：\(urlString)") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        try await fire(req)
    }

    private func postForm(_ urlString: String, fields: [String: String]) async throws {
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
        try await fire(req)
    }

    private func postRaw(_ urlString: String, body: String, headers: [String: String]) async throws {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 30
        req.httpBody = body.data(using: .utf8)
        try await fire(req)
    }

    private func get(_ urlString: String) async throws {
        guard let url = URL(string: urlString) else { throw TranscribeError.http(0, "地址不对") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        try await fire(req)
    }

    private func fire(_ req: URLRequest) async throws {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TranscribeError.http(0, "无响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscribeError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
