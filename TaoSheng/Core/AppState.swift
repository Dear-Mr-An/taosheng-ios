import Foundation
import Combine

extension Notification.Name {
    static let taoshengDataChanged = Notification.Name("taoshengDataChanged")
    static let taoshengAskChanged = Notification.Name("taoshengAskChanged")
}

/// 全局聚合状态：一次刷新，各页共用
final class AppState: ObservableObject {
    static let shared = AppState()

    private var refreshGen = 0
    private var dayGen = 0

    private let store = Store.shared

    // 今天
    @Published var todaySegments: [Segment] = []
    @Published var todayEvents: [MemoryEvent] = []
    @Published var todayItems: [MemoryItem] = []
    @Published var todayCards: [SkillCard] = []
    @Published var todayReview: ReviewRecord?
    @Published var days: [String] = []

    // 待办（跨天）
    @Published var pendingItems: [MemoryItem] = []
    @Published var activeItems: [MemoryItem] = []
    @Published var doneItems: [MemoryItem] = []
    @Published var counts: (pending: Int, accepted: Int, done: Int) = (0, 0, 0)

    // 配置类
    @Published var persons: [Person] = []
    @Published var skills: [SkillDef] = []
    @Published var channels: [Channel] = []
    @Published var reminders: [Reminder] = []
    @Published var reviews: [ReviewRecord] = []
    @Published var hotwords: [Hotword] = []
    @Published var askMessages: [AskMessage] = []
    @Published var skillRuns: [SkillRun] = []
    @Published var things: [Thing] = []

