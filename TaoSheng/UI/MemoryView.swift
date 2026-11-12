import SwiftUI

struct MemoryView: View {
    @ObservedObject private var app = AppState.shared
    @State private var byDay = true
    @State private var showShare = false
    @State private var showReview = false
    @State private var toast: String?
    @State private var cat = "重点"

    private let cats = ["重点", "寻物", "灵感", "关键信息", "决定"]

    private var day: String { app.selectedDay }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if byDay {
                    dayStrip
                    reviewCard
                    eventList
                } else {
                    catChips
                    catList
                }
                Color.clear.frame(height: 78)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [app.exportMarkdown(day: day)])
        }
        .sheet(isPresented: $showReview) {
            NavigationStack { ReviewSheet(day: day) }
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
                let md = app.exportMarkdown(day: day)
                if md.count < 40 { toast = "这一天还没有可导出的内容" } else { showShare = true }
            } label: {
                Text("导出")
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(future && !on ? 0.45 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
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
            HStack(spacing: 8) {
                Button {
                    Task { await genReview() }
                } label: {
                    Text(app.dayReview == nil ? "生成回顾" : "重新生成")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if app.dayReview != nil {
                    Button { showReview = true } label: {
                        Text("查看完整回顾")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.accent)
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

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间线 · \(app.dayEvents.count) 件事")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            if app.dayEvents.isEmpty {
                EmptyHint(text: "这一天还没有整理出内容")
            } else {
                ForEach(app.dayEvents) { e in
                    EventRow(event: e, onStar: {
                        app.starEvent(e.id, starred: !e.starred)
                    })
                }
            }
            if !app.dayCards.isEmpty {
                ForEach(app.dayCards) { c in
                    if !c.isNothing { CardView(card: c) }
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    // MARK: 按类

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
                    EmptyHint(text: "还没有标过重点")
                } else {
                    ForEach(app.starredList) { e in
                        EventRow(event: e, onStar: { app.starEvent(e.id, starred: false) })
                    }
                }
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        } else if cat == "寻物" {
            thingsList
        } else {
            let list = Store.shared.items(day: nil, status: nil, category: cat, limit: 200)
            VStack(alignment: .leading, spacing: 10) {
                if list.isEmpty {
                    EmptyHint(text: "还没有这一类的内容")
                } else {
                    ForEach(list) { it in
                        ItemRow(item: it) { st in app.setItemStatus(it.id, status: st) }
                    }
                }
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
    }

    private var thingsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.things.isEmpty {
                EmptyHint(text: "还没有记录过东西放哪了")
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
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 12)).foregroundColor(Theme.accent)
                Text(card.skillName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if let s = card.startAt {
                    Text(DigestEngine.hms(s))
                        .font(.system(size: 11)).foregroundColor(Theme.dim2)
                }
            }
            ForEach(Array(card.fields.keys.sorted()), id: \.self) { k in
                let v = card.fields[k] ?? ""
                if !v.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k)
                            .font(.system(size: 10.5)).foregroundColor(Theme.dim2)
                        Text(v)
                            .font(.system(size: 12.5)).foregroundColor(Theme.text2)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    EmptyHint(text: "还没有生成回顾")
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    EmptyHint(text: "这一天还没有转写好的原话")
                }
                ForEach(rows) { s in
                    SegmentRow(seg: s,
                               onPlay: { SegmentPlayer.shared.toggle(segment: s) },
                               onStar: { Store.shared.setStar(id: s.id, starred: !Store.shared.isStarred(id: s.id)) },
                               onAssign: { selected = s },
                               onDelete: {
                                   Store.shared.deleteSegment(id: s.id, removeFile: true)
                                   rows = Store.shared.segments(day: day, limit: 600)
                               })
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 40)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("原话 · \(rows.count) 段")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
        }
        .onAppear { rows = Store.shared.segments(day: day, limit: 600) }
        .sheet(item: $selected) { s in
            SpeakerAssignSheet(segment: s) {
                rows = Store.shared.segments(day: day, limit: 600)
            }
        }
    }
}

// MARK: - 寻物

struct ThingsView: View {
    @State private var things: [Thing] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if things.isEmpty {
                Text("还没有记录过东西放哪了")
                    .foregroundColor(Theme.dim)
            }
            ForEach(things) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.name).font(.system(size: 15, weight: .medium))
                    Text(sub(t)).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("寻物")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
        }
        .onAppear { things = Store.shared.things(limit: 200) }
    }

    private func sub(_ t: Thing) -> String {
        if let h = t.holder, !h.isEmpty { return "借给 \(h)" }
        if let p = t.place, !p.isEmpty { return "在 \(p)" }
        return "位置未知"
    }
}

// MARK: - 指定说话人

struct SpeakerAssignSheet: View {
    let segment: Segment
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var persons: [Person] = []
    @State private var newName = ""

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
        Store.shared.setSpeaker(id: segment.id, speaker: p.name)
        let url = Store.audioDir.appendingPathComponent(segment.fileName)
        if let v = Voiceprint.vector(from: url) {
            Store.shared.insertVoiceSample(VoiceSample(
                id: UUID().uuidString,
                personId: p.id,
                segmentId: segment.id,
                vector: v,
                createdAt: Date()
            ))
        }
        AppState.shared.refresh()
        onDone()
        dismiss()
    }
}
