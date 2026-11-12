import Foundation

/// 每日 / 每周回顾：一句话总结、要紧的事、待办、值得留意、灵感、心力
final class ReviewEngine {
    static let shared = ReviewEngine()

    private let store = Store.shared
    private var timer: Timer?
    private var dailyInFlight = Set<String>()
    private var weeklyInFlight = Set<String>()
    private var lastDailyAttempt: [String: Date] = [:]
    private var lastWeeklyAttempt: [String: Date] = [:]

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.runIfDue()
        }
        runIfDue()
    }

    func runIfDue() {
        let s = Settings.shared
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let today = DayKey.of(now)
        guard !s.effectiveLLM.key.isEmpty else { return }

        let done = store.reviews(limit: 40)

        // 每日回顾：到点、今天还没生成、今天没试过
        let dailyDone = done.contains { $0.day == today && $0.kind == .daily }
        if !dailyDone, hour >= s.reviewHour,
           UserDefaults.standard.string(forKey: "ts.lastReviewTry") != today,
           !dailyInFlight.contains(today),
           now.timeIntervalSince(lastDailyAttempt[today] ?? .distantPast) >= 300 {
            dailyInFlight.insert(today)
            lastDailyAttempt[today] = now
            Task {
                defer { self.dailyInFlight.remove(today) }
                do {
                    _ = try await self.generateDaily(day: today)
                    UserDefaults.standard.set(today, forKey: "ts.lastReviewTry")
                } catch {
                    NSLog("涛声: 自动回顾失败 \(error)")
                }
            }
        }

        // 同一天可同时有每日和每周回顾；每日失败也不能挡住周回顾。
        let weekday = cal.component(.weekday, from: now)
        guard weekday == s.weeklyReviewWeekday, hour >= s.reviewHour else { return }
        let weekDone = done.contains { $0.kind == .weekly && $0.day == today }
        guard !weekDone,
              UserDefaults.standard.string(forKey: "ts.lastWeeklyTry") != today,
              !weeklyInFlight.contains(today),
              now.timeIntervalSince(lastWeeklyAttempt[today] ?? .distantPast) >= 300 else { return }
        weeklyInFlight.insert(today)
        lastWeeklyAttempt[today] = now
        Task {
            defer { self.weeklyInFlight.remove(today) }
            do {
                _ = try await self.generateWeekly(endDay: today)
                UserDefaults.standard.set(today, forKey: "ts.lastWeeklyTry")
            } catch {
                NSLog("涛声: 周回顾失败 \(error)")
            }
        }
    }

    // MARK: - 每日

    func generateDaily(day: String) async throws -> ReviewRecord {
        let s = Settings.shared
        // Store 按时间倒序返回；回顾契约要求按时间升序编号和输入。
        let evs = store.events(day: day, limit: 400).reversed()
        let allItems = store.items(day: day, status: nil, category: nil, limit: 400)
        guard !evs.isEmpty || !allItems.isEmpty else { throw TranscribeError.empty }

        // 事件编号换成 1..N：提示词要求 eventId 是整数，而且只能是本轮输入里的
        var numOf: [String: Int] = [:]
        for (i, e) in evs.enumerated() { numOf[e.id] = i + 1 }

        let iso = ISO8601DateFormatter()
        var byEvent: [String: [[String: Any]]] = [:]
        var orphans: [[String: Any]] = []
        for it in allItems {
            var d: [String: Any] = [
                "status": it.status.rawValue,
                "category": it.category,
                "content": it.content,
                "createdAt": iso.string(from: it.createdAt)
            ]
            if let t = it.dueText, !t.isEmpty { d["dueText"] = t }
            if let a = it.dueAt { d["dueAt"] = iso.string(from: a) }
            if let eid = it.eventId, numOf[eid] != nil {
                byEvent[eid, default: []].append(d)
            } else {
                orphans.append(d)
            }
        }

        var evArr: [[String: Any]] = []
        for (i, e) in evs.enumerated() {
            var d: [String: Any] = [
                "id": i + 1,
                "title": e.title,
                "summary": e.summary,
                "points": e.points,
                "people": e.people,
                "emotion": e.emotion,
                "intensity": e.intensity,
                "important": e.important,
                "starred": e.starred,
                "startAt": iso.string(from: e.startAt),
                "items": byEvent[e.id] ?? []
            ]
            if let place = e.place, !place.isEmpty { d["place"] = place }
            evArr.append(d)
        }
        if !orphans.isEmpty {
            evArr.append([
                "id": evs.count + 1,
                "title": "零散记录",
                "summary": "没有归到具体事件的条目",
                "points": [], "people": [],
                "emotion": "平静", "intensity": 3,
                "important": false, "starred": false,
                "startAt": iso.string(from: Date()),
                "items": orphans
            ])
        }

        // 标星满 3 天还没新进展的历史重点
        let cal = Calendar.current
        var stale: [[String: Any]] = []
        for e in store.starredEvents(limit: 60) {
            guard let at = e.starredAt else { continue }
            let days = cal.dateComponents([.day], from: at, to: Date()).day ?? 0
            guard days >= 3, numOf[e.id] == nil else { continue }
            stale.append(["id": evArr.count + stale.count + 1,
                          "title": e.title,
                          "day": e.day,
                          "starredAt": iso.string(from: at)])
            if stale.count == 5 { break }
        }

        // 时间窗：昨晚 reviewHour → 今晚 reviewHour
        let end = cal.date(bySettingHour: s.reviewHour, minute: 0, second: 0, of: Date()) ?? Date()
        let start = cal.date(byAdding: .day, value: -1, to: end) ?? end

        let payload: [String: Any] = [
            "date": day,
            "timeWindow": ["startExclusive": iso.string(from: start),
                           "endInclusive": iso.string(from: end)],
            "events": evArr,
            "starred_stale": stale
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let user = String(data: body, encoding: .utf8) else {
            throw LLMError.badReply("回顾输入组装失败")
        }

        let reply = try await LLMClient.completeAny(system: PromptsAsk.reviewSystem, user: user, temperature: 0.2)
        // 解析不出就是失败，不能存成空白回顾 —— 否则当天判定已生成，再也不会重来
        guard let obj = JSONExtract.object(from: reply) else {
            throw LLMError.badReply("回顾结果不是 JSON，请重试")
        }

        var headline = ""
        var bodyText = ""
        if let h = obj["brief"] as? String { headline = h.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let secs = obj["sections"] as? [[String: Any]] {
            for sec in secs {
                let title = (sec["title"] as? String) ?? ""
                guard !title.isEmpty else { continue }
                var rows: [String] = []
                if let ls = sec["lines"] as? [[String: Any]] {
                    for l in ls {
                        if let t = l["text"] as? String, !t.isEmpty { rows.append(t) }
                    }
                } else if let ls = sec["lines"] as? [String] {
                    rows = ls
                }
                guard !rows.isEmpty else { continue }
                bodyText += "## \(title)\n"
                for l in rows { bodyText += "- \(l)\n" }
                bodyText += "\n"
            }
        }
        guard !bodyText.isEmpty else {
            throw LLMError.badReply("回顾没有任何栏目，请重试")
        }
        if headline.isEmpty { headline = "今天的一天" }

        let rec = ReviewRecord(
            id: "daily-\(day)",
            kind: .daily,
            day: day,
            headline: headline,
            text: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        store.saveReview(rec)

        if s.pushOnReview {
            PushEngine.shared.pushReview(rec)
        }
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        return rec
    }

    // MARK: - 每周

    func generateWeekly(endDay: String) async throws -> ReviewRecord {
        let segs = store.recentTranscripts(days: 7, limit: 300)
        guard !segs.isEmpty else { throw TranscribeError.empty }
        var context = ""
        for s in segs.reversed() {
            let who = s.speaker.isEmpty ? "" : "\(s.speaker)："
            context += "\(s.day) \(s.timeText) \(who)\(s.transcript)\n"
        }
        if context.count > 16000 {
            context = String(context.suffix(16000))
        }

        let system = """
        你是用户的私人记录助手。基于最近一周的原话，写一份「每周回顾」。
        只输出 JSON：
        {"headline":"一句话总结这一周（不超过 24 字）",
         "sections":[{"title":"关键进展","lines":[]},{"title":"反复出现的问题","lines":[]},{"title":"下周最重要的三件事","lines":[]},{"title":"人际与协作","lines":[]}]}
        规则：每节 1~4 条，每条不超过 40 字，只写原话里有的。
        """

        let reply = try await LLMClient.completeAny(system: system, user: "这一周的原话：\n\(context)", temperature: 0.3)
        guard let obj = JSONExtract.object(from: reply),
              let sections = obj["sections"] as? [[String: Any]] else {
            throw LLMError.badReply("周回顾结果不是有效 JSON，请重试")
        }

        let headline = ((obj["headline"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var body = ""
        for sec in sections {
            let title = ((sec["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = ((sec["lines"] as? [String]) ?? []).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard !title.isEmpty, !lines.isEmpty else { continue }
            body += "## \(title)\n"
            for line in lines { body += "- \(line)\n" }
            body += "\n"
        }
        guard !body.isEmpty else { throw LLMError.badReply("周回顾没有任何栏目，请重试") }

        let rec = ReviewRecord(
            id: "weekly-\(endDay)",
            kind: .weekly,
            day: endDay,
            headline: headline.isEmpty ? "这一周" : headline,
            text: body.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date()
        )
        store.saveReview(rec)
        if Settings.shared.pushOnReview {
            PushEngine.shared.pushReview(rec)
        }
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        return rec
    }
}