    // 选中的那天（记忆页）
    @Published var selectedDay: String = DayKey.of(Date())
    @Published var daySegments: [Segment] = []
    @Published var dayEvents: [MemoryEvent] = []
    @Published var dayItems: [MemoryItem] = []
    @Published var dayCards: [SkillCard] = []
    @Published var dayReview: ReviewRecord?
    @Published var starredList: [MemoryEvent] = []

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
            store.upsertPerson(Person(
                id: "me", name: "我", colorHex: "#F0833E",
                note: "默认认作本人的声音", isMe: true, sampleCount: 0, createdAt: Date()
            ))
        }
        if store.skills().isEmpty {
            let now = Date()
            let builtins: [SkillDef] = [
                SkillDef(id: "meeting", name: "会议速记", symbol: "person.2.wave.2",
                         desc: "把有明确议题的多人讨论整理成会议卡",
                         enabled: true, schedule: .afterDigest, hour: 0, minute: 0, weekday: 1,
                         prompt: "把今天识别为会议的内容整理成会议卡：议题、结论、分点要点、决定。",
                         builtin: true, createdAt: now,
                         fields: [
                            SkillField(key: "topic", label: "议题", type: "text", required: true),
                            SkillField(key: "conclusion", label: "结论先行", type: "paragraph", required: true),
                            SkillField(key: "points", label: "分点要点", type: "bullets", required: false),
                            SkillField(key: "decisions", label: "决定", type: "bullets", required: false)
                         ]),
                SkillDef(id: "checkout", name: "收工打卡", symbol: "checkmark.seal",
                         desc: "用自己的记录回看今天做了什么",
                         enabled: true, schedule: .daily, hour: 18, minute: 0, weekday: 1,
                         prompt: "用自己的记录回看今天做了什么。",
                         builtin: true, createdAt: now.addingTimeInterval(1),
                         fields: [
                            SkillField(key: "done", label: "今天做了什么", type: "bullets", required: true),
                            SkillField(key: "progress", label: "推进到哪一步", type: "bullets", required: false),
                            SkillField(key: "tomorrow", label: "明天接着做", type: "bullets", required: false)
                         ]),
                SkillDef(id: "weekly", name: "每周回顾", symbol: "calendar.badge.clock",
                         desc: "一周的收获、卡点与下周计划",
                         enabled: false, schedule: .weekly, hour: 21, minute: 0, weekday: 1,
                         prompt: "总结这一周：关键进展、反复出现的问题、下周最重要的三件事。",
                         builtin: true, createdAt: now.addingTimeInterval(2),
                         fields: [
                            SkillField(key: "progress", label: "关键进展", type: "bullets", required: true),
                            SkillField(key: "problems", label: "反复出现的问题", type: "bullets", required: false),
                            SkillField(key: "next", label: "下周最重要的三件事", type: "bullets", required: false)
                         ]),
                SkillDef(id: "mood", name: "情绪日记", symbol: "heart.text.square",
                         desc: "记录今天的情绪变化与原因",
                         enabled: false, schedule: .daily, hour: 22, minute: 15, weekday: 1,
                         prompt: "从今天的原话里读出情绪变化：什么时候状态好、什么时候烦躁、因为什么。",
                         builtin: true, createdAt: now.addingTimeInterval(3),
                         fields: [
                            SkillField(key: "mood", label: "今天的心情", type: "text", required: true),
                            SkillField(key: "reason", label: "因为什么", type: "paragraph", required: false),
                            SkillField(key: "shift", label: "情绪变化", type: "bullets", required: false)
                         ])
            ]
            builtins.forEach { store.upsertSkill($0) }
        }
        Settings.shared.onboarded = true
    }

    // MARK: - 刷新

    func wipeAll() {
        store.wipeAll()
        seedIfNeeded()
        refresh()
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
    }

    /// 一次性把界面要用的数据全查出来。
    /// 20 多次 SQL 不能压在主线程上 —— 每转写一段、每勾一个待办都会发通知触发这里，
    /// 同步跑会把滚动和点击卡住。查询放后台，赋值回主线程，并用代数号丢弃过期结果。
    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        let today = DayKey.of(Date())
        refreshGen &+= 1
        let gen = refreshGen
        // 选中非今天时也更新当天数据；日期查询独立启动，永远只在主线程改代数号。
        if selectedDay != today { refreshDay(selectedDay) }
        else { dayGen &+= 1 } // 取消此前某个旧日期仍在执行的查询
        DispatchQueue.global(qos: .userInitiated).async {
            let segs = self.store.segments(day: today, limit: 600)
            let evs = self.store.events(day: today, limit: 300)
            let its = self.store.items(day: today, status: nil, category: nil, limit: 300)
            let cards = self.store.cards(day: today, skillId: nil, limit: 40)
            let pend = self.store.items(day: nil, status: .pending, category: nil, limit: 200)
            let act = self.store.items(day: nil, status: .accepted, category: nil, limit: 200)
            let done = self.store.items(day: nil, status: .done, category: nil, limit: 200)
            let cnt = self.store.itemCounts()
            let rev = self.store.reviews(limit: 60).first { $0.day == today }
            let ppl = self.store.persons()
            let sk = self.store.skills()
            let ch = self.store.channels()
            let rm = self.store.reminders()
            let rv = self.store.reviews(limit: 30)
            let hw = self.store.hotwords()
            let dk = self.store.dayKeys(limit: 90)
            let ask = self.store.askMessages(limit: 200)
            let runs = self.store.skillRuns(day: nil, limit: 40)
            let th = self.store.things(limit: 200)
            let star = self.store.starredEvents(limit: 100)

            DispatchQueue.main.async {
                guard gen == self.refreshGen else { return }
                self.todaySegments = segs
                self.todayEvents = evs
                self.todayItems = its
                self.todayCards = cards
                self.todayReview = rev
                self.pendingItems = pend
                self.activeItems = act
                self.doneItems = done
                self.counts = cnt
                self.persons = ppl
                self.skills = sk
                self.channels = ch
                self.reminders = rm
                self.reviews = rv
                self.hotwords = hw
                self.days = dk
                self.askMessages = ask
                self.skillRuns = runs
                self.things = th
                self.starredList = star
                // 查询期间用户可能切换了日期，按当前选择判断，避免旧日期数据覆写。
                if self.selectedDay == today {
                    self.daySegments = segs
                    self.dayEvents = evs
                    self.dayItems = its
                    self.dayCards = cards
                    self.dayReview = rev
                }
            }
        }
    }

    func refreshDay(_ day: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshDay(day) }
            return
        }
        selectedDay = day
        dayGen &+= 1
        let gen = dayGen
        DispatchQueue.global(qos: .userInitiated).async {
            let segs = self.store.segments(day: day, limit: 600)
            let evs = self.store.events(day: day, limit: 300)
            let its = self.store.items(day: day, status: nil, category: nil, limit: 300)
            let cards = self.store.cards(day: day, skillId: nil, limit: 40)
            let rev = self.store.reviews(limit: 60).first { $0.day == day }
            DispatchQueue.main.async {
                guard gen == self.dayGen, self.selectedDay == day else { return }
                self.daySegments = segs
                self.dayEvents = evs
                self.dayItems = its
                self.dayCards = cards
                self.dayReview = rev
            }
        }
    }

    // MARK: - 提取项操作

    func setItemStatus(_ id: String, status: MemItemStatus) {
        store.setItemStatus(id: id, status: status)
        refresh()
    }

    func deleteItem(_ id: String) {
        store.deleteItem(id: id)
        refresh()
    }

    /// 手动加一条待办（文字原样，走 LLM 拆卡由 UI 决定）
    func addItem(content: String, category: String = "待办", due: String? = nil) {
        let it = MemoryItem(
            id: shortID(), eventId: nil, day: DayKey.of(Date()),
            category: category, kind: "我要做", content: content,
            status: .accepted, dueText: due, dueAt: DigestEngine.parseDue(due),
            who: nil, sourceText: nil, createdAt: Date(), updatedAt: Date()
        )
        store.insertItems([it])
        refresh()
    }

    /// 一次加多条（语音拆卡场景）：只落一次库、只刷新一次，
    /// 否则拆出 5 条就要跑 5 × 20 多次 SQL，卡在弹窗里。
    func addItems(_ drafts: [(content: String, category: String, due: String?)]) {
        guard !drafts.isEmpty else { return }
        let now = Date()
        let day = DayKey.of(now)
        let list = drafts.map { d in
            MemoryItem(
                id: shortID(), eventId: nil, day: day,
                category: d.category, kind: "我要做", content: d.content,
                status: .accepted, dueText: d.due, dueAt: DigestEngine.parseDue(d.due),
                who: nil, sourceText: nil, createdAt: now, updatedAt: now
            )
        }
        store.insertItems(list)
        refresh()
    }

    // MARK: - 事件操作

    func starEvent(_ id: String, starred: Bool) {
        store.setEventStar(id: id, starred: starred)
        refresh()
    }

    func deleteEvent(_ id: String) {
        store.deleteEvent(id: id)
        refresh()
    }

    func toggleSkill(_ id: String) {
        guard var s = skills.first(where: { $0.id == id }) else { return }
        s.enabled.toggle()
        store.upsertSkill(s)
        refresh()
    }

    func saveSkill(_ s: SkillDef) {
        store.upsertSkill(s)
        refresh()
    }

    func deleteSkill(_ id: String) {
        store.deleteSkill(id: id)
        refresh()
    }

    func addPerson(name: String) {
        let idx = persons.count % personPalette.count
        store.upsertPerson(Person(
            id: shortID(), name: name, colorHex: personPalette[idx],
            note: "", isMe: false, sampleCount: 0, createdAt: Date()
        ))
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
            id: shortID(), title: title, fireAt: date, itemId: "",
            enabled: true, repeatDaily: repeatDaily, createdAt: Date()
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
        store.upsertHotword(Hotword(id: shortID(), word: word, replacement: replacement, createdAt: Date()))
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

    var pendingCount: Int { counts.pending }

    var todayTalkText: String {
        let s = Int(todaySeconds.rounded())
        if s < 60 { return "\(s)秒" }
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)小时\(m)分" : "\(m)分钟"
    }

    var todaySeconds: Double {
        todaySegments.reduce(0) { $0 + $1.duration }
    }

    var eventCount: Int { todayEvents.count }

    var peopleCount: Int {
        Set(todayEvents.flatMap { $0.people }).count
    }

    var meetingCount: Int {
        todayEvents.filter { $0.scene == "会议" }.count
    }

    var mySeconds: Double {
        todaySegments.filter { $0.speaker == "我" }.reduce(0) { $0 + $1.duration }
    }

    var otherSeconds: Double {
        todaySegments.filter { $0.speaker != "我" && !$0.speaker.isEmpty }.reduce(0) { $0 + $1.duration }
    }

    /// 所有跨天未完成的待办 + 约定（待办页）
    var allOpenItems: [MemoryItem] {
        (pendingItems + activeItems).sorted { a, b in
            (a.dueAt ?? Date.distantFuture) < (b.dueAt ?? Date.distantFuture)
        }
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
        let evs = store.events(day: day, limit: 500)
        let its = store.items(day: day, status: nil, category: nil, limit: 500)
        let cards = store.cards(day: day, skillId: nil, limit: 40)
        var out = "# 涛声 · \(day)\n\n"

        if let r = store.reviews(limit: 60).first(where: { $0.day == day }), !r.headline.isEmpty {
            out += "## 一句话\n\n\(r.headline)\n\n"
        }
        if !evs.isEmpty {
            out += "## 时间线\n\n"
            for e in evs {
                out += "### \(e.timeText) \(e.title)\n\n"
                if !e.summary.isEmpty { out += "\(e.summary)\n\n" }
                for p in e.points { out += "- \(p)\n" }
                if !e.points.isEmpty { out += "\n" }
            }
        }
        if !its.isEmpty {
            out += "## 提取\n\n"
            for i in its {
                let mark = i.status == .done ? "x" : " "
                out += "- [\(mark)] **\(i.category)** \(i.content)"
                if let d = i.dueDisplay { out += "（\(d)）" }
                out += "\n"
            }
            out += "\n"
        }
        for c in cards where !c.isNothing {
            out += "## \(c.skillName)\n\n"
            for (k, v) in c.fields where !v.isEmpty { out += "**\(k)**：\(v)\n\n" }
        }
        out += "## 原话\n\n"
        for s in segs where !s.transcript.isEmpty {
            let who = s.speaker.isEmpty ? "" : "\(s.speaker)："
            out += "- \(s.timeText) \(who)\(s.transcript)\n"
        }
        return out
    }
}
