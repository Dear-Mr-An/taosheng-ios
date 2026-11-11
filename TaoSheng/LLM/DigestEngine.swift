import Foundation
import Combine

/// 整理引擎：把一天的原话整理成事件 + 提取项（对齐原版 digest.md 流程），
/// 顺带跑一次寻物（things.md），最后按设置推送。
final class DigestEngine: ObservableObject {

    static let shared = DigestEngine()

    @Published private(set) var running = false
    @Published private(set) var lastRunAt: Date?
    @Published var lastError: String?

    private var timer: Timer?
    private var lastAttempt: [String: Date] = [:]

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 触发

    private func tick() {
        let s = Settings.shared
        guard !s.effectiveLLM.key.isEmpty else { return }
        guard !running else { return }

        let day = DayKey.of(Date())
        // 距上次整理不足间隔就跳过
        if let last = lastAttempt[day], Date().timeIntervalSince(last) < Double(max(s.digestIntervalMin, 1)) * 60 {
            return
        }
        let rows = Store.shared.undigestedSegments(day: day, limit: 200)
        guard !rows.isEmpty else { return }

        lastAttempt[day] = Date()
        Task { try? await self.digest(day: day) }
    }

    // MARK: - 主流程

    @discardableResult
    func digest(day: String, full: Bool = false) async throws -> (events: Int, items: Int) {
        if running { return (0, 0) }
        await MainActor.run { self.running = true; self.lastError = nil }
        defer { Task { await MainActor.run { self.running = false } } }

        let s = Settings.shared
        guard !s.effectiveLLM.key.isEmpty else {
            throw LLMError.notConfigured
        }

        let rows = full
            ? Store.shared.transcriptRows(day: day, limit: 800)
            : Store.shared.undigestedSegments(day: day, limit: 200)
        guard !rows.isEmpty else { return (0, 0) }

        // 1. 组原话
        let lines = Self.buildLines(rows)
        let unfinished = Store.shared.openItemContents(days: 60)
        let ignored = Store.shared.ignoredItemContents(days: 60)

        // 2. 调模型
        let user = Prompts.digestUser(day: day, lines: lines, unfinished: unfinished, ignored: ignored)
        let reply = try await LLMClient.completeAny(system: Prompts.digestSystem, user: user, temperature: 0.2)

        // 3. 解析
        guard let data = JSONExtract.object(from: reply) else {
            await fail("整理结果看不懂：\(reply.prefix(120))")
            return (0, 0)
        }
        let out: DigestOut
        do {
            out = try JSONDecoder().decode(DigestOut.self, from: JSONSerialization.data(withJSONObject: data))
        } catch {
            await fail("整理结果结构不对：\(error.localizedDescription)")
            return (0, 0)
        }

        // 4. 落事件
        let segById = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.offset + 1, $0.element) })
        var eventCount = 0
        for (idx, e) in out.events.enumerated() {
            let first = segById[e.from] ?? rows.first
            let last = segById[e.to] ?? first
            guard let f = first else { continue }
            let start = f.startedAt
            let end = last?.endedAt ?? f.endedAt
            let ev = MemoryEvent(
                id: UUID().uuidString,
                day: day,
                startAt: start,
                endAt: end,
                scene: e.scene ?? "其他",
                title: e.title ?? "（未命名）",
                summary: e.summary ?? "",
                points: e.points ?? [],
                people: e.people ?? [],
                place: e.place,
                emotion: e.emotion ?? "平静",
                intensity: e.intensity ?? 3,
                important: e.important ?? false,
                starred: false,
                starredAt: nil,
                entityId: "\(day)-\(idx)",
                lineFrom: e.from,
                lineTo: e.to,
                createdAt: Date()
            )
            Store.shared.upsertEvent(ev)
            eventCount += 1
        }

        // 5. 落提取项（同一句话重复提取要跳过）
        var itemCount = 0
        let existing = Set(Store.shared.items(day: day, status: nil, category: nil, limit: 500).map { $0.content })
        var newItems: [MemoryItem] = []
        for it in out.items {
            let content = (it.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, !existing.contains(content) else { continue }
            let cat = it.category ?? "备忘"
            let due = it.due
            newItems.append(MemoryItem(
                id: UUID().uuidString,
                eventId: nil,
                day: day,
                category: cat,
                kind: it.kind,
                content: content,
                status: cat == "待办" || cat == "约定" ? .pending : .accepted,
                dueText: due,
                dueAt: Self.parseDue(due),
                who: it.who,
                sourceText: segById[it.line ?? -1]?.transcript,
                createdAt: Date(),
                updatedAt: Date()
            ))
            itemCount += 1
        }
        Store.shared.insertItems(newItems)

        // 6. 完成提示（done_hints）
        for h in out.done_hints ?? [] {
            Store.shared.setItemStatus(id: h.item_id, status: MemItemStatus.done)
        }

        // 7. 寻物（失败不影响整理）
        await runThings(day: day, rows: rows)

        // 7.5 技能卡：说完自动识别型（会议速记等）
        SkillEngine.shared.runAfterDigest(day: day)

        // 8. 标记已整理
        Store.shared.markDigested(rows.map { $0.id })

        // 9. 推送 + 通知
        let summary = out.events.first?.summary ?? ""
        PushEngine.shared.pushDigest(day: day, summary: summary, items: newItems, transcript: lines.joined(separator: "\n"))
        await MainActor.run {
            self.lastRunAt = Date()
            NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        }
        return (eventCount, itemCount)
    }

    // MARK: - 寻物

    private func runThings(day: String, rows: [Segment]) async {
        let known = Store.shared.things()
        guard !known.isEmpty || rows.count > 0 else { return }
        let payload: [String: Any] = [
            "mode": "live",
            "lines": rows.enumerated().map { i, r in
                ["id": i + 1, "at": Self.hms(r.startedAt), "segmentId": r.id, "text": r.transcript]
            },
            "context": [],
            "known": known.map { ["id": $0.id, "name": $0.name, "aliases": $0.aliases] }
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: body, encoding: .utf8) else { return }
        let user = "# 日历\n\(Prompts.calendarTable())\n\n# 输入\n\(text)"
        guard let reply = try? await LLMClient.completeAny(system: Prompts.thingsSystem, user: user, temperature: 0),
              let obj = JSONExtract.object(from: reply),
              let list = obj["items"] as? [[String: Any]] else { return }

        for raw in list {
            guard let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            let action = raw["action"] as? String ?? "Placed"
            let place = raw["place"] as? String
            let who = raw["who"] as? String
            let confident = raw["confident"] as? Bool ?? true
            let knownId = raw["knownId"] as? String
            let lineId = raw["lineId"] as? Int
            let aliases = raw["aliases"] as? [String] ?? []

            var thing = knownId.flatMap { id in known.first { $0.id == id } } ?? Store.shared.thing(named: name)
            if thing == nil {
                let t = Thing(id: UUID().uuidString, name: name, aliases: aliases,
                              owner: raw["owner"] as? String ?? "Mine",
                              place: place, holder: who, updatedAt: Date())
                Store.shared.upsertThing(t)
                thing = t
            }
            guard let t = thing else { continue }
            if action == "Placed", let p = place {
                Store.shared.upsertThing(Thing(id: t.id, name: t.name, aliases: t.aliases, owner: t.owner, place: p, holder: nil, updatedAt: Date()))
            }
            if action == "Lent", let w = who {
                Store.shared.upsertThing(Thing(id: t.id, name: t.name, aliases: t.aliases, owner: t.owner, place: t.place, holder: w, updatedAt: Date()))
            }
            let segId = lineId.flatMap { id in rows[safe: id - 1]?.id }
            Store.shared.insertFact(ThingFact(
                id: UUID().uuidString,
                thingId: t.id,
                action: action,
                place: place,
                who: who,
                lineId: segId,
                confident: confident,
                at: Date()
            ))
        }
    }

    // MARK: - 工具

    static func buildLines(_ rows: [Segment]) -> [String] {
        var out: [String] = []
        var lastDay: String?
        for (i, r) in rows.enumerated() {
            if let ld = lastDay, ld != r.day {
                out.append("—— 新录音 ——")
            }
            lastDay = r.day
            let who = r.speaker.isEmpty ? "说话人1" : r.speaker
            out.append("[\(i + 1)] \(hms(r.startedAt)) \(who)：\(r.transcript)")
        }
        return out
    }

    static func hms(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    static func parseDue(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private func fail(_ msg: String) async {
        await MainActor.run {
            self.lastError = msg
            self.running = false
        }
    }

    // MARK: - 解析结构

    struct DigestOut: Codable {
        var events: [EventOut]
        var items: [ItemOut]
        var done_hints: [DoneHint]?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            events = (try? c.decode([EventOut].self, forKey: .events)) ?? []
            items = (try? c.decode([ItemOut].self, forKey: .items)) ?? []
            done_hints = try? c.decode([DoneHint].self, forKey: .done_hints)
        }
    }

    struct EventOut: Codable {
        var from: Int
        var to: Int
        var scene: String?
        var title: String?
        var summary: String?
        var points: [String]?
        var people: [String]?
        var place: String?
        var emotion: String?
        var intensity: Int?
        var important: Bool?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            from = (try? c.decode(Int.self, forKey: .from)) ?? 1
            to = (try? c.decode(Int.self, forKey: .to)) ?? from
            scene = try? c.decode(String.self, forKey: .scene)
            title = try? c.decode(String.self, forKey: .title)
            summary = try? c.decode(String.self, forKey: .summary)
            points = try? c.decode([String].self, forKey: .points)
            people = try? c.decode([String].self, forKey: .people)
            place = try? c.decode(String.self, forKey: .place)
            emotion = try? c.decode(String.self, forKey: .emotion)
            intensity = try? c.decode(Int.self, forKey: .intensity)
            important = try? c.decode(Bool.self, forKey: .important)
        }
    }

    struct ItemOut: Codable {
        var category: String?
        var kind: String?
        var content: String?
        var due: String?
        var who: String?
        var line: Int?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            category = try? c.decode(String.self, forKey: .category)
            kind = try? c.decode(String.self, forKey: .kind)
            content = try? c.decode(String.self, forKey: .content)
            due = try? c.decode(String.self, forKey: .due)
            who = try? c.decode(String.self, forKey: .who)
            line = try? c.decode(Int.self, forKey: .line)
        }
    }

    struct DoneHint: Codable {
        var item_id: String
        var line_id: Int?
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
