import Foundation

/// 一场会结束后的「立即整理」。
///
/// 和按天整理的区别：这里只喂这一场的原话，只产出 1 个事件，整理完立刻推送。
/// 董事长开完会就要看到纪要，等 30 分钟的定时器没有意义。
enum SessionDigest {
    struct Output {
        var eventId: String
        var title: String
        var summary: String
        var points: [String]
        var items: [MemoryItem]
    }

    private struct Reply: Decodable {
        struct Todo: Decodable {
            var content: String?
            var owner: String?
            var due: String?
        }
        var title: String?
        var summary: String?
        var points: [String]?
        var decisions: [String]?
        var todos: [Todo]?
    }

    static let system = """
    你是会议纪要助手。用户给你一场会议的原话（每行带说话人和时间）。
    只输出一个 JSON 对象，不要任何解释文字、不要 markdown 围栏：
    {"title":"不超过 14 字的会议标题","summary":"2-4 句会议摘要","points":["讨论到的要点"],"decisions":["明确决定的事"],"todos":[{"content":"要做的事","owner":"负责人的说话人名字","due":"YYYY-MM-DD HH:mm 或 明天 或空"}]}
    要求：
    1. 只依据原话，不要编造没说过的事；没有决定就 decisions 给 []。
    2. todos 的 owner 必须是原话里出现过的说话人名字，不要写「大家」「某人」。
    3. 待办一条一句话，动词开头。
    4. 原话很少就少写，不要为了凑满字段硬编。
    """

    static func run(session: ListenSession, utterances: [Utterance]) async throws -> Output {
        guard !utterances.isEmpty else { throw LLMError.badReply("这场没有识别出内容") }
        guard !Settings.shared.effectiveLLM.key.isEmpty else {
            throw LLMError.badReply("还没填大模型密钥。去「设置 → 大模型与整理」填好，再点重试。")
        }

        var lines: [String] = []
        for (i, u) in utterances.enumerated() {
            let name = session.name(u.speaker)
            lines.append("[\(i + 1)] \(u.timeText) \(name)：\(u.text)")
        }
        let speakerList = Set(utterances.map { session.name($0.speaker) }).sorted()
        let head = """
        会议模式：\(session.mode.title)
        开始：\(Fmt.monthDayTime.string(from: session.startedAt))
        时长：\(session.durationText)
        说话人：\(speakerList.joined(separator: "、"))
        原话：
        """
        let user = head + "\n" + lines.joined(separator: "\n")

        let reply = try await LLMClient.completeAny(system: system, user: user,
                                                   temperature: 0.2, thinking: Settings.shared.deepThinking)
        guard let obj = JSONExtract.object(from: reply) else {
            throw LLMError.badReply("整理结果不是 JSON，原话已保留，可点重试")
        }
        let out: Reply
        do {
            out = try JSONDecoder().decode(Reply.self, from: JSONSerialization.data(withJSONObject: obj))
        } catch {
            throw LLMError.badReply("整理结果结构不对，原话已保留，可点重试")
        }

        let title = (out.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (out.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !summary.isEmpty else {
            throw LLMError.badReply("整理没返回标题和摘要，原话已保留，可点重试")
        }

        var points = (out.points ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for d in (out.decisions ?? []) {
            let t = d.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { points.append("决定：\(t)") }
        }

        // 每场会议固定 1 个事件；entityId 稳定，重试时更新同一张卡而不是又生成一张。
        let event = MemoryEvent(
            id: UUID().uuidString,
            day: session.day,
            startAt: session.startedAt,
            endAt: session.endedAt ?? Date(),
            scene: session.scene,
            title: title.isEmpty ? "\(session.mode.title)记录" : title,
            summary: summary,
            points: Array(points.prefix(8)),
            people: speakerList,
            place: nil,
            emotion: "平静",
            intensity: 3,
            important: session.mode == .meeting,
            starred: false,
            starredAt: nil,
            entityId: "session-\(session.id)",
            lineFrom: 1,
            lineTo: utterances.count,
            createdAt: Date()
        )
        Store.shared.upsertEvent(event)

        // 待办：负责人写说话人的名字（董事长要求「待办负责人写说话人名」）
        var items: [MemoryItem] = []
        let existing = Set(Store.shared.items(day: session.day, status: nil, category: nil, limit: 500).map { $0.content })
        var seen = existing
        for t in out.todos ?? [] {
            let content = (t.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, seen.insert(content).inserted else { continue }
            let owner = (t.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let due = (t.due ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(MemoryItem(
                id: UUID().uuidString,
                eventId: event.entityId,
                day: session.day,
                category: "待办",
                kind: owner.isEmpty || owner == "我" ? "我要做" : "别人答应我",
                content: content,
                status: .pending,
                dueText: due.isEmpty ? nil : due,
                dueAt: DigestEngine.parseDue(due),
                who: owner.isEmpty ? nil : owner,
                sourceText: nil,
                createdAt: Date(),
                updatedAt: Date()
            ))
        }
        if !items.isEmpty {
            Store.shared.insertItems(items)
            for it in items {
                guard let due = it.dueAt, let fire = ReminderTime.resolve(due: due) else { continue }
                ReminderEngine.shared.scheduleQuick(id: it.id, title: it.content, at: fire)
            }
        }

        // 这一场的段都算整理过了，别再被按天整理重复处理
        let ids = Store.shared.sessionSegments(sessionId: session.id).map { $0.id }
        if !ids.isEmpty { Store.shared.markDigested(ids) }

        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        return Output(eventId: event.entityId ?? event.id, title: event.title, summary: event.summary, points: event.points, items: items)
    }
}
