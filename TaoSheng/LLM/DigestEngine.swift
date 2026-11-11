import Foundation
import Combine

/// 整理引擎：把一天的转写交给大模型，产出事件 + 待办/约定/灵感等条目。
final class DigestEngine: ObservableObject {
    static let shared = DigestEngine()

    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRunAt: Date?

    private var timer: Timer?

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.runIfDue()
        }
        runIfDue()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 每天到点自动整理一次当天
    func runIfDue() {
        let s = Settings.shared
        guard s.autoDigest, s.llmReady else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= s.digestHour else { return }
        let day = DayKey.of(Date())
        if Store.shared.digest(day: day) != nil { return }
        digest(day: day)
    }

    /// 手动 / 定时整理某一天
    func digest(day: String) {
        guard !running else { return }
        let s = Settings.shared
        guard s.llmReady else {
            lastError = "先在设置里填好整理模型（Base URL / 模型 / Key）"
            return
        }
        let segs = Store.shared.segments(day: day, limit: 800)
            .filter { $0.state == .transcribed && !$0.isEmptySpeech }
            .sorted { $0.startedAt < $1.startedAt }
        guard !segs.isEmpty else {
            lastError = "这一天还没有可整理的转写内容"
            return
        }

        running = true
        lastError = nil

        var lines: [String] = []
        for (i, seg) in segs.enumerated() {
            if i > 0, seg.startedAt.timeIntervalSince(segs[i - 1].endedAt) > 600 {
                lines.append("—— 新录音 ——")
            }
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            let who = seg.speaker.isEmpty ? "" : "\(seg.speaker)："
            lines.append("[\(i + 1)] \(f.string(from: seg.startedAt)) \(who)\(seg.transcript)")
        }

        let system = Prompts.digestSystem
        let user = Prompts.digestUser(day: day, lines: lines, calendar: Prompts.calendarText())

        Task.detached(priority: .userInitiated) {
            do {
                let reply = try await LLMClient.completeAny(system: system, user: user, temperature: 0.3)
                let items = DigestEngine.parse(reply: reply, day: day)
                Store.shared.replaceItems(day: day, items: items.items)
                Store.shared.saveDigest(day: day, summary: items.summary)
                await MainActor.run {
                    self.running = false
                    self.lastRunAt = Date()
                    self.lastError = nil
                    NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
                }
            } catch {
                await MainActor.run {
                    self.running = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - 解析

    struct Parsed {
        var summary: String
        var items: [DigestItem]
    }

    static func parse(reply: String, day: String) -> Parsed {
        guard let obj = JSONExtract.object(from: reply) else {
            return Parsed(summary: "", items: [])
        }
        var out: [DigestItem] = []
        let now = Date()

        if let events = obj["events"] as? [[String: Any]] {
            for e in events {
                let title = (e["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty else { continue }
                let scene = (e["scene"] as? String) ?? ""
                var detail = (e["summary"] as? String) ?? ""
                if let points = e["points"] as? [String], !points.isEmpty {
                    detail += "\n" + points.map { "· \($0)" }.joined(separator: "\n")
                }
                out.append(DigestItem(
                    id: shortID(), day: day, kind: .event,
                    title: scene.isEmpty ? title : "\(title)",
                    detail: detail, due: "", status: .open, createdAt: now
                ))
            }
        }

        if let items = obj["items"] as? [[String: Any]] {
            for i in items {
                let content = (i["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else { continue }
                let cat = (i["category"] as? String) ?? "备忘"
                let kind: ItemKind
                switch cat {
                case "待办": kind = .todo
                case "约定": kind = .promise
                case "灵感": kind = .idea
                case "关键信息", "备忘", "决定", "知识": kind = .memory
                default: kind = .memory
                }
                let dueRaw = i["due"] as? String ?? ""
                let due = (dueRaw == "null" || dueRaw.isEmpty) ? "" : dueRaw
                var detail = cat
                if let k = i["kind"] as? String, k != "null", !k.isEmpty { detail = "\(cat) · \(k)" }
                out.append(DigestItem(
                    id: shortID(), day: day, kind: kind,
                    title: content, detail: detail, due: due, status: .open, createdAt: now
                ))
            }
        }

        let summary = (obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Parsed(summary: summary, items: out)
    }
}
