import SwiftUI

struct MemoryView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings

    @State private var mode = 0            // 0 = 事件，1 = 原话
    @State private var onlyStar = false
    @State private var showReview = false
    @State private var exportItems: [Any] = []
    @State private var showExport = false
    @State private var showLost = false
    @State private var busy = false
    @State private var toast: String?
    @State private var assignSeg: Segment? = nil

    private var days: [String] {
        let cal = Calendar.current
        return (0..<14).compactMap { i in
            cal.date(byAdding: .day, value: -i, to: Date()).map { DayKey.of($0) }
        }.reversed()
    }

    private var isToday: Bool { app.selectedDay == DayKey.of(Date()) }

    private var items: [DigestItem] { isToday ? app.todayItems : app.dayItems }
    private var segs: [Segment] { isToday ? app.todaySegments : app.daySegments }

    private var shownSegs: [Segment] {
        guard onlyStar else { return segs }
        let starred = Set(Store.shared.starredSegments(limit: 500).map { $0.id })
        return segs.filter { starred.contains($0.id) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                dayStrip
                reviewCard
                contentCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showReview) {
            ReviewSheet(day: app.selectedDay, record: app.dayReview)
        }
        .sheet(isPresented: $showLost) {
            LostFinderView()
        }
        .sheet(isPresented: $showExport) {
            ShareSheet(items: exportItems)
        }
        .sheet(item: $assignSeg) { seg in
            SpeakerAssignSheet(segment: seg, names: app.persons.map { $0.name }) { name in
                Store.shared.setSpeaker(id: seg.id, speaker: name)
                let url = Store.audioDir.appendingPathComponent(seg.fileName)
                if let v = Voiceprint.vector(from: url),
                   let p = app.persons.first(where: { $0.name == name }) {
                    Store.shared.insertVoiceSample(VoiceSample(id: shortID(),
                                                             personId: p.id,
                                                             segmentId: seg.id,
                                                             vector: v,
                                                             createdAt: Date()))
                }
                app.refreshDay(app.selectedDay)
                app.refresh()
                flash("已记下「\(name)」的声音")
            }
        }
        .overlay(alignment: .top) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.text.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if app.selectedDay.isEmpty { app.selectedDay = DayKey.of(Date()) }
            app.refreshDay(app.selectedDay)
        }
    }

    // MARK: - 头部
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("记忆")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(DayKey.display(app.selectedDay))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            HStack(spacing: 8) {
                iconButton("square.and.arrow.up") { export() }
                iconButton("magnifyingglass") { showLost = true }
                iconButton("calendar") {
                    app.selectedDay = DayKey.of(Date())
                    app.refreshDay(app.selectedDay)
                }
            }
        }
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: 34, height: 34)
                .background(Theme.card)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 日期条
    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { d in
                        let on = d == app.selectedDay
                        Button {
                            app.selectedDay = d
                            app.refreshDay(d)
                        } label: {
                            VStack(spacing: 3) {
                                Text(dayNumber(d))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text(weekShort(d))
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(on ? Color.white : Theme.text2)
                            .frame(width: 42, height: 50)
                            .background(on ? Theme.accent : Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(d)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { proxy.scrollTo(app.selectedDay, anchor: .trailing) }
        }
    }

    private func dayNumber(_ key: String) -> String {
        guard let d = DayKey.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: d)
    }

    private func weekShort(_ key: String) -> String {
        guard let d = DayKey.date(from: key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    // MARK: - 当天回顾
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(app.dayReview == nil ? "当天回顾" : "当天回顾 · \(reviewTime)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if busy { ProgressView().scaleEffect(0.6).tint(.white) }
            }

            Text(app.dayReview?.headline ?? "还没有这一天的回顾。点「生成回顾」，它会把这一天讲成一段话。")
                .font(.system(size: app.dayReview == nil ? 13 : 15, weight: app.dayReview == nil ? .regular : .semibold))
                .foregroundStyle(.white.opacity(app.dayReview == nil ? 0.85 : 1))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if app.dayReview != nil {
                    Button { showReview = true } label: {
                        Text("查看完整回顾")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button { generateReview() } label: {
                    Text(app.dayReview == nil ? "生成回顾" : "重新生成")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Spacer()
            }
        }
        .padding(15)
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var reviewTime: String {
        guard let r = app.dayReview else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: r.createdAt)
    }

    // MARK: - 事件 / 原话
    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Chip(text: "事件 · \(items.count)", selected: mode == 0) { mode = 0 }
                Chip(text: "原话 · \(segs.count)", selected: mode == 1) { mode = 1 }
                if mode == 1 {
                    Chip(text: "★ 重点", selected: onlyStar) { onlyStar.toggle() }
                }
                Spacer()
            }

            if mode == 0 {
                if items.isEmpty {
                    EmptyHint(text: "这一天还没有事件。").padding(.vertical, 20)
                } else {
                    ForEach(items) { item in
                        EventRow(item: item) { app.toggleItem(item.id) }
                    }
                }
            } else {
                if shownSegs.isEmpty {
                    EmptyHint(text: onlyStar ? "这一天还没有标重点的原话。长按一段原话可以标。" : "这一天没有录音。").padding(.vertical, 20)
                } else {
                    ForEach(shownSegs) { seg in
                        SegmentRow(seg: seg,
                                   onPlay: { SegmentPlayer.shared.toggle(segment: seg) },
                                   onStar: {
                                       Store.shared.setStar(id: seg.id, starred: !Store.shared.isStarred(id: seg.id))
                                       app.refreshDay(app.selectedDay)
                                   },
                                   onAssign: { assignSpeaker(seg) },
                                   onDelete: {
                                       Store.shared.deleteSegment(id: seg.id, removeFile: true)
                                       app.refreshDay(app.selectedDay)
                                   })
                        Divider().overlay(Theme.lineSoft)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - 动作
    private func generateReview() {
        guard !busy else { return }
        busy = true
        let day = app.selectedDay
        Task {
            do {
                _ = try await ReviewEngine.shared.generateDaily(day: day)
                await MainActor.run {
                    app.refreshDay(day)
                    app.refresh()
                    busy = false
                    flash("回顾生成好了")
                }
            } catch {
                await MainActor.run {
                    busy = false
                    flash("生成失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func assignSpeaker(_ seg: Segment) {
        guard !app.persons.isEmpty else {
            flash("先去「设置 → 声纹与人物」添加人物")
            return
        }
        assignSeg = seg
    }

    private func export() {
        let md = app.exportMarkdown(day: app.selectedDay)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("涛声-\(app.selectedDay).md")
        if (try? md.write(to: url, atomically: true, encoding: .utf8)) != nil {
            exportItems = [url]
            showExport = true
        }
    }

    private func flash(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == s { toast = nil }
        }
    }
}

// MARK: - 完整回顾
struct ReviewSheet: View {
    let day: String
    let record: ReviewRecord?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let r = record {
                        Text(r.headline)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text(r.text)
                            .font(.system(size: 14.5))
                            .foregroundStyle(Theme.text2)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        EmptyHint(text: "还没有回顾。")
                    }
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(DayKey.display(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 指定说话人
struct SpeakerAssignSheet: View {
    let segment: Segment
    let names: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(names, id: \.self) { n in
                    Button {
                        onPick(n)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            SpeakerDot(name: n, size: 8)
                            Text(n).foregroundStyle(Theme.text)
                            Spacer()
                            if segment.speaker == n {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("这是谁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 寻物
struct LostFinderView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var results: [Segment] = []
    @State private var asked = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("钥匙放哪了？充电宝借给谁了？", text: $q)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit { search() }
                    Button("找") { search() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !asked {
                            EmptyHint(text: "说过的「放在哪、带走、借给谁、还回来」，都会记在这里。")
                        } else if results.isEmpty {
                            EmptyHint(text: "没找到相关记录。")
                        } else {
                            ForEach(results) { s in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(DayKey.display(s.day))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.dim)
                                        Text(s.timeText)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.dim2)
                                    }
                                    Text(s.transcript)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.top, 10)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("寻物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func search() {
        let key = q.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        asked = true
        results = Store.shared.searchForAsk(key, limit: 30)
    }
}

// MARK: - 便捷弹出

