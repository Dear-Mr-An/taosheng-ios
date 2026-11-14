import Foundation

/// 一场会/一场培训结束后的「立即整理」。
///
/// 和按天整理的区别：这里只喂这一场的原话，只产出 1 个事件（会议速记 / 培训笔记），整理完立刻推送。
/// 董事长开完会就要看到纪要，等 30 分钟的定时器没有意义。
///
/// 结构不让模型自由发挥：会议固定「议题 / 结论先行 / 要点 / 决定 / 待办」，培训固定
/// 「主题 / 核心要点 / 知识点 / 行动」，由 `NoteRules` 按模式写死，模型只负责把每条
/// 加上对应前缀（`points` 里带「议题：」这种前缀，展示时再分拣）。
enum SessionDigest {
    struct Output {
        var eventId: String
        var title: String
        var summary: String
        var points: [String]
        var quotes: [EventQuote]
        var items: [MemoryItem]
    }

    private struct Reply: Decodable {
        struct Todo: Decodable {
            var content: String?
            var owner: String?
            var due: String?
        }
        struct Quote: Decodable {
            var speaker: String?
            var time: String?
            var text: String?
        }
        var title: String?
        var summary: String?
        var points: [String]?
        var todos: [Todo]?
        var quotes: [Quote]?
    }

    // MARK: - 提示词

    static let meetingSystem = """
    你是会议速记助手。用户给你一场会议的原话（每行带说话人名字和相对时间）。
    只输出一个 JSON 对象，不要任何解释文字、不要 markdown 围栏：
    {"title":"不超过 14 字的会议标题","summary":"2-4 句；第一句就是这个会的结论","points":["带前缀的条目"],"todos":[{"content":"要做的事","owner":"负责人的说话人名字","due":"YYYY-MM-DD HH:mm 或 明天 或空"}],"quotes":[{"speaker":"说话人名字","time":"14:52","text":"原话照抄"}]}
    要求：
    1. points 每条都必须以下面四个前缀之一开头：「议题：」「结论先行：」「要点：」「决定：」。
       议题写这次要谈什么，结论先行写最后定了什么，要点写讨论过程里的关键信息，决定写明确拍板的事。
    2. summary 第一句直接给结论，不要「本次会议讨论了」这种开场白。
    3. quotes 给 3-5 条最关键的原话，text 必须原文照抄（不要改写、不要加标点），speaker 用原话里的名字，time 用原话前面的时间。
    4. todos 的 owner 必须是原话里出现过的说话人名字，不要写「大家」「某人」；没有就 []。
    5. 只依据原话，不要编造没说过的事；原话少就少写。
    """

    static let trainingSystem = """
    你是培训笔记助手。用户给你一场培训/讲课的原话（每一行带说话人和相对时间）。
    只输出一个 JSON 对象，不要任何解释文字、不要 markdown 围栏：
    {"title":"不超过 14 字的笔记标题","summary":"2-4 句；第一句就是这次培训在讲什么","points":["带前缀的条目"],"todos":[{"content":"听完要做的事","owner":"我","due":"空"}],"quotes":[{"speaker":"讲课人名字","time":"12:30","text":"原话照抄"}]}
    要求：
    1. points 每条都必须以下面四个前缀之一开头：「主题：」「核心要点：」「知识点：」「行动：」。
       主题写这次讲什么，核心要点写最重要的两三句，知识点写具体方法/概念/步骤，行动写听完要去做的。
    2. summary 第一句直接说这次培训讲的是什么，不要客套。
    3. quotes 给 3-5 条讲课人的关键原话，text 原文照抄。
    4. todos 是「我要做的行动」，owner 写「我」；没有就 []。
    5. 只依据原话，不要编造。
    """

    static func system(for mode: CaptureMode) -> String {
        mode == .training ? trainingSystem : meetingSystem
    }

    // MARK: - 主流程

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
        模式：\(session.mode.title)
        开始：\(Fmt.monthDayTime.string(from: session.startedAt))
        时长：\(session.durationText)
        说话人：\(speakerList.joined(separator: "、"))
        原话：
        """
        // 太长的会按尾部截断：开头的寒暄不重要，最后半小时的结论才重要
        var body = lines.joined(separator: "\n")
        if body.count > 24000 {
            body = "（前面略）\n" + String(body.suffix(24000))
        }
        let user = head + "\n" + body

        let reply = try await LLMClient.completeAny(system: system(for: session.mode), user: user,
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

        // 结构由代码按模式兜底：模型漏了前缀就按顺序补，保证详情页四段都成形
        var points = (out.points ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let marks = session.mode == .training
            ? ["主题：", "核心要点：", "知识点：", "行动："]
            : ["议题：", "结论先行：", "要点：", "决定："]
        let missing = points.contains { line in !marks.contains { line.hasPrefix($0) } }
        if missing {
            points = points.map { line in
                marks.contains { line.hasPrefix($0) } ? line : "要点：" + line
            }
        }
        if session.mode != .training, !summary.isEmpty, !points.contains(where: { $0.hasPrefix("结论先行：") }) {
            points.insert("结论先行：" + NoteRules.conclusion(summary), at: 0)
        }

        let quotes: [EventQuote] = (out.quotes ?? []).compactMap { q in
            let text = (q.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 6 else { return nil }
            let who = (q.speaker ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let time = (q.time ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return EventQuote(speaker: who.isEmpty ? (speakerList.first ?? "说话人1") : who,
                              time: time, text: text)
        }

        // 每场固定 1 个事件；entityId 稳定，重试时更新同一张卡而不是又生成一张。
        let event = MemoryEvent(
            id: UUID().uuidString,
            day: session.day,
            startAt: session.startedAt,
            endAt: session.endedAt ?? Date(),
            scene: session.scene,
            title: title.isEmpty ? session.mode.noteTitle : title,
            summary: summary,
            points: Array(points.prefix(12)),
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
            createdAt: Date(),
            sessionId: session.id,
            quotes: Array(quotes.prefix(5))
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
        return Output(eventId: event.entityId ?? event.id, title: event.title, summary: event.summary,
                      points: event.points, quotes: event.quotes, items: items)
    }
}
