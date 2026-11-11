import Foundation

/// 整理技能：按原版 skill.json 的 fields 结构，让模型直接产出「卡片字段」
final class SkillEngine: ObservableObject {
    static let shared = SkillEngine()

    @Published private(set) var lastError: String?
    @Published private(set) var running = false

    private let store = Store.shared
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.runIfDue()
        }
        runIfDue()
    }

    func runIfDue() {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now)
        let today = DayKey.of(now)
        let list = store.skills().filter { $0.enabled }
        for s in list {
            switch s.schedule {
            case .manual, .afterDigest:
                continue
            case .daily:
                guard hour > s.hour || (hour == s.hour && minute >= s.minute) else { continue }
                if !hasRun(s.id, day: today) { fire(s, day: today) }
            case .weekly:
                guard weekday == s.weekday else { continue }
                guard hour > s.hour || (hour == s.hour && minute >= s.minute) else { continue }
                if !hasRun(s.id, day: today) { fire(s, day: today) }
            }
        }
    }

    /// 每轮整理之后调用：看看新内容值不值得出卡（afterDigest 类型）
    func runAfterDigest(day: String) {
        for s in store.skills() where s.enabled && s.schedule == .afterDigest {
            if hasRun(s.id, day: day) { continue }
            fire(s, day: day)
        }
    }

    private func hasRun(_ skillId: String, day: String) -> Bool {
        !store.cards(day: day, skillId: skillId, limit: 1).isEmpty
    }

    private func fire(_ skill: SkillDef, day: String) {
        Task {
            do {
                _ = try await self.run(skill, day: day)
                await MainActor.run { self.lastError = nil }
            } catch {
                let msg = "「\(skill.name)」没跑成：\(error.localizedDescription)"
                await MainActor.run { self.lastError = msg }
                NSLog("涛声: \(msg)")
            }
        }
    }

    // MARK: - 运行

    func run(_ skill: SkillDef, day: String) async throws -> SkillCard {
        await MainActor.run { self.running = true }
        defer { Task { await MainActor.run { self.running = false } } }

        let lines = store.transcriptRows(day: day, limit: 1200)
        guard !lines.isEmpty else { throw TranscribeError.empty }

        var context = ""
        for (i, r) in lines.enumerated() {
            let who = r.speaker.isEmpty ? "" : "\(r.speaker)："
            context += "[\(i + 1)] \(r.time) \(who)\(r.text)\n"
        }
        if context.count > 14000 { context = String(context.prefix(14000)) }

        let fields = skill.fields.isEmpty ? [SkillField.text, SkillField.bullets] : skill.fields
        let spec = fields.map { "- \($0.key)（\($0.label) · \($0.typeText)\($0.required ? " · 必有" : "")" }
            .joined(separator: "\n")

        let system = """
        你是用户的私人记录助手，现在执行技能「\(skill.name)」。
        这个技能要做的事：\(skill.desc.isEmpty ? skill.name : skill.desc)

        \(skill.prompt)

        卡片上要有这些字段：
        \(spec)

        输出要求：
        1. 只输出 JSON，不要 Markdown 包裹，不要解释。
        2. 格式：{"fields":{"字段key":"内容"},"quotes":["原话摘录"],"nothing":false}
        3. 字段值按类型写：一句话=短句；一段话=完整段落；要点=用「· 」开头的多行文本；清单=用「□ 」开头；标签=逗号分隔；原话=照抄原句。
        4. quotes 最多 3 条，必须是输入里真实出现过的原话，不要改写。
        5. 如果今天的记录里没有这个技能该处理的内容，输出 {"fields":{},"quotes":[],"nothing":true,"nothing_reason":"一句话说明为什么没有"}。
        6. 只用输入里出现的信息，不要编造人名、时间、数字。
        """

        let reply = try await LLMClient.completeAny(system: system, user: "\(day) 的记录：\n\(context)", temperature: 0.3)
        let obj = JSONExtract.object(from: reply) ?? [:]
        let isNothing = (obj["nothing"] as? Bool) ?? (obj["nothing"] as? String == "true")
        var map: [String: String] = [:]
        if let raw = obj["fields"] as? [String: Any] {
            for f in fields {
                if let v = raw[f.key] as? String, !v.trimmed.isEmpty {
                    map[f.key] = v.trimmed
                }
            }
        }
        let quotes = (obj["quotes"] as? [String]) ?? []
        let reason = (obj["nothing_reason"] as? String) ?? ""

        if map.isEmpty && !isNothing {
            map[fields.first?.key ?? "text"] = reply.trimmed
        }

        let card = SkillCard(
            id: shortID(),
            skillId: skill.id,
            skillName: skill.name,
            day: day,
            startAt: nil,
            endAt: nil,
            entityId: "\(day)-\(skill.id)",
            fields: map,
            quotes: quotes,
            nothingReason: isNothing ? (reason.isEmpty ? "今天没有相关内容" : reason) : nil,
            createdAt: Date()
        )
        store.insertCard(card)

        // 兼容旧的「最近产出」列表
        let head = map[fields.first?.key ?? "text"] ?? skill.name
        store.insertSkillRun(SkillRun(
            id: card.id,
            skillId: skill.id,
            skillName: skill.name,
            day: day,
            title: String(head.prefix(40)),
            output: map.map { "\($0.key)：\($0.value)" }.sorted().joined(separator: "\n"),
            createdAt: Date()
        ))

        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        if !isNothing { PushEngine.shared.pushCard(card) }
        return card
    }

    /// 「+ 智能生成」：让模型读今天原话，建议一个新技能（含字段）
    func suggestSkill(day: String) async throws -> SkillDef {
        let lines = store.transcriptRows(day: day, limit: 200)
        var context = ""
        for r in lines {
            let who = r.speaker.isEmpty ? "" : "\(r.speaker)："
            context += "\(r.time) \(who)\(r.text)\n"
        }
        let system = """
        看用户的日常原话，提出一个对他有用的整理技能。
        只输出 JSON：
        {"name":"不超过6字","desc":"一句话说明这个技能做什么","symbol":"SF Symbols 名",
         "prompt":"给模型的执行指令，说清什么情况该出卡、关注哪些信息",
         "fields":[{"key":"英文小写key","label":"卡片上显示的名字","type":"text|paragraph|bullets|checklist|tags|quotes","required":true}]}
        字段 2~4 个，至少一个 required。
        """
        let reply = try await LLMClient.completeAny(system: system, user: context.isEmpty ? "（今天没有原话）" : context, temperature: 0.7)
        let obj = JSONExtract.object(from: reply) ?? [:]
        var fields: [SkillField] = []
        if let arr = obj["fields"] as? [[String: Any]] {
            for f in arr {
                guard let k = f["key"] as? String, !k.isEmpty else { continue }
                fields.append(SkillField(
                    key: k,
                    label: (f["label"] as? String) ?? k,
                    type: (f["type"] as? String) ?? "paragraph",
                    required: (f["required"] as? Bool) ?? false
                ))
            }
        }
        if fields.isEmpty { fields = [SkillField.paragraph, SkillField.bullets] }
        return SkillDef(
            id: shortID(),
            name: (obj["name"] as? String) ?? "自定义技能",
            symbol: (obj["symbol"] as? String) ?? "sparkles",
            desc: (obj["desc"] as? String) ?? "",
            enabled: false,
            schedule: .manual,
            hour: 21,
            minute: 0,
            weekday: 1,
            prompt: (obj["prompt"] as? String) ?? "总结今天的重点。",
            builtin: false,
            createdAt: Date(),
            fields: fields
        )
    }
}
