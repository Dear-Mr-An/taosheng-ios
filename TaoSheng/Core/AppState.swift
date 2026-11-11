import Foundation
import Combine

extension Notification.Name {
    static let taoshengDataChanged = Notification.Name("taoshengDataChanged")
    static let taoshengAskChanged = Notification.Name("taoshengAskChanged")
}

/// 全局聚合状态：一次刷新，各页共用
final class AppState: ObservableObject {
    static let shared = AppState()

    private let store = Store.shared

    @Published var todaySegments: [Segment] = []
    @Published var days: [String] = []
    @Published var todayItems: [DigestItem] = []
    @Published var openItems: [DigestItem] = []
    @Published var todaySummary: String = ""
    @Published var stats: (segments: Int, transcribed: Int, pending: Int, seconds: Double) = (0, 0, 0, 0)

    @Published var persons: [Person] = []
    @Published var skills: [SkillDef] = []
    @Published var channels: [Channel] = []
    @Published var reminders: [Reminder] = []
    @Published var reviews: [ReviewRecord] = []
    @Published var hotwords: [Hotword] = []
    @Published var askMessages: [AskMessage] = []
    @Published var skillRuns: [SkillRun] = []

    @Published var selectedDay: String = DayKey.of(Date())
    @Published var daySegments: [Segment] = []
    @Published var dayItems: [DigestItem] = []
    @Published var dayReview: ReviewRecord? = nil
    @Published var dayPlaces: [PlaceVisit] = []

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .taoshengDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        seedIfNeeded()
        refresh()
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - 首次初始化内置数据

    private func seedIfNeeded() {
        if store.persons().isEmpty {
            let me = Person(
                id: "me",
                name: "我",
                colorHex: "#F0833E",
                note: "默认认作本人的声音",
                isMe: true,
                sampleCount: 0,
                createdAt: Date()
            )
            store.upsertPerson(me)
        }
        if store.skills().isEmpty {
            let now = Date()
            let builtins: [SkillDef] = [
                SkillDef(id: "meeting", name: "会议速记", symbol: "person.2.wave.2", desc: "说完自动识别，整理成会议纪要",
                         enabled: true, schedule: .afterDigest, hour: 0, minute: 0, weekday: 1,
                         prompt: "把今天识别为会议的内容整理成会议纪要：参会人、议题、结论、待办。", builtin: true, createdAt: now),
                SkillDef(id: "checkout", name: "收工打卡", symbol: "checkmark.seal", desc: "每天下班时总结今天做完的事",
                         enabled: false, schedule: .daily, hour: 18, minute: 0, weekday: 1,
                         prompt: "总结今天完成的事、没做完的事、明天第一件事。", builtin: true, createdAt: now.addingTimeInterval(1)),
                SkillDef(id: "weekly", name: "每周回顾", symbol: "calendar.badge.clock", desc: "一周的收获、卡点与下周计划",
                         enabled: false, schedule: .weekly, hour: 21, minute: 0, weekday: 1,
                         prompt: "总结这一周：关键进展、反复出现的问题、下周最重要的三件事。", builtin: true, createdAt: now.addingTimeInterval(2)),
                SkillDef(id: "mood", name: "情绪日记", symbol: "heart.text.square", desc: "记录今天的情绪变化与原因",
                         enabled: false, schedule: .daily, hour: 22, minute: 15, weekday: 1,
                         prompt: "从今天的原话里读出情绪变化：什么时候状态好、什么时候烦躁、因为什么。", builtin: true, createdAt: now.addingTimeInterval(3))
            ]
            builtins.forEach { store.upsertSkill($0) }
        }
        if !Settings.shared.onboarded {
            Settings.shared.onboarded = true
        }
    }

    // MARK: - 刷新

    /// 清空数据后重建内置人物与技能
    func wipeAll() {
        store.wipeAll()
        seedIfNeeded()
        refresh()
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
    }

    func refresh() {
        let today = DayKey.of(Date())
        let segs = store.segments(day: today, limit: 400)
        let items = store.items(day: today, openOnly: false)
        let open = store.items(day: nil, openOnly: true)
        let st = store.todayStats()
        let dig = store.digest(day: today)
        let ppl = store.persons()
        let sk = store.skills()
        let ch = store.channels()
        let rm = store.reminders()
        let rv = store.reviews(limit: 30)
        let hw = store.hotwords()
        let dk = store.dayKeys(limit: 90)
        let ask = store.askMessages(limit: 200)
        let runs = store.skillRuns(day: nil, limit: 40)

        DispatchQueue.main.async {
            self.todaySegments = segs
            self.todayItems = items
            self.openItems = open
            self.stats = st
            self.todaySummary = dig?.summary ?? ""
            self.persons = ppl
            self.skills = sk
            self.channels = ch
            self.reminders = rm
            self.reviews = rv
            self.hotwords = hw
            self.days = dk
            self.askMessages = ask
            self.skillRuns = runs
        }
        refreshDay(selectedDay)
    }

    func refreshDay(_ day: String) {
        selectedDay = day
        let segs = store.segments(day: day, limit: 400)
        let items = store.items(day: day, openOnly: false)
        let rev = store.reviews(limit: 60).first { $0.day == day }
        let places = store.places(day: day)
        DispatchQueue.main.async {
            self.daySegments = segs
            self.dayItems = items
            self.dayReview = rev
            self.dayPlaces = places
        }
    }

