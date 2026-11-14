import SwiftUI

struct TodayView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var digest = DigestEngine.shared
    @ObservedObject private var settings = Settings.shared
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance") private var appearance = "auto"

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
        .tabBarClearance()
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
                    .font(.system(size: Theme.fsHero, weight: .bold, design: .rounded))
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
                        .fill(flow.isRecording ? Color.white : Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(heroStatus)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { heroCollapsed.toggle() }
                } label: {
                    Text(heroCollapsed ? "展开" : "收起")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                        .tapTarget(10)
                }
                .buttonStyle(.plain)
            }

            if !heroCollapsed {
                modeRow
                    .padding(.top, 12)

                listenButton
                    .padding(.top, 10)

                if flow.isRecording || !liveLines.isEmpty {
                    liveTranscript
                        .padding(.top, 10)
                }

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
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    if flow.canRetry {
                        Button {
                            flow.retry()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 12))
                                Text("重试").font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.26))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
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
                    }

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

    /// 英雄卡顶上那行字：录音/收尾/整理/失败各有各的说法，别一律写「已暂停」。
    private var heroStatus: String {
        if flow.working || flow.isRecording { return flow.statusText }
        if let s = flow.current, s.state == .done { return "已整理" }
        return flow.statusText
    }

    /// 录音中的实时转写：最近 6 行，最新在最下面。分人留到结束再做，
    /// 因为每段是独立送识别的，跨段编号对不上，硬标会标错人。
    private var liveLines: [(String, String, Bool)] {
        guard let sid = flow.current?.id, flow.isRecording else { return [] }
        let rows = app.todaySegments.filter { $0.sessionId == sid }
        let recent = rows.prefix(6)
        return recent.map { seg in
            (Fmt.hm.string(from: seg.startedAt), seg.transcript, seg.state == .transcribed)
        }.reversed()
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 5) {
            if liveLines.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).tint(.white)
                    Text("转写中…")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
            } else {
                ForEach(Array(liveLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.0)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.top, 1)
                        Text(line.2 ? line.1 : "转写中…")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(line.2 ? 0.95 : 0.7))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !NetWatcher.shared.canUpload {
                Text("等网络后转写")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(CaptureMode.allCases) { m in
                    Button {
                        guard !flow.isRecording else { return }
                        settings.captureMode = m
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: m.symbol)
                                .font(.system(size: 10.5, weight: .medium))
                            Text(m.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(settings.captureMode == m ? Theme.accent : Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(settings.captureMode == m ? Color.white : Color.white.opacity(0.18))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(flow.isRecording)
                    .accessibilityLabel(m.title)
                }
            }
            Text(flow.isRecording ? "录音中不能换模式，结束这一场再换" : settings.captureMode.hint)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(flow.isRecording ? 0.75 : 1)
    }

    private var listenButton: some View {
        Button {
            toggleCapture()
        } label: {
            HStack(spacing: 7) {
                if flow.working {
                    ProgressView().scaleEffect(0.75).tint(.white)
                } else {
                    Image(systemName: flow.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(flow.working ? flow.statusText : (flow.isRecording ? "结束聆听" : "开始聆听"))
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(flow.isRecording || flow.working ? Color.white : Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(flow.isRecording || flow.working ? Color.white.opacity(0.16) : Color.white))
            .overlay(Capsule().stroke(Color.white.opacity(flow.isRecording ? 0.45 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(flow.working)
    }
    private var heroNote: String {
        if flow.isRecording { return "边说边转写；结束后统一分人，再整理成纪要。实时行先不标说话人，避免标错。" }
        if flow.working { return flow.statusText + "，稍等，整理好会推送到你配置的通道。" }
        if flow.canRetry, let err = flow.lastError { return err }
        if let s = flow.current, s.state == .done {
            return "这一场" + s.mode.title + "已整理，纪要和待办进了时间线。"
        }
        if let y = capture.yieldReason, !y.isEmpty { return y }
        if let e = capture.lastError, !e.isEmpty { return e }
        if settings.effectiveLLM.key.isEmpty {
            return "没填大模型密钥也能录音转写；整理纪要先在「设置 → 大模型与整理」填密钥。"
        }
        if app.todayEvents.isEmpty { return "点「开始聆听」边说边转写，结束就出纪要。" }
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
        Rectangle().fill(Color.white.opacity(0.22))
            .frame(width: 1, height: 30)
            // 竖线两侧留 12pt：原来紧贴数字，看起来像「|1」「|2」
            .padding(.horizontal, 12)
    }

    // MARK: 今日节律

    /// 四格全部按「会话」统计：场数、时长、产出的待办、说话人数。
    /// 原来靠段级说话人标签 + 模型给的 scene 字符串，「工作会议」这种写法就把会议数算成 0。
    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日节律")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(app.todaySessions.isEmpty ? "还没有会话" : "今天 \(app.todaySessions.count) 场")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.dim)
            }

            HStack(spacing: 0) {
                rhythmCell("\(app.meetingCount)", "场会议", Theme.accent)
                rhythmCell(sessionMinutesText, "开会时长", Theme.blue)
                rhythmCell("\(app.sessionTodoCount)", "条待办", Theme.purple)
                rhythmCell("\(app.peopleCount)", "位说话人", Theme.ok)
            }

            sessionStrip

            HStack(spacing: 12) {
                ForEach(CaptureMode.allCases) { m in
                    HStack(spacing: 4) {
                        Circle().fill(modeColor(m)).frame(width: 7, height: 7)
                        Text(m.title)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.dim)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private var sessionMinutesText: String {
        let minutes = Int((app.sessionSeconds / 60).rounded())
        if minutes < 60 { return "\(minutes) 分" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) 小时" : "\(h) 时 \(m) 分"
    }

    private func modeColor(_ m: CaptureMode) -> Color {
        switch m {
        case .meeting: return Theme.accent
        case .training: return Theme.purple
        case .call: return Theme.blue
        }
    }

    /// 当天 0–24 点的时间条：一场会话一段色块，一眼看出会开在什么时段。
    private var sessionStrip: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 0.6)
                    )
                ForEach(app.todaySessions) { s in
                    let r = dayFractions(s)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(modeColor(s.mode).opacity(0.85))
                        .frame(width: max(4, (r.1 - r.0) * w))
                        .offset(x: r.0 * w)
                }
                // 4 个整点刻度，方便对上时间
                ForEach([6, 12, 18], id: \.self) { h in
                    Rectangle().fill(Theme.line.opacity(0.9))
                        .frame(width: 0.6)
                        .offset(x: w * CGFloat(h) / 24)
                }
            }
        }
        .frame(height: 22)
        .accessibilityLabel("今天 \(app.todaySessions.count) 场会话的时间分布")
    }

    /// 会话在 0–24 小时里的起止比例；录音中的算到此刻。
    private func dayFractions(_ s: ListenSession) -> (CGFloat, CGFloat) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: s.startedAt)
        let start = max(0, s.startedAt.timeIntervalSince(dayStart))
        let end = max(start + 60, (s.endedAt ?? Date()).timeIntervalSince(dayStart))
        let a = min(max(start / 86400, 0), 1)
        let b = min(max(end / 86400, a + 0.002), 1)
        return (CGFloat(a), CGFloat(b))
    }

    private func rhythmCell(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            Text(v)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(c)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                if app.todayEvents.count > 6 {
                    Button { showTimeline = true } label: {
                        Text("全部 >").font(.system(size: 12.5)).foregroundColor(Theme.accent)
                            .tapTarget(10)
                    }
                    .buttonStyle(.plain)
                }
            }

            if app.todayEvents.isEmpty {
                EmptyHint(symbol: "clock.badge.questionmark", title: "这一天还没有整理出事件", detail: "有录音后等自动整理，或到设置里手动整理")
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

    /// 开始/结束都走会话：只有会话结束才知道「这一场」的范围，才能整场分人、整场整理。
    private func toggleCapture() {
        if flow.isRecording {
            flow.stop()
        } else {
            flow.start(mode: settings.captureMode)
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
    @State private var timelineLoading = false
    @EnvironmentObject private var app: AppState

    private var dayList: [String] {
        (0..<3).map { DayKey.of(Date().addingTimeInterval(-Double($0) * 86_400)) }
    }

    private var currentDay: String {
        dayList.indices.contains(scope) ? dayList[scope] : day
    }

    private var raw: [MemoryEvent] { loaded }

    private func loadTimeline() async {
        if loaded.isEmpty { timelineLoading = true }
        let day = currentDay
        let list = await Task.detached(priority: .userInitiated) {
            Store.shared.events(day: day, limit: 800)
        }.value
        if day == currentDay { loaded = list; timelineLoading = false }
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
                headerRow
                filterRow
                listBody
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

    /// 标题行拆成独立属性：整段 body 写在一起会触发「类型检查超时」
    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("时间线 · \(events.count) 件事")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.dim)
            Spacer(minLength: 8)
            segControl
        }
    }

    private var filterRow: some View {
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
    }

    @ViewBuilder
    private var listBody: some View {
        if timelineLoading && events.isEmpty {
            LoadingHint(rows: 3, text: "正在读取…")
        } else if events.isEmpty {
            EmptyHint(symbol: "clock.badge.questionmark",
                      title: "这一天还没有整理出事件",
                      detail: "有录音后等自动整理，或到设置里手动整理")
        } else {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                groupBlock(part: g.0, list: g.1)
            }
        }
    }

    private func groupBlock(part: String, list: [MemoryEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(part) · \(list.count) 件")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.dim2)
                .padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { idx, e in
                    lineRow(event: e, showDivider: idx < list.count - 1)
                }
            }
            .padding(.vertical, 2)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
    }

    private func lineRow(event e: MemoryEvent, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            TimelineLine(event: e, onStar: {
                app.starEvent(e.id, starred: !e.starred)
                reloadTick &+= 1
            }, onTap: {
                detailEvent = e
            })
            if showDivider {
                Rectangle().fill(Theme.line)
                    .frame(height: 0.6)
                    .padding(.leading, 58)
            }
        }
    }
    private var segControl: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Button { scope = i } label: {
                    Text(i == 0 ? "今天" : (i == 1 ? "昨天" : "前天"))
                        .font(.system(size: Theme.fsSmall, weight: scope == i ? .semibold : .regular))
                        .foregroundColor(scope == i ? Theme.accent : Theme.dim)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(scope == i ? Theme.accentSoft : Color.clear)
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
