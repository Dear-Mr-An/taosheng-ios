import SwiftUI

// MARK: - 暂停（原版 QuickPause：暂停多久 + 到点自动恢复）

/// 原版首页上的「❚❚」：暂停收音一段时间，到点自己恢复。
/// 暂停期间 captureWanted 置 false，恢复时再起；时长按上次选择记在本地。
final class RsQuiet: ObservableObject {
    static let shared = RsQuiet()

    @Published private(set) var until: Date?
    @Published private(set) var lastPauseMinutes: Int

    private var timer: Timer?

    private init() {
        let saved = UserDefaults.standard.object(forKey: "rsLastPauseMinutes") as? Int
        lastPauseMinutes = saved ?? 30
        if let t = UserDefaults.standard.object(forKey: "rsQuietUntil") as? Date, t > Date() {
            until = t
            scheduleWatch()
        } else {
            UserDefaults.standard.removeObject(forKey: "rsQuietUntil")
        }
    }

    var isQuiet: Bool { until != nil }

    var resumeText: String {
        guard let u = until else { return "" }
        return Fmt.hm.string(from: u)
    }

    func pause(minutes: Int) {
        lastPauseMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "rsLastPauseMinutes")
        let t = Date().addingTimeInterval(Double(minutes) * 60)
        until = t
        UserDefaults.standard.set(t, forKey: "rsQuietUntil")
        UserDefaults.standard.set(false, forKey: "captureWanted")
        CaptureEngine.shared.stop()
        scheduleWatch()
    }

    func resume() {
        until = nil
        timer?.invalidate()
        timer = nil
        UserDefaults.standard.removeObject(forKey: "rsQuietUntil")
        UserDefaults.standard.set(true, forKey: "captureWanted")
        if !CaptureEngine.shared.isRunning { CaptureEngine.shared.start() }
    }

    private func scheduleWatch() {
        timer?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, let u = self.until else { return }
            if u <= Date() { self.resume() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - 今天页

struct RsTodayScreen: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var digest = DigestEngine.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var quiet = RsQuiet.shared

    @State private var dayOffset = 0
    @State private var filter = 0                 // 0 全部 / 1 媒体
    @State private var showListen = false
    @State private var showSearch = false
    @State private var showTopic = false
    @State private var themeMode: RsThemeMode = .system
    /// 截图模式：进页面就打开对应抽屉
    var autoSheet: String? = nil
    /// 面板打开时告诉外层，好把自己盖到 TabBar 上面
    var onPanel: (Bool) -> Void = { _ in }
    @State private var cachedEvents: [MemoryEvent] = []

    /// 今天直接读 AppState（刷新完成后自动跟着变），其它天用一次查询的缓存
    private var events: [MemoryEvent] { dayOffset == 0 ? app.todayEvents : cachedEvents }
    private var pending: [MemoryItem] { dayOffset == 0 ? app.pendingItems : [] }

    private var pendingCardWidth: CGFloat {
        max(150, (UIScreen.main.bounds.width - 32 - 12) / 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                RsOverviewCard(onPending: {
                    withAnimation(.easeOut(duration: 0.2)) { filter = 0 }
                }, onOpenListen: { showListen = true },
                   activeOverride: ShotMode.screen == "rs-today" ? true : nil)
                if !pending.isEmpty { pendingSection }
                timelineSection
                Color.clear.frame(height: Rs.shellBottom + 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Rs.bg)
        .scrollIndicators(.hidden)
        .overlay {
            if showListen {
                RsBottomSheet(tall: true, onClose: { showListen = false }) {
                    RsListenSheet(onClose: { showListen = false })
                }
            }
            if showTopic {
                RsBottomSheet(tall: true, onClose: { showTopic = false }) {
                    RsTopicSheet(onClose: { showTopic = false })
                }
            }
            if showSearch {
                RsBottomSheet(onClose: { showSearch = false }) {
                    RsRecordSearchSheet(onClose: { showSearch = false })
                }
            }
        }
        .onChange(of: showListen) { onPanel($0 || showTopic || showSearch) }
        .onChange(of: showTopic) { onPanel(showListen || $0 || showSearch) }
        .onChange(of: showSearch) { onPanel(showListen || showTopic || $0) }
        .onAppear {
            load()
            if autoSheet == "listen" { showListen = true }
            if autoSheet == "search" { showSearch = true }
            if autoSheet == "topic" { showTopic = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in load() }
        .onChange(of: dayOffset) { _ in load() }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text2)
                Text(dayText)
                    .font(Rs.largeTitle)
                    .foregroundStyle(Rs.text)
            }
            Spacer(minLength: 0)
            Button { showSearch = true } label: {
                ZStack {
                    Circle().fill(Rs.accentSoft)
                    RsMagnifier().frame(width: 18, height: 18)
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(RsSpringButtonStyle())
            RsThemeModePill(mode: $themeMode)
        }
        .padding(.horizontal, 4)
    }

    private var label: String {
        dayOffset == 0 ? "今天 · \(weekday)" : (dayOffset == 1 ? "昨天 · \(weekday)" : "前天 · \(weekday)")
    }

    private var weekday: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: dayDate)
    }

    private var dayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: dayDate)
    }

    private var dayDate: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
    }

    // MARK: 待确认

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsSection(title: "待确认") {
                Text("\(pending.count) 条")
                    .font(Rs.section)
                    .foregroundStyle(Rs.text3)
            } content: {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(pending) { it in
                            RsPendingCard(item: it)
                                .frame(width: pendingCardWidth)
                        }
                    }
                }
            }
        }
    }

    // MARK: 时间线

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsSection(title: "时间线 · \(events.count) 件事") {
                RsDaySwitcher(selected: $dayOffset, compact: true)
            } content: {
                HStack(spacing: 8) {
                    RsChip(text: "全部", on: filter == 0) { filter = 0 }
                    RsChip(text: "媒体", count: mediaCount, on: filter == 1, dot: Rs.text3) { filter = 1 }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 14)

                ForEach(groups, id: \.name) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(g.name) · \(g.items.count) 件")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Rs.text3)
                            .padding(.leading, 4)
                        RsCard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
                            ForEach(Array(g.items.enumerated()), id: \.element.id) { i, e in
                                RsTimelineLine(event: e)
                                if i < g.items.count - 1 {
                                    Rectangle()
                                        .fill(Rs.separator)
                                        .frame(height: 0.5)
                                        .padding(.leading, 76)
                                        .padding(.trailing, 18)
                                }
                            }
                        }
                    }
                }

                if groups.isEmpty {
                    RsCard {
                        Text("这一天还没有事情。点上面的「开始聆听」，说过的话会自动变成事件。")
                            .font(Rs.body)
                            .foregroundStyle(Rs.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var mediaCount: Int {
        events.filter { $0.scene == "媒体" }.count
    }

    private struct Group { let name: String; let items: [MemoryEvent] }

    private var groups: [Group] {
        let base = filter == 1 ? events.filter { $0.scene == "媒体" } : events
        let sorted = base.sorted { $0.startAt < $1.startAt }
        var out: [Group] = []
        for name in ["凌晨", "上午", "下午", "晚上"] {
            let items = sorted.filter { partOfDay($0.startAt) == name }
            if !items.isEmpty { out.append(Group(name: name, items: items)) }
        }
        return out
    }

    private func partOfDay(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        if h < 6 { return "凌晨" }
        if h < 12 { return "上午" }
        if h < 18 { return "下午" }
        return "晚上"
    }

    private func load() {
        guard dayOffset != 0 else { cachedEvents = []; return }
        cachedEvents = Store.shared.events(day: DayKey.of(dayDate), limit: 400)
    }
}

// MARK: - 主卡（OverviewCard.kt）

struct RsOverviewCard: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var digest = DigestEngine.shared
    @ObservedObject private var quiet = RsQuiet.shared
    @ObservedObject private var settings = Settings.shared

    var onPending: () -> Void = {}
    var onOpenListen: () -> Void = {}
    /// 截图模式用：模拟器没有麦克风，按原版显示「正在聆听」和暂停键
    var activeOverride: Bool? = nil

    private var recording: Bool { activeOverride == true ? false : (capture.isRunning && capture.isSpeaking) }
    private var listening: Bool { activeOverride ?? capture.isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow
            statsRow
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 0.5)
                .padding(.top, 10)
            digestRow
                .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 12, trailing: 18))
        .background(cardBackground)
        .shadow(color: Color(hex: "E2632A").opacity(0.28), radius: 14, x: 0, y: 8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Rs.heroRadius, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(hex: "F59048"), Color(hex: "E5672C"), Color(hex: "CF4A1E")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Rs.heroRadius, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
    }

    // 第一行：状态点 + 状态字 + › + 声波 + 专题 + 暂停键
    private var statusRow: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.white.opacity(listening ? 1 : 0.5))
                .frame(width: 8, height: 8)
            Spacer().frame(width: 8)
            Button {
                onOpenListen()
            } label: {
                HStack(spacing: 0) {
                    Text(statusText)
                        .font(Rs.headline)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(" ›")
                        .font(Rs.headline)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            RsBreathingWave(level: capture.level, active: listening, recording: recording, tint: .white)
                .frame(height: 22)
                .frame(maxWidth: 110)
            Spacer(minLength: 8)
            RsHeroPill(text: "◉ 专题") { onOpenListen() }
            Spacer().frame(width: 6)
            roundKey
        }
        .frame(height: 36)
    }

    private var roundKey: some View {
        Button {
            if quiet.isQuiet {
                quiet.resume()
            } else if listening {
                quiet.pause(minutes: quiet.lastPauseMinutes)
            } else {
                UserDefaults.standard.set(true, forKey: "captureWanted")
                CaptureEngine.shared.start()
            }
        } label: {
            ZStack {
                Circle().fill(quiet.isQuiet || !listening ? Color.white : Color.white.opacity(0.22))
                glyph
                    .foregroundStyle(quiet.isQuiet || !listening ? Color(hex: "D2511F") : Color.white)
                    .frame(width: 12, height: 12)
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .frame(width: 44, height: 44)
        .buttonStyle(RsSpringButtonStyle())
    }

    @ViewBuilder private var glyph: some View {
        if quiet.isQuiet || !listening {
            // ▶ 恢复
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: size.width * 0.22, y: 0))
                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                p.addLine(to: CGPoint(x: size.width * 0.22, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(quiet.isQuiet || !listening ? Color(hex: "D2511F") : Color.white))
            }
        } else {
            // ❚❚ 暂停：两根圆角竖条
            HStack(spacing: 2.5) {
                Capsule().frame(width: 3.4)
                Capsule().frame(width: 3.4)
            }
        }
    }

    private var statusText: String {
        // 截图模式：模拟器没有麦克风，按原版显示「正在聆听」
        if activeOverride == true { return "正在聆听" }
        if let _ = quiet.until {
            return "已暂停 · \(quiet.resumeText) 恢复"
        }
        if capture.isRunning {
            return recording ? "正在录音" : "正在聆听"
        }
        if let y = capture.yieldReason, !y.isEmpty { return y }
        return "没在聆听"
    }

    // 第二行：三个大数字
    private var statsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            stat(speechParts.0, speechParts.1) {}
            stat("\(app.eventCount)", "件") {}
            stat("\(app.pendingItems.count)", "条") { onPending() }
        }
        .padding(.top, 8)
    }


    private func stat(_ number: String, _ unit: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(number)
                        .font(Rs.number)
                        .foregroundStyle(Color.white)
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Text(unit == "条" ? "待确认 ›" : (unit == "件" ? "事件" : "人声"))
                    .font(Rs.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var speechParts: (String, String) {
        let minutes = Int((app.todaySeconds / 60).rounded())
        if minutes < 60 { return ("\(max(0, minutes))", "分钟") }
        return ("\(minutes / 60) 小时 \(minutes % 60)", "分")
    }

    // 第三行：整理状态 + 现在整理 + 模型
    private var digestRow: some View {
        HStack(spacing: 6) {
            Text(digestLine)
                .font(Rs.caption)
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(2)
            Spacer(minLength: 6)
            RsHeroPill(text: digest.running ? "排队中" : "现在整理", filled: true) {
                guard !digest.running else { return }
                Task { _ = try? await DigestEngine.shared.digest(day: DayKey.of(Date())) }
            }
            RsHeroPill(text: modelName) { onOpenListen() }
        }
        .padding(.top, 8)
    }

    /// 原版写的是服务商名（DeepSeek ›），不是模型 id
    private var modelName: String {
        let raw = settings.llmModel
        if raw.isEmpty { return "模型 ›" }
        let low = raw.lowercased()
        if low.hasPrefix("deepseek") { return "DeepSeek ›" }
        if low.hasPrefix("gpt") || low.hasPrefix("o1") || low.hasPrefix("o3") { return "OpenAI ›" }
        if low.contains("qwen") { return "通义 ›" }
        if low.contains("glm") { return "智谱 ›" }
        if low.contains("gemini") { return "Gemini ›" }
        return "\(raw) ›"
    }

    private var digestLine: String {
        if digest.running { return "正在整理…" }
        if let t = digest.lastRunAt {
            let m = Int(Date().timeIntervalSince(t) / 60)
            if m < 1 { return "刚刚整理过" }
            if m < 60 { return "\(m) 分钟前整理过" }
            return "\(m / 60) 小时前整理过"
        }
        return "还没整理过"
    }
}

// MARK: - 待确认卡（PendingCard）

struct RsPendingCard: View {
    let item: MemoryItem
    @ObservedObject private var app = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                RsCategoryChip(category: item.category, kind: item.kind)
                Spacer(minLength: 0)
                if let due = item.dueDisplay, !due.isEmpty {
                    Text(due)
                        .font(Rs.caption)
                        .foregroundStyle(dueColor)
                        .lineLimit(1)
                }
            }
            Text(item.content)
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(Rs.text)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 7)
            HStack(spacing: 8) {
                SmallPill(text: "忽略", filled: false) {
                    app.setItemStatus(item.id, status: .ignored)
                }
                SmallPill(text: item.category == "约定" ? "记下" : "接受", filled: true) {
                    app.setItemStatus(item.id, status: .accepted)
                }
            }
            .padding(.top, 9)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous)
                .fill(Rs.accentSoft)
                .shadow(color: Rs.shadow, radius: 10, x: 0, y: 4)
        )
    }

    private var dueColor: Color {
        guard let d = item.dueAt else { return Rs.accent }
        if d < Date() { return Rs.critical }
        if Calendar.current.isDateInToday(d) { return Rs.warning }
        return Rs.accent
    }
}

