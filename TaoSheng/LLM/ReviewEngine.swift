import Foundation

/// 每日 / 每周回顾：一句话总结、要紧的事、待办、值得留意、灵感、心力
final class ReviewEngine {
    static let shared = ReviewEngine()

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
        let s = Settings.shared
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let today = DayKey.of(Date())
        guard !s.effectiveLLM.key.isEmpty else { return }
        let existing = store.reviews(limit: 20).first { $0.day == today && $0.kind == .daily }
        guard existing == nil, hour >= s.reviewHour else { return }
        // 同一天只自动试一次，失败也不反复烧请求
        if UserDefaults.standard.string(forKey: "ts.lastReviewTry") == today { return }
        UserDefaults.standard.set(today, forKey: "ts.lastReviewTry")
        Task {
            do { _ = try await self.generateDaily(day: today) }
            catch { NSLog("涛声: 自动回顾失败 \(error)") }
        }
    }

    // MARK: - 每日

    func generateDaily(day: String) async throws -> ReviewRecord {
        let lines = store.transcriptLines(day: day)
        guard !lines.isEmpty else { throw TranscribeError.empty }
        var context = ""
        for l in lines {
            let who = l.speaker.isEmpty ? "" : "\(l.speaker)："
            context += "\(l.time) \(who)\(l.text)\n"
        }
        if context.count > 12000 {
            context = String(context.prefix(12000))
        }

        let system = PromptsAsk.reviewSystem

        let reply = try await LLMClient.completeAny(system: system, user: "\(day) 的原话：\n\(context)", temperature: 0.3)
        let obj = JSONExtract.object(from: reply)

        var headline = "今天没什么特别的"
        var body = ""
        if let o = obj {
            if let h = o["brief"] as? String, !h.isEmpty { headline = h }
            if let secs = o["sections"] as? [[String: Any]] {
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
                    body += "## \(title)\n"
                    for l in rows { body += "- \(l)\n" }
                    body += "\n"
                }
            }
        } else {
            body = reply
        }

        let rec = ReviewRecord(
            id: "daily-\(day)",
            kind: .daily,
            day: day,
            headline: headline,
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
            context = String(context.prefix(16000))
        }

        let system = """
        你是用户的私人记录助手。基于最近一周的原话，写一份「每周回顾」。
        只输出 JSON：
        {"headline":"一句话总结这一周（不超过 24 字）",
         "sections":[{"title":"关键进展","lines":[]},{"title":"反复出现的问题","lines":[]},{"title":"下周最重要的三件事","lines":[]},{"title":"人际与协作","lines":[]}]}
        规则：每节 1~4 条，每条不超过 40 字，只写原话里有的。
        """

        let reply = try await LLMClient.completeAny(system: system, user: "这一周的原话：\n\(context)", temperature: 0.3)
        let obj = JSONExtract.object(from: reply)

        var headline = "这一周"
        var body = ""
        if let o = obj {
            if let h = o["headline"] as? String, !h.isEmpty { headline = h }
            if let secs = o["sections"] as? [[String: Any]] {
                for sec in secs {
                    let title = (sec["title"] as? String) ?? ""
                    let lines = (sec["lines"] as? [String]) ?? []
                    guard !lines.isEmpty else { continue }
                    body += "## \(title)\n"
                    for l in lines { body += "- \(l)\n" }
                    body += "\n"
                }
            }
        } else {
            body = reply
        }

        let rec = ReviewRecord(
            id: "weekly-\(endDay)",
            kind: .weekly,
            day: endDay,
            headline: headline,
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