    // MARK: - 操作

    func toggleItem(_ id: String) {
        store.toggleItem(id: id)
        refresh()
    }

    func setItemDone(_ id: String, done: Bool) {
        store.setItemStatus(id: id, status: done ? .done : .open)
        refresh()
    }

    func deleteItem(_ id: String) {
        store.deleteItem(id: id)
        refresh()
    }

    func addTodo(title: String, due: String, day: String = DayKey.of(Date())) {
        let item = DigestItem(
            id: shortID(),
            day: day,
            kind: .todo,
            title: title,
            detail: "",
            due: due,
            status: .open,
            createdAt: Date()
        )
        store.insert(item)
        refresh()
    }

    func toggleSkill(_ id: String) {
        guard var s = skills.first(where: { $0.id == id }) else { return }
        s.enabled.toggle()
        store.upsertSkill(s)
        refresh()
    }

    func deleteSkill(_ id: String) {
        store.deleteSkill(id: id)
        refresh()
    }

    func addPerson(name: String) {
        let idx = persons.count % personPalette.count
        let p = Person(
            id: shortID(),
            name: name,
            colorHex: personPalette[idx],
            note: "",
            isMe: false,
            sampleCount: 0,
            createdAt: Date()
        )
        store.upsertPerson(p)
        refresh()
    }

    func deletePerson(_ id: String) {
        store.deletePerson(id: id)
        refresh()
    }

    func addChannel(_ c: Channel) {
        store.upsertChannel(c)
        refresh()
    }

    func deleteChannel(_ id: String) {
        store.deleteChannel(id: id)
        refresh()
    }

    func addReminder(title: String, at date: Date, repeatDaily: Bool) {
        let r = Reminder(
            id: shortID(),
            title: title,
            fireAt: date,
            itemId: "",
            enabled: true,
            repeatDaily: repeatDaily,
            createdAt: Date()
        )
        store.upsertReminder(r)
        ReminderEngine.shared.schedule(r)
        refresh()
    }

    func deleteReminder(_ id: String) {
        store.deleteReminder(id: id)
        ReminderEngine.shared.cancel(id)
        refresh()
    }

    func addHotword(word: String, replacement: String) {
        let h = Hotword(id: shortID(), word: word, replacement: replacement, createdAt: Date())
        store.upsertHotword(h)
        refresh()
    }

    func deleteHotword(_ id: String) {
        store.deleteHotword(id: id)
        refresh()
    }

    func clearAsk() {
        store.clearAsk()
        refresh()
    }

    func recordAsk(question: String) {
        store.insertAsk(AskMessage(id: shortID(), role: .me, text: question, citations: [], createdAt: Date()))
        refresh()
    }

    func recordAnswer(text: String, citations: [String]) {
        store.insertAsk(AskMessage(id: shortID(), role: .ai, text: text, citations: citations, createdAt: Date()))
        refresh()
    }

    // MARK: - 派生

    var pendingCount: Int { stats.pending }

    var todayTalkText: String {
        let s = Int(stats.seconds.rounded())
        if s < 60 { return "\(s)秒" }
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分钟"
    }

    var peopleCount: Int {
        Set(todaySegments.map { $0.speaker }.filter { !$0.isEmpty }).count
    }

    var eventCount: Int { todayItems.count }

    var mySeconds: Double {
        todaySegments.filter { $0.speaker == "我" }.reduce(0) { $0 + $1.duration }
    }

    var otherSeconds: Double {
        todaySegments.filter { $0.speaker != "我" && !$0.speaker.isEmpty }.reduce(0) { $0 + $1.duration }
    }

    // MARK: - 维护

    func purgeOldAudio() {
        let keep = Settings.shared.keepAudioDays
        guard keep > 0 else { return }
        let cut = Date().addingTimeInterval(-Double(keep) * 86400)
        let old = store.segments(day: nil, limit: 5000).filter { $0.startedAt < cut }
        for s in old where !store.isStarred(id: s.id) {
            store.deleteSegment(id: s.id, removeFile: true)
        }
        refresh()
    }

    func exportMarkdown(day: String) -> String {
        let segs = store.segments(day: day, limit: 1000).sorted { $0.startedAt < $1.startedAt }
        let items = store.items(day: day, openOnly: false)
        let dig = store.digest(day: day)
        var out = "# 涛声 · \(day)\n\n"
        if let d = dig, !d.summary.isEmpty {
            out += "## 概要\n\n\(d.summary)\n\n"
        }
        if !items.isEmpty {
            out += "## 事件与待办\n\n"
            for i in items {
                let mark = i.status == .done ? "[x]" : "[ ]"
                out += "- \(mark) **\(i.kind.title)** \(i.title)"
                if !i.due.isEmpty { out += "（\(i.due)）" }
                if !i.detail.isEmpty { out += " — \(i.detail)" }
                out += "\n"
            }
            out += "\n"
        }
        out += "## 原话\n\n"
        for s in segs where !s.isEmptySpeech {
            let who = s.speaker.isEmpty ? "" : "\(s.speaker)："
            out += "- \(s.timeText) \(who)\(s.transcript)\n"
        }
        return out
    }
}
