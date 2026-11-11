import Foundation

/// 整理技能：内置四种 + 自定义（JSON 提示词）
final class SkillEngine {
    static let shared = SkillEngine()

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
        let hour = cal.component(.hour, from: Date())
        let minute = cal.component(.minute, from: Date())
        let weekday = cal.component(.weekday, from: Date())
        let today = DayKey.of(Date())
        let list = store.skills().filter { $0.enabled }
        // 「已过点且当天没跑过」就算到期——App 在后台时 Timer 不跑，回前台补跑
        let passedTarget = (hour > 0 || minute > 0) && (hour > 0)
        for s in list {
            switch s.schedule {
            case .manual, .afterDigest:
                continue
            case .daily:
                guard passedTarget else { continue }
                guard hour > s.hour || (hour == s.hour && minute >= s.minute) else { continue }
                let done = store.skillRuns(day: today, limit: 80).contains { $0.skillId == s.id }
                if !done {
                    Task { _ = try? await self.run(s, day: today) }
                }
            case .weekly:
                guard passedTarget, weekday == s.weekday else { continue }
                guard hour > s.hour || (hour == s.hour && minute >= s.minute) else { continue }
                let done = store.skillRuns(day: today, limit: 80).contains { $0.skillId == s.id }
                if !done {
                    Task { _ = try? await self.run(s, day: today) }
                }
            }
        }
    }

    func run(_ skill: SkillDef, day: String) async throws -> SkillRun {
        let lines = store.transcriptLines(day: day)
        guard !lines.isEmpty else { throw TranscribeError.empty }
        var context = ""
        for l in lines {
            let who = l.speaker.isEmpty ? "" : "\(l.speaker)："
            context += "\(l.time) \(who)\(l.text)\n"
        }
        if context.count > 12000 { context = String(context.prefix(12000)) }

        let system = """
        你是用户的私人记录助手，现在执行技能「\(skill.name)」。
        \(skill.prompt)
        输出要求：直接给 Markdown 正文，不要开场白，不要解释你在做什么，不要输出 JSON 包裹。
        只用原话里出现的信息，缺信息就说「今天没有相关内容」。
        """

        let reply = try await LLMClient.completeAny(system: system, user: "\(day) 的原话：\n\(context)", temperature: 0.4)
        let firstLine = reply.split(separator: "\n").first.map(String.init) ?? skill.name

        let run = SkillRun(
            id: shortID(),
            skillId: skill.id,
            skillName: skill.name,
            day: day,
            title: String(firstLine.prefix(40)),
            output: reply.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        store.insertSkillRun(run)
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        return run
    }

    /// 「+ 智能生成」：让模型读今天原话，建议一个新技能
    func suggestSkill(day: String) async throws -> SkillDef {
        let lines = store.transcriptLines(day: day)
        var context = ""
        for l in lines.prefix(80) {
            let who = l.speaker.isEmpty ? "" : "\(l.speaker)："
            context += "\(l.time) \(who)\(l.text)\n"
        }
        let system = """
        看用户的日常原话，提出一个对他有用的整理技能。
        只输出 JSON：{"name":"不超过6字","desc":"一句话说明","prompt":"给模型的指令，具体到输出结构","symbol":"SF Symbols 名"}
        """
        let reply = try await LLMClient.completeAny(system: system, user: context.isEmpty ? "（今天没有原话）" : context, temperature: 0.7)
        let obj = JSONExtract.object(from: reply) ?? [:]
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
            createdAt: Date()
        )
    }
}
