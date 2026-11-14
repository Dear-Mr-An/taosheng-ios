import SwiftUI

struct MemoryView: View {
    @ObservedObject private var app = AppState.shared
    @State private var byDay = true
    @State private var showShare = false
    @State private var exportBusy = false
    @State private var exported = ""
    @State private var showReview = false
    @State private var toast: String?
    @State private var cat = "重点"
    @State private var detailEvent: MemoryEvent?
    /// 分类页的 200 行查询从 body 里搬出来（每次重绘同步查库会卡滚动）
    @State private var catItems: [MemoryItem] = []
    @State private var catLoading = false
    /// catItems 当前装的是哪个分类：切到别的分类时先清空，否则会闪一下上一类的数据
    @State private var loadedCat = ""
    @State private var weekOffset = 0
    @State private var reviewBusy = false
    /// 0 全部 / 1 会议 / 2 培训：只筛「按天」这一支，按类那支不动
    @State private var kindFilter = 0
    @State private var noteEvent: MemoryEvent?
    @State private var activeRailKey: String?

    private let cats = ["重点", "寻物", "灵感", "关键信息", "决定"]

    private var day: String { app.selectedDay }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sp3 + 2) {
                    header
                    if byDay {
                        dayStrip
                        kindBar
                        reviewCard
                        cardsCard
                        timelineCard(proxy: proxy)
                    } else {
                        catChips
                        catList
                    }
                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, Theme.sp4)
                .padding(.top, 8)
            }
            .coordinateSpace(name: "railScroll")
            .onPreferenceChange(RailOffsetKey.self) { map in
                let visible = map.filter { $0.value <= 4 && $0.value > -260 }
                if let key = visible.max(by: { $0.value < $1.value })?.key, key != activeRailKey {
                    activeRailKey = key
                }
            }
        }
        .tabBarClearance()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task(id: "\(cat)|\(byDay)") {
            await loadCat()
            guard let s = ShotMode.screen else { return }
            if s == "memory-filter-meeting" { kindFilter = 1 }
            if (s == "card-sheet-top" || s == "card-sheet-bottom"), noteEvent == nil {
                noteEvent = app.dayEvents.first { $0.sessionId != nil } ?? app.dayEvents.first
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in
            Task { await loadCat() }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [exported])
        }
        .sheet(isPresented: $showReview) {
            NavigationStack { ReviewSheet(day: day) }
        }
        .sheet(item: $detailEvent) { e in
            EventDetailView(event: e)
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $noteEvent) { e in
            NoteSheet(event: e,
                      people: notePeople(e),
                      onRename: { label, name in
                          guard let sid = e.sessionId else { return }
                          ListenFlow.shared.renameSpeaker(label, to: name)
                          _ = sid
                      },
                      onQuote: { _ in detailEvent = e },
                      onRegenerate: { noteEvent = nil; detailEvent = e },
                      onDelete: {
                          app.deleteEvent(e.id)
                          noteEvent = nil
                      })
        }
        .alert("提示", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) {
            Button("好") { toast = nil }
        } message: { Text(toast ?? "") }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("记忆")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Spacer()
            Button {
                guard !exportBusy else { return }
                exportBusy = true
                Task {
                    // AppState 是主线程隔离的，跨线程取值要 await
                    let md = await Task.detached(priority: .userInitiated) {
                        await AppState.shared.exportMarkdown(day: day)
                    }.value
                    exportBusy = false
                    if md.count < 40 { toast = "这一天还没有可导出的内容" } else { exported = md; showShare = true }
                }
            } label: {
                Text(exportBusy ? "整理中…" : "导出")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accentSoft)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            segControl
        }
    }

    private var segControl: some View {
        HStack(spacing: 0) {
            segItem("按天", on: byDay) { byDay = true }
            segItem("按类", on: !byDay) { byDay = false }
        }
        .padding(3)
        .background(Theme.card)
        .clipShape(Capsule())
    }

    private func segItem(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Theme.accent : Theme.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(on ? Theme.accentSoft : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var seg: some View {
        EmptyView()
    }

    // MARK: 按天

    private var dayStrip: some View {
        VStack(spacing: 6) {
        HStack(spacing: 6) {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一周")
            Text(weekLabel)
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.dim)
                .frame(maxWidth: .infinity)
            Button {
                weekOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(weekOffset >= 0)
            .accessibilityLabel("下一周")
        }
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { d in
                let on = d == day
                let isToday = d == DayKey.of(Date())
                let future = d > DayKey.of(Date())
                Button { app.refreshDay(d) } label: {
                    VStack(spacing: 5) {
                        Text(weekName(d))
                            .font(.system(size: 11, weight: on ? .semibold : .regular))
                            .foregroundColor(on ? .white : (isToday ? Theme.accent : Theme.dim))
                        Text(dayNum(d))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(on ? .white : (isToday ? Theme.accent : Theme.text))
                        Circle()
                            .fill(isToday ? (on ? Color.white : Theme.accent) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(on ? Theme.accent : (isToday ? Theme.accentSoft : Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .opacity(future && !on ? 0.45 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        }
    }

    private var weekLabel: String {
        if weekOffset == 0 { return "本周" }
        return weekOffset < 0 ? "\(-weekOffset) 周前" : "\(weekOffset) 周后"
    }

    /// 当天已经出过快记的会/培训（回顾卡里列出来，点一下直接看快记）
    private var dayNotes: [MemoryEvent] {
        Array(app.dayEvents.filter { $0.isNote }.reversed())
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sun.haze")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
                Text("当天回顾")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(app.dayReview == nil ? "未生成" : "已生成")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.dim2)
            }
            if let r = app.dayReview, !r.headline.isEmpty {
                Text(r.headline)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("还没生成回顾。整理完事件后点下面生成。")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dim)
            }
            if !dayNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天开了 \(dayNotes.count) 场会")
                        .font(.system(size: Theme.fsCaption, weight: .medium))
                        .foregroundColor(Theme.text2)
                    ForEach(dayNotes) { e in
                        Button { noteEvent = e } label: {
                            HStack(spacing: 6) {
                                Image(systemName: e.scene == "培训" ? "graduationcap" : "person.2.wave.2")
                                    .font(.system(size: 11))
                                    .foregroundColor(e.scene == "培训" ? Theme.purple : Theme.accent)
                                Text(e.title)
                                    .font(.system(size: Theme.fsSmall))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(e.timeRangeText)
                                    .font(.system(size: Theme.fsCaption))
                                    .foregroundColor(Theme.dim)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.sp3)
                .background(Theme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            HStack(spacing: 8) {
                Button {
                    guard !reviewBusy else { return }
                    Task { await genReview() }
                } label: {
                    HStack(spacing: 5) {
                        if reviewBusy { ProgressView().scaleEffect(0.6).tint(.white) }
                        Text(reviewBusy ? "正在写…" : (app.dayReview == nil ? "生成回顾" : "重新生成"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(reviewBusy ? Theme.dim2 : Theme.accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(reviewBusy)
                if app.dayReview != nil {
                    Button { showReview = true } label: {
                        Text("查看完整回顾")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.accent)
                            .tapTarget(10)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    /// 「全部 / 会议 / 培训」：只影响按天那一支的列表
    private var kindBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(["全部", "会议", "培训"].enumerated()), id: \.offset) { idx, name in
                Button { kindFilter = idx } label: {
                    Text(name)
                        .font(.system(size: Theme.fsSmall, weight: kindFilter == idx ? .semibold : .regular))
                        .foregroundColor(kindFilter == idx ? Theme.accent : Theme.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(kindFilter == idx ? Theme.accentSoft : Theme.card))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var filteredEvents: [MemoryEvent] {
        switch kindFilter {
        case 1: return app.dayEvents.filter { $0.scene == "会议" }
        case 2: return app.dayEvents.filter { $0.scene == "培训" }
        default: return app.dayEvents
        }
    }

    /// 速记卡：整张白卡，条间分隔线从文字起画；右上「+ 生成」
    @ViewBuilder
    private var cardsCard: some View {
        let cards = app.dayCards.filter { !$0.isNothing }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("速记卡")
                    .font(.system(size: Theme.fsTitle, weight: .semibold))
                    .foregroundColor(Theme.text)
                if !cards.isEmpty {
                    Text("\(cards.count)")
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.dim)
                }
                Spacer(minLength: 0)
                Button {
                    // afterDigest 类的速记卡：立刻按这一天跑一遍
                    SkillEngine.shared.runAfterDigest(day: day)
                    toast = "正在生成，稍后出现在这里"
                } label: {
                    Text("+ 生成")
                        .font(.system(size: Theme.fsSmall, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .tapTarget(8)
                }
                .buttonStyle(.plain)
            }
            if cards.isEmpty {
                EmptyHint(symbol: "rectangle.stack", title: "这一天还没有速记卡",
                          detail: "速记卡把一天里的事整理成一页，例如项目快讯、今日复盘")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, c in
                        CardView(card: c)
                        if idx < cards.count - 1 {
                            Rectangle().fill(Theme.lineSoft)
                                .frame(height: 0.6)
                                .padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .padding(Theme.sp4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func timelineCard(proxy: ScrollViewProxy) -> some View {
        let items = filteredEvents
        let groups = partGroups(items)
        return VStack(alignment: .leading, spacing: Theme.sp3) {
            HStack(spacing: 8) {
                Text("时间线 · \(items.count) 件事")
                    .font(.system(size: Theme.fsTitle, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 0)
            }
            if items.isEmpty {
                EmptyHint(symbol: "sparkles", title: "这一天还没有整理出内容",
                          detail: kindFilter == 0 ? "先录一段，整理后会自动生成时间线" : "换一个筛选看看，或先录一场")
            } else {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.title) { g in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(g.title) · \(g.items.count) 件")
                                    .font(.system(size: Theme.fsCaption, weight: .medium))
                                    .foregroundColor(Theme.dim)
                                    .padding(.leading, 4)
                                VStack(spacing: 0) {
                                    ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, e in
                                        Group {
                                            if e.isNote {
                                                NoteTimelineLine(event: e, itemCount: noteItemCount(e)) {
                                                    noteEvent = e
                                                }
                                            } else {
                                                TimelineLine(event: e,
                                                             onStar: { app.starEvent(e.id, starred: !e.starred) },
                                                             onTap: { detailEvent = e })
                                            }
                                        }
                                        .id("tl-\(e.id)")
                                        .railTrack(e.id)
                                        if idx < g.items.count - 1 {
                                            Rectangle().fill(Theme.lineSoft)
                                                .frame(height: 0.6)
                                                .padding(.leading, 58)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, items.count > 8 ? 36 : 0)
                    if items.count > 8 {
                        HourRail(slots: railSlots(items),
                                 autoHeight: RailRules.railHeight(slotCount: railSlots(items).count,
                                                                  entryCount: items.count,
                                                                  available: 320),
                                 activeKey: activeRailKey) { key in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("tl-\(key)", anchor: .top)
                            }
                        }
                        .frame(width: 30)
                        .padding(.top, 26)
                    }
                }
            }
        }
    }

    private struct PartGroup: Identifiable {
        let title: String
        let items: [MemoryEvent]
        var id: String { title }
    }

    private func partGroups(_ list: [MemoryEvent]) -> [PartGroup] {
        var order: [String] = []
        var map: [String: [MemoryEvent]] = [:]
        for e in list {
            let p = partOf(e.startAt)
            if map[p] == nil { order.append(p) }
            map[p, default: []].append(e)
        }
        return order.map { PartGroup(title: $0, items: (map[$0] ?? []).sorted { $0.startAt < $1.startAt }) }
    }

    private func partOf(_ date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        if h < 6 { return "凌晨" }
        if h < 12 { return "上午" }
        if h < 18 { return "下午" }
        return "晚上"
    }

    private func railSlots(_ list: [MemoryEvent]) -> [RailSlot] {
        RailRules.slots(list.map { (key: $0.id, hour: Calendar.current.component(.hour, from: $0.startAt)) })
    }

    private func noteItemCount(_ e: MemoryEvent) -> Int {
        app.todayItems.filter { $0.eventId == e.id }.count + app.dayItems.filter { $0.eventId == e.id }.count
    }

    private func notePeople(_ e: MemoryEvent) -> [(label: String, name: String, seconds: Double)] {
        guard let sid = e.sessionId else { return [] }
        let session = Store.shared.session(id: sid)
        let rows = Store.shared.utterances(sessionId: sid)
        var sums: [String: Double] = [:]
        for u in rows { sums[u.speaker, default: 0] += u.duration }
        return sums.map { (label: $0.key, name: session?.name($0.key) ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var catChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cats, id: \.self) { c in
                    Chip(text: c, selected: cat == c) { cat = c }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var catList: some View {
        if cat == "重点" {
            VStack(alignment: .leading, spacing: 12) {
                Text("在时间线上把一件事往左滑，就能标成重点。标过的事会集中放在这里，问问能查，每日和每周回顾也会跟进。")
                    .font(.system(size: 11.5)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if app.starredList.isEmpty {
                    EmptyHint(symbol: "star", title: "还没有标过重点", detail: "在时间线里长按一条可以标重点")
                } else {
                    ForEach(app.starredList) { e in
                        EventRow(event: e,
                                 onStar: { app.starEvent(e.id, starred: false) },
                                 onTap: { detailEvent = e })
                    }
                }
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        } else if cat == "寻物" {
            thingsList
        } else {
            let list = catItems
            VStack(alignment: .leading, spacing: Theme.sp3) {
                if catLoading && list.isEmpty {
                    LoadingHint(rows: 3, text: "正在读取…")
                } else if list.isEmpty {
                    EmptyHint(symbol: "tray", title: "还没有这一类的内容", detail: "整理出来的提取项会按类别归到这里")
                } else {
                    ForEach(list) { it in
                        ItemRow(item: it) { st in
                            app.setItemStatus(it.id, status: st)
                            // 勾完这一条状态变了，重新读一遍分类列表，图标才跟得上
                            Task { await loadCat() }
                        }
                    }
                }
            }
            .padding(Theme.sp3)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
    }

    private func loadCat() async {
        guard !byDay, cat != "重点", cat != "寻物" else { catLoading = false; return }
        let key = cat
        if loadedCat != key {
            catItems = []
            loadedCat = key
        }
        if catItems.isEmpty { catLoading = true }
        let list = await Task.detached(priority: .userInitiated) {
            Store.shared.items(day: nil, status: nil, category: key, limit: 200)
        }.value
        if cat == key { catItems = list; catLoading = false }
    }

    private var thingsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.things.isEmpty {
                EmptyHint(symbol: "shippingbox", title: "还没有记录过东西放哪了", detail: "说一句「钥匙放抽屉了」就会记下来")
            } else {
                ForEach(app.things) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(t.name)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundColor(Theme.text)
                            if t.holder != nil {
                                Text("借出")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.warn)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Theme.warn.opacity(0.12)).clipShape(Capsule())
                            }
                            Spacer()
                        }
                        Text(thingLine(t))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.dim)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private func thingLine(_ t: Thing) -> String {
        if let h = t.holder, !h.isEmpty { return "借给 \(h)" }
        if let p = t.place, !p.isEmpty { return "在 \(p)" }
        return "位置未知"
    }

    // MARK: 工具

    /// 本周一到周日，7 格固定顺序
    private var weekDays: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2          // 周一为一周开始
        cal.locale = Locale(identifier: "zh_CN")
        let today = Date()
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeek) ?? thisWeek
        return (0..<7).compactMap { i in
            cal.date(byAdding: .day, value: i, to: start).map { DayKey.of($0) }
        }
    }

    private func dayNum(_ d: String) -> String {
        String(d.suffix(2)).replacingOccurrences(of: "0", with: "", options: .anchored)
    }

    /// 周几，固定「周一…周日」写法
    private func weekName(_ d: String) -> String {
        guard let date = DayKey.date(from: d) else { return "" }
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let w = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return names[(w - 1 + 7) % 7]
    }

    private func genReview() async {
        reviewBusy = true
        defer { reviewBusy = false }
        do {
            _ = try await ReviewEngine.shared.generateDaily(day: day)
            app.refreshDay(day)
        } catch {
            toast = error.localizedDescription
        }
    }
}

// MARK: - 技能卡

struct CardView: View {
    let card: SkillCard

    private var title: String {
        if let t = card.fields["title"], !t.isEmpty { return t }
        let s = card.fields["summary"] ?? ""
        let c = NoteRules.conclusion(s)
        return c.isEmpty ? card.skillName : c
    }

    private var summary: String {
        let s = card.fields["summary"] ?? ""
        return s == title ? "" : s
    }

    private var points: [String] {
        (card.fields["points"] ?? "")
            .split(whereSeparator: { $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var timeText: String {
        guard let st = card.startAt else { return "" }
        let a = Fmt.hm.string(from: st)
        guard let en = card.endAt else { return a }
        return a + "–" + Fmt.hm.string(from: en)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.bgDeep)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.accent)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(card.skillName)
                        .font(.system(size: Theme.fsCaption, weight: .medium))
                        .foregroundColor(Theme.dim)
                    if !timeText.isEmpty {
                        Text("· " + timeText)
                            .font(.system(size: Theme.fsCaption))
                            .foregroundColor(Theme.dim2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.dim2)
                }
                Text(title)
                    .font(.system(size: Theme.fsBody, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(summary.isEmpty ? points.prefix(2).joined(separator: "；") : summary)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.text2)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 回顾全文

struct ReviewSheet: View {
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var record: ReviewRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r = record {
                    Text(r.headline)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(r.text)
                        .font(.system(size: 13.5))
                        .foregroundColor(Theme.text2)
                        .lineSpacing(4)
                } else {
                    EmptyHint(symbol: "doc.text.magnifyingglass", title: "还没有生成回顾", detail: "到设定时间后会自动写一份回顾")
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("回顾 · \(day)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear {
            record = Store.shared.reviews(limit: 60).first { $0.day == day }
        }
    }
}

// MARK: - 原话

struct RawLinesView: View {
    let day: String
    @State private var rows: [Segment] = []
    @State private var selected: Segment?
    @State private var pendingDelete: Segment?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    EmptyHint(symbol: "waveform", title: "这一天还没有转写好的原话", detail: "录音转写完成后会出现在这里")
                }
                ForEach(rows) { s in
                    SegmentRow(seg: s,
                               starred: s.starred ?? false,
                               canAssign: true,
                               canDelete: true,
                               onPlay: { SegmentPlayer.shared.toggle(segment: s) },
                               onStar: {
                                   Store.shared.setStar(id: s.id, starred: !Store.shared.isStarred(id: s.id))
                                   // 以前只写库不刷新，星标看着没反应
                                   Task { await reload() }
                               },
                               onAssign: { selected = s },
                               onDelete: { pendingDelete = s })
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 8)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .tabBarClearance()
        .navigationTitle("原话 · \(rows.count) 段")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
        }
        .task { await reload() }
        .sheet(item: $selected) { s in
            SpeakerAssignSheet(segment: s) {
                Task { await reload() }
            }
        }
        .alert("删除这段原话？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                guard let s = pendingDelete else { return }
                pendingDelete = nil
                if SegmentPlayer.shared.isPlaying(s.id) { SegmentPlayer.shared.stop() }
                Store.shared.deleteSegment(id: s.id, removeFile: true)
                NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
                Task { await reload() }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("录音文件和转写都会删掉，删了找不回来。")
        }
    }

    private func reload() async {
        let key = day
        let list = await Task.detached(priority: .userInitiated) {
            Store.shared.segments(day: key, limit: 600)
        }.value
        rows = list
    }
}

// MARK: - 指定说话人

struct SpeakerAssignSheet: View {
    let segment: Segment
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var persons: [Person] = []
    @State private var newName = ""
    @State private var assigning = false

    var body: some View {
        NavigationStack {
            List {
                Section("这段是谁说的") {
                    ForEach(persons) { p in
                        Button {
                            assign(p)
                        } label: {
                            HStack(spacing: 8) {
                                SpeakerDot(name: p.name, size: 22)
                                Text(p.name)
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                Text("\(p.sampleCount) 段样本")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.dim2)
                            }
                        }
                    }
                }
                Section("新建一个人") {
                    HStack {
                        TextField("名字或称呼，例如：老王", text: $newName)
                        Button("添加") {
                            let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !n.isEmpty else { return }
                            AppState.shared.addPerson(name: n)
                            persons = Store.shared.persons()
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("这是谁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("取消") { dismiss() } }
            }
            .onAppear { persons = Store.shared.persons() }
        }
    }

    private func assign(_ p: Person) {
        guard !assigning else { return }
        assigning = true
        Store.shared.setSpeaker(id: segment.id, speaker: p.name)
        let url = Store.audioDir.appendingPathComponent(segment.fileName)
        let personId = p.id
        let segmentId = segment.id
        // 声纹要解码整段音频，放在后台算，算完再存样本
        Task {
            let vector = await Task.detached(priority: .userInitiated) { Voiceprint.vector(from: url) }.value
            if let vector {
                Store.shared.insertVoiceSample(VoiceSample(
                    id: UUID().uuidString,
                    personId: personId,
                    segmentId: segmentId,
                    vector: vector,
                    createdAt: Date()
                ))
            }
            AppState.shared.refresh()
            onDone()
            dismiss()
        }
    }
}