private struct SmallPill: View {
    let text: String
    var filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filled ? Color.white : Rs.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(filled ? Rs.accent : Rs.card))
        }
        .buttonStyle(RsSpringButtonStyle())
    }
}

// MARK: - 时间线一行（TimelineLine）

struct RsTimelineLine: View {
    let event: MemoryEvent
    var onStar: (() -> Void)? = nil
    @State private var detail: MemoryEvent?
    @State private var shotOpened = false

    private var quietRow: Bool { event.scene == "媒体" }

    var body: some View {
        Button {
            detail = event
        } label: {
            HStack(alignment: .top, spacing: 0) {
                Text(event.timeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(timeColor)
                    .frame(minWidth: 58, alignment: .leading)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(event.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Rs.text)
                            .lineLimit(1)
                        if event.starred {
                            Text("★").font(Rs.caption).foregroundStyle(Rs.accent)
                        } else if event.important {
                            Text("要紧").font(Rs.caption).foregroundStyle(Rs.text3)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(event.summary)
                        .font(.system(size: 12)).lineSpacing(4)
                        .foregroundStyle(Rs.text2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
            .opacity(quietRow ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .onAppear {
            if ShotMode.screen == "rs-event", !shotOpened {
                shotOpened = true
                detail = event
            }
        }
        .sheet(item: $detail) { e in
            NavigationStack {
                RsEventSheet(event: e)
                    .environmentObject(AppState.shared)
            }
        }
    }

    private var timeColor: Color {
        if quietRow { return Rs.text3 }
        if event.starred { return Rs.accent }
        if let end = event.endAt, Date().timeIntervalSince(end) < 3600 { return Rs.accent }
        return Rs.text2
    }
}
