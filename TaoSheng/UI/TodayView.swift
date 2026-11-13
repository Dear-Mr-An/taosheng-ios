import SwiftUI

struct TodayView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var digest = DigestEngine.shared
    @ObservedObject private var settings = Settings.shared
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance") private var appearance = "system"

    @State private var heroCollapsed = false
    @State private var toast: String?
    @State private var showTimeline = false
    @State private var detailEvent: MemoryEvent?
    /// 上一次回顾生成时间：以前写在 body 里的计算属性里查库，每次重绘都要跑一次 SQL
    @State private var lastReviewAt: Date?

    private var today: String { DayKey.of(Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                heroCard
                rhythmCard
                timelineCard
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { await loadLastReview() }
        .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in
            Task { await loadLastReview() }
        }
        .sheet(item: $detailEvent) { e in
            EventDetailView(event: e)
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("提示", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) {
            Button("好") { toast = nil }
        } message: {
            Text(toast ?? "")
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今天 · \(weekdayText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.dim)
                Text(dateText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
            }
            Spacer()
            Button {
                appearance = scheme == .dark ? "light" : "dark"
            } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(capture.isRunning ? Color.white : Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(capture.isRunning ? "正在聆听" : "已暂停")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { heroCollapsed.toggle() }
                } label: {
                    Text(heroCollapsed ? "展开" : "收起")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            if !heroCollapsed {
                modeRow
                    .padding(.top, 12)

                listenButton
                    .padding(.top, 10)

                Divider()
                    .overlay(Color.white.opacity(0.25))
                    .padding(.vertical, 12)

                HStack(spacing: 0) {
                    heroStat(app.todayTalkText, "录到人声")
                    heroDivider
                    heroStat("\(app.eventCount)", "件事")
                    heroDivider
                    heroStat("\(app.counts.pending)", "待确认")
                }

                Text(heroNote)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.78))
                    .lineSpacing(2)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    Button {
                        Task { await runDigest() }
                    } label: {
                        HStack(spacing: 5) {
                            if digest.running {
                                ProgressView().scaleEffect(0.7).tint(.white)
                            } else {
                                Image(systemName: "sparkles").font(.system(size: 12))
                            }
                            Text(digest.running ? "正在整理…" : "现在整理")
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(digest.running)

                    Spacer()

                    Text(digestAgo)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Theme.accent, Theme.accentHi],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(CaptureMode.allCases) { m in
                    Button {
                        switchMode(m)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: m.symbol)
                                .font(.system(size: 11, weight: .medium))
                            Text(m.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(settings.captureMode == m ? Theme.accent : Color.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(settings.captureMode == m ? Color.white : Color.white.opacity(0.18))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(settings.captureMode.hint)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listenButton: some View {
        Button {
            toggleCapture()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: capture.isRunning ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(capture.isRunning ? "停止聆听" : "开始聆听")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(capture.isRunning ? Color.white : Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(capture.isRunning ? Color.white.opacity(0.16) : Color.white))
            .overlay(Capsule().stroke(Color.white.opacity(capture.isRunning ? 0.45 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func switchMode(_ m: CaptureMode) {
        guard settings.captureMode != m else { return }
        let wasRunning = capture.isRunning
        settings.captureMode = m
        guard wasRunning else { return }
        capture.stop()
        // 立刻重启时 audio session 还没释放，start() 会静默失败；
        // 等 0.4 秒再开；仍失败时隔 1 秒再试一次，避免切完模式就再也不录了。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !capture.isRunning { capture.start() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !capture.isRunning, settings.captureMode == m { capture.start() }
            }
        }
    }

    private var heroNote: String {
        if let y = capture.yieldReason, !y.isEmpty { return y }
        if let e = capture.lastError, !e.isEmpty { return e }
        if let e = digest.lastError, !e.isEmpty { return e }
        if settings.effectiveLLM.key.isEmpty {
            return "填好大模型密钥后，转写出的原话会自动整理成一件件事"
        }
        if app.todayEvents.isEmpty {
            return "录到人声 → 转写成原话 → 整理成一件件事"
        }
        return "模型已就绪 · \(settings.llmModel)"
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroDivider: some View {
        Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 30)
    }

    // MARK: 今日节律

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日节律")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.text)

            HStack(spacing: 0) {
                rhythmCell(durationText(app.mySeconds), "我说了", Theme.accent)
                rhythmCell(durationText(app.otherSeconds), "别人说了", Theme.blue)
                rhythmCell("\(app.peopleCount)", "人聊过", Theme.purple)
                rhythmCell("\(app.meetingCount)", "次开会", Theme.ok)
            }

            hourBars
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    /// 一天 24 小时里每个小时说了多少，柱高按当天最忙的一小时归一
    private var hourBars: some View {
        let totals = hourlyTotals()
        let peak = max(totals.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<24, id: \.self) { i in
                let h = totals[i] / peak
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(totals[i] > 0 ? Theme.accent.opacity(0.30 + 0.55 * h) : Theme.line)
                    .frame(height: max(2.5, 34 * h))
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 34, alignment: .bottom)
    }

    private func hourlyTotals() -> [Double] {
        var out = [Double](repeating: 0, count: 24)
        let cal = Calendar.current
        for s in app.todaySegments {
            let h = cal.component(.hour, from: s.startedAt)
            if h >= 0 && h < 24 { out[h] += max(1, s.duration) }
        }
        return out
    }

    private func rhythmCell(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            Text(v)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(c)
            Text(l)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 时间线

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间线 · \(app.todayEvents.count) 件事")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if app.todayEvents.count > 5 {
                    Button { showTimeline = true } label: {
                        Text("全部 >").font(.system(size: 12.5)).foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if app.todayEvents.isEmpty {
                EmptyHint(text: "这一天还没有整理出事件")
            } else {
                let shown = Array(app.todayEvents.prefix(6))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, e in
                        TimelineLine(event: e,
                                     onStar: { app.starEvent(e.id, starred: !e.starred) },
                                     onTap: { detailEvent = e })
                        if idx < shown.count - 1 {
                            Rectangle().fill(Theme.line)
                                .frame(height: 0.6)
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 2)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
        }
        .sheet(isPresented: $showTimeline) {
            NavigationStack { TimelineFullView(day: today) }
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 动作

    private func toggleCapture() {
        if capture.isRunning {
            capture.stop()
            UserDefaults.standard.set(false, forKey: "captureWanted")
        } else {
            capture.start()
            UserDefaults.standard.set(true, forKey: "captureWanted")
        }
    }

    private func runDigest() async {
        do {
            let r = try await digest.digest(day: today)
            if r.events == 0 && r.items == 0 { toast = "暂时没有新的原话可以整理" }
        } catch {
            toast = error.localizedDescription
        }
    }

    private var digestAgo: String {
        let t = digest.lastRunAt ?? lastReviewAt
        guard let t = t else { return "还没整理过" }
        let m = Int(Date().timeIntervalSince(t) / 60)
        if m < 1 { return "刚刚整理过" }
        if m < 60 { return "\(m) 分钟前整理过" }
        return "\(m / 60) 小时前整理过"
    }

    private func loadLastReview() async {
        let t = await Task.detached(priority: .utility) { () -> Date? in
            Store.shared.reviews(limit: 1).first?.createdAt
        }.value
        if lastReviewAt != t { lastReviewAt = t }
    }

    private var weekdayText: String { Fmt.weekday.string(from: Date()) }

    private var dateText: String { Fmt.monthDay.string(from: Date()) }

    private func durationText(_ s: Double) -> String {
        let v = Int(s.rounded())
        if v < 60 { return "\(v)秒" }
        if v < 3600 { return "\(v / 60)分" }
        return "\(v / 3600)小时\(v % 3600 / 60)分"
    }
}

// MARK: - 全天时间线

struct TimelineFullView: View {
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var scope = 0
    @State private var onlyMedia = false
    @State private var earlyFirst = true
    @State private var detailEvent: MemoryEvent?
    @State private var reloadTick = 0
    /// 800 行查询从 body 里搬出来：以前每次重绘都同步查库，滚动时明显掉帧
    @State private var loaded: [MemoryEvent] = []

    private var dayList: [String] {
        (0..<3).map { DayKey.of(Date().addingTimeInterval(-Double($0) * 86_400)) }
    }

    private var currentDay: String {
        dayList.indices.contains(scope) ? dayList[scope] : day
    }

    private var raw: [MemoryEvent] { loaded }

    private func loadTimeline() async {
        let day = currentDay
        let list = await Task.detached(priority: .userInitiated) {
            Store.shared.events(day: day, limit: 800)
        }.value
        if day == currentDay { loaded = list }
    }

    private var events: [MemoryEvent] {
        var list = raw.sorted { $0.startAt < $1.startAt }
        if !earlyFirst { list.reverse() }
        return onlyMedia ? list.filter { $0.scene == "媒体" } : list
    }

    private var mediaCount: Int { raw.filter { $0.scene == "媒体" }.count }

    private var groups: [(String, [MemoryEvent])] {
        var out: [(String, [MemoryEvent])] = []
        for e in events {
            let t = partTitle(e.startAt)
            if let i = out.firstIndex(where: { $0.0 == t }) {
                out[i].1.append(e)
            } else {
                out.append((t, [e]))
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("时间线 · \(events.count) 件事")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.dim)
                    Spacer(minLength: 8)
                    segControl
                }

                HStack(spacing: 8) {
                    chip("全部", active: !onlyMedia) { onlyMedia = false }
                    chip("● 媒体 \(mediaCount)", active: onlyMedia) { onlyMedia = true }
                    Spacer(minLength: 0)
                    Button { earlyFirst.toggle() } label: {
                        Text(earlyFirst ? "早的在上" : "晚的在上")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }

                if events.isEmpty {
                    EmptyHint(text: "这一天还没有整理出事件")
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(g.0) · \(g.1.count) 件")
                                .font(.system(size: 12.5))
                                .foregroundColor(Theme.dim2)
                                .padding(.top, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(g.1.enumerated()), id: \.element.id) { idx, e in
                                    TimelineLine(event: e, onStar: {
                                        Store.shared.setEventStar(id: e.id, starred: !e.starred)
                                        reloadTick &+= 1
                                    }, onTap: { detailEvent = e })
                                    if idx < g.1.count - 1 {
                                        Rectangle().fill(Theme.line)
                                            .frame(height: 0.6)
                                            .padding(.leading, 58)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .task(id: "\(currentDay)|\(reloadTick)") { await loadTimeline() }
        .navigationTitle("时间线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(item: $detailEvent) { e in
            EventDetailView(event: e)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var segControl: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Button { scope = i } label: {
                    Text(i == 0 ? "今天" : (i == 1 ? "昨天" : "前天"))
                        .font(.system(size: 12.5, weight: scope == i ? .semibold : .regular))
                        .foregroundColor(scope == i ? Theme.text : Theme.dim)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(scope == i ? Theme.card : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.bgDeep)
        .clipShape(Capsule())
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12.5, weight: active ? .medium : .regular))
                .foregroundColor(active ? .white : Theme.text2)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(active ? Theme.accent : Theme.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func partTitle(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        if h < 6 { return "凌晨" }
        if h < 12 { return "上午" }
        if h < 18 { return "下午" }
        return "晚上"
    }
}

/// 时间线的一行：左侧橙色时刻，右侧标题 + 两行摘要
struct TimelineLine: View {
    let event: MemoryEvent
    var onStar: () -> Void = {}
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text(event.timeText)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.accent)
                    .frame(width: 46, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !event.summary.isEmpty {
                        Text(event.summary)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.dim)
                            .lineSpacing(3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                if event.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.warn)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onStar() } label: {
                Label(event.starred ? "取消重点" : "标为重点", systemImage: "star")
            }
        }
    }
}
