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
        guard !s.effectiveLLM.key.isEmpty, !running else { return }

        let now = Date()
        let day = DayKey.of(now)
        let lastSuccess = UserDefaults.standard.object(forKey: "digestLastAutomaticSuccess") as? Date
        guard DigestSchedule.shouldRun(enabled: s.autoDigest, byInterval: s.digestByInterval,
            intervalMinutes: s.digestIntervalMin, hour: s.digestHour, now: now, lastRun: lastSuccess) else { return }
        // 失败后至少等五分钟，时间点模式失败不应阻止当天重试。
        if let last = lastAttempt[day], now.timeIntervalSince(last) < 300 { return }
        let days = Store.shared.undigestedDays(through: day)
        guard !days.isEmpty else { return }

        lastAttempt[day] = now
        Task { await self.digestAutomatically(days: days) }
    }

    // MARK: - 主流程

    /// 按这批录音保存的模式追加规则，不能读取当前全局模式。
    private func systemPrompt(for mode: CaptureMode) -> String {
        switch mode {
        case .meeting: return Prompts.digestSystem + Prompts.meetingModeExtra
        case .training: return Prompts.digestSystem + Prompts.trainingModeExtra
        case .call: return Prompts.digestSystem + Prompts.callModeExtra
        case .daily: return Prompts.digestSystem
        }
    }

    @MainActor
    @discardableResult
    func digest(day: String, full: Bool = false) async throws -> (events: Int, items: Int) {
        guard !running else { return (0, 0) }
        running = true
        lastError = nil
        defer { running = false }
        do {
            return try await performDigest(day: day, full: full)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    @MainActor
    private func digestAutomatically(days: [String]) async {
        guard !running else { return }
        running = true
        lastError = nil
        defer { running = false }
        do {
            var failed: String?
            for day in days {
                try Task.checkCancellation()
                do {
                    _ = try await performDigest(day: day, full: false)
                } catch {
                    // 一天失败不能拖垮整批：记下来继续下一天，
                    // 否则积压里永远卡在最前面那天，后面的新录音永远轮不到。
                    failed = "\(day)：\(error.localizedDescription)"
                }
            }
            if let f = failed { lastError = f } else {
                UserDefaults.standard.set(Date(), forKey: "digestLastAutomaticSuccess")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func performDigest(day: String, full: Bool) async throws -> (events: Int, items: Int) {
        let s = Settings.shared
        guard !s.effectiveLLM.key.isEmpty else {
            throw LLMError.notConfigured
        }

        let rows = full
            ? Store.shared.transcriptRows(day: day, limit: -1)
            : Store.shared.undigestedSegments(day: day, limit: -1)
        guard !rows.isEmpty else { return (0, 0) }

        // 按时间上连续的模式分批，避免上午和晚上的同模式跨越会议被合并。
        var batches: [[Segment]] = []
        for row in rows {
            if let last = batches.last, last.count < 200, last.last?.captureMode == row.captureMode {
                batches[batches.count - 1].append(row)
            } else {
                batches.append([row])
            }
        }
        var total = (events: 0, items: 0)
        var addedItems: [MemoryItem] = []
        var summaries: [String] = []
        var transcripts: [String] = []
        // 失败时仍刷新已保存的部分，但不能把部分成功当成整轮完成向外推送。
        defer {
            if total.events > 0 {
                lastRunAt = Date()
                NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
            }
        }
        for batch in batches {
            guard let first = batch.first else { continue }
            let result = try await digestRows(batch, day: day, system: systemPrompt(for: first.captureMode))
            total.events += result.events
            total.items += result.items.count
            addedItems.append(contentsOf: result.items)
            summaries.append(result.summary)
            transcripts.append(result.transcript)
        }
        SkillEngine.shared.runAfterDigest(day: day)
        PushEngine.shared.pushDigest(day: day, summary: summaries.joined(separator: "\n"),
            items: addedItems, transcript: transcripts.joined(separator: "\n"))
        return total
    }

    private struct BatchResult {
        let events: Int
        let items: [MemoryItem]
        let summary: String
        let transcript: String
    }

    private func digestRows(_ rows: [Segment], day: String, system: String) async throws -> BatchResult {
        let useSituation = Settings.shared.usePlaceInDigest
        var lines = Self.buildLines(rows, envTags: useSituation && Settings.shared.envSoundOn ? Store.shared.envTags(day: day) : [:])
        if useSituation {
            let places = Store.shared.places(day: day)
            for (index, row) in rows.enumerated() {
                if let place = places.first(where: { $0.arriveAt <= row.endedAt && $0.leaveAt >= row.startedAt }) {
                    lines[index] += "（地点：\(place.name)）"
                }
            }
        }
        let unfinished = Store.shared.openItemContents(days: 60)
        let ignored = Store.shared.ignoredItemContents(days: 60)

        // 2. 调模型
        let user = Prompts.digestUser(day: day, lines: lines, unfinished: unfinished, ignored: ignored)
        let reply = try await LLMClient.completeAny(system: system, user: user, temperature: 0.2, thinking: Settings.shared.deepThinking)
        // 3. 解析
        guard let data = JSONExtract.object(from: reply) else {
            throw LLMError.badReply("整理结果不是 JSON，原话已保留，请重试")
        }
        let out: DigestOut
        do {
            out = try JSONDecoder().decode(DigestOut.self, from: JSONSerialization.data(withJSONObject: data))
        } catch {
            throw LLMError.badReply("整理结果结构不正确，原话已保留，请重试")
        }
        // 只产出提取项（比如安静的一天只有一句「明天交报告」）是正常结果，
        // 不能当失败：否则 markDigested 永远不执行，每轮都重发整天原话重试，白烧 token。
        guard !out.events.isEmpty || !out.items.isEmpty else {
            throw LLMError.badReply("未返回事件，原话已保留，请重试")
        }

        // 4. 落事件
        let segById = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.offset + 1, $0.element) })
        var eventCount = 0
        for e in out.events {
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
                entityId: "\(day)-\(f.id)-\(e.from)-\(e.to)",
                lineFrom: e.from,
                lineTo: e.to,
                createdAt: Date()
            )
            Store.shared.upsertEvent(ev)
            eventCount += 1
        }

        // 5. 落提取项（同一句话重复提取要跳过）
        var existing = Set(Store.shared.items(day: day, status: nil, category: nil, limit: 500).map { $0.content })
        var newItems: [MemoryItem] = []
        for it in out.items {
            let content = (it.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, existing.insert(content).inserted else { continue }
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
        }
        Store.shared.insertItems(newItems)

        // 5b. 有明确时间的待办顺手排提醒：先算真实提醒时间，再判断是否过期，
        //     只有日期的（今天完成/明天交）落在 9 点，不会因为 00:00 被判过期而丢掉。
        for item in newItems where item.status == .pending {
            guard let due = item.dueAt, let fire = ReminderTime.resolve(due: due) else { continue }
            ReminderEngine.shared.scheduleQuick(id: item.id, title: item.content, at: fire)
        }

        // 6. 完成提示只能指向本轮提供的未完成项，并有真实原话作为依据。
        let allowedIDs = Set(unfinished.compactMap { line -> String? in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
            return obj["id"]
        })
        for hint in out.done_hints ?? [] {
            guard allowedIDs.contains(hint.item_id), let line = hint.line_id, segById[line] != nil else { continue }
            Store.shared.completeOpenItem(id: hint.item_id)
        }

        // 7. 寻物（失败不影响整理）
        await runThings(day: day, rows: rows)

        // 8. 标记已整理；技能、推送和通知由整轮汇总触发。
        Store.shared.markDigested(rows.map { $0.id })
        return BatchResult(events: eventCount, items: newItems,
            summary: out.events.compactMap { $0.summary }.joined(separator: "\n"),
            transcript: lines.joined(separator: "\n"))
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

    static func buildLines(_ rows: [Segment], envTags: [String: String] = [:]) -> [String] {
        var out: [String] = []
        var lastDay: String?
        for (i, r) in rows.enumerated() {
            if let ld = lastDay, ld != r.day {
                out.append("—— 新录音 ——")
            }
            lastDay = r.day
            let who = r.speaker.isEmpty ? "说话人1" : r.speaker
            var line = "[\(i + 1)] \(hms(r.startedAt)) \(who)：\(r.transcript)"
            if let tag = envTags[r.id], !tag.isEmpty, tag != "人声", tag != "安静" {
                line += "（环境：\(tag)）"
            }
            out.append(line)
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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 模型常把 id 写成数字、把 line_id 写成字符串；
            // 之前任一条不合规会让整个数组解码失败，"已完成"提示全军覆没。
            if let s = try? c.decode(String.self, forKey: .item_id) {
                item_id = s
            } else if let n = try? c.decode(Int.self, forKey: .item_id) {
                item_id = String(n)
            } else {
                item_id = ""
            }
            if let n = try? c.decode(Int.self, forKey: .line_id) {
                line_id = n
            } else if let s = try? c.decode(String.self, forKey: .line_id) {
                line_id = Int(s)
            } else {
                line_id = nil
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
