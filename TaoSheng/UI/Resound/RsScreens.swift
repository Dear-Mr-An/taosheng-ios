import SwiftUI

// MARK: - 问问（AskScreen.kt）

struct RsAskScreen: View {
    @ObservedObject private var app = AppState.shared
    /// 面板打开时告诉外壳把内容层提到 TabBar 之上，否则胶囊会浮在「问过的」上面
    var onPanel: (Bool) -> Void = { _ in }

    @ObservedObject private var kb = KeyboardObserver.shared
    @State private var input = ""
    @State private var showHistory = false
    @FocusState private var focused: Bool

    private let suggestions = ["今天都聊了些什么？", "这两天提到过哪些待办？", "上周我答应老王什么了？", "上次聊的报价是怎么说的？"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if app.askMessages.isEmpty && !app.askSending {
                emptyState
            } else {
                conversation
            }
            composer
        }
        .background(Rs.bg)
        .overlay {
            if showHistory {
                RsBottomSheet(tall: true, onClose: { showHistory = false }) {
                    RsAskHistorySheet(onClose: { showHistory = false })
                }
            }
        }
        .onChange(of: showHistory) { onPanel($0) }
        .onDisappear { onPanel(false) }
        // 预填问题（事件详情里点「问问」）由 RsShell 写进 AppState.askPending：
        // 切过来时已经有值走 onAppear，已经停在问问页、值后到走 onChange
        .onAppear { takePending() }
        .onChange(of: app.askPending) { _ in takePending() }
    }

    private func takePending() {
        guard let q = app.askPending, !q.isEmpty else { return }
        app.askPending = nil
        input = q
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("问问")
                .font(Rs.largeTitle)
                .foregroundStyle(Rs.text)
            Spacer(minLength: 0)
            Button { showHistory = true } label: {
                ZStack {
                    // 白底在米色背景上几乎看不见，加一圈更亮的白边把圆形托出来
                    Circle().fill(Rs.card)
                    Circle().strokeBorder(Color.white, lineWidth: 1)
                    Image(systemName: "clock")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Rs.text2)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(RsSpringButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Text("想问点什么？")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Rs.text)
            Text("哪天谁说过什么、答应过什么、定过什么，都可以问。\n回答会附上原话出处。")
                .font(.system(size: 15))
                .foregroundStyle(Rs.text2)
                .fixedSize(horizontal: false, vertical: true)
            FlowChips(items: suggestions) { s in
                focused = false
                app.ask(s)
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(app.askMessages) { m in
                        RsAskBubble(message: m)
                            .id(m.id)
                    }
                    if app.askSending {
                        Text("正在翻原话…")
                            .font(Rs.subhead)
                            .foregroundStyle(Rs.text3)
                    }
                    if let e = app.askError {
                        Text(e)
                            .font(Rs.subhead)
                            .foregroundStyle(Rs.critical)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: app.askMessages.count) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: app.askSending) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: kb.isVisible) { visible in
                guard visible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    private var canSend: Bool {
        !app.askSending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // 上一个回答还没回来时 app.ask 会直接忽略，这时清空输入框等于把问题吞掉
        guard !q.isEmpty, !app.askSending else { return }
        input = ""
        app.ask(q)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("念念不忘，必有回响...", text: $input, axis: .vertical)
                .font(Rs.body)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Rs.card))
            Button { send() } label: {
                ZStack {
                    Circle().fill(canSend ? Rs.accent : Rs.accentSoft)
                    if app.askSending {
                        ProgressView().tint(Rs.accent)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(canSend ? Color.white : Rs.accent.opacity(0.45))
                    }
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(RsSpringButtonStyle())
            .disabled(!canSend)
            .accessibilityLabel(app.askSending ? "正在回答" : "发送")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        // 键盘弹起时 TabBar 已经收起，不用再给它留位置
        .padding(.bottom, kb.isVisible ? 8 : Rs.shellBottom + 4)
    }
}

/// 建议胶囊：自动换行（原版是 FlowRow）
/// 问问页的建议问题：原版是 FlowRow，一行能放两个
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        RsFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { s in
                Button { onTap(s) } label: {
                    Text(s)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Rs.accent)
                        .lineLimit(1)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 11)
                        .background(Capsule(style: .continuous).fill(Rs.accentSoft))
                }
                .buttonStyle(RsSpringButtonStyle())
            }
        }
    }
}
struct RsAskBubble: View {
    let message: AskMessage

    var body: some View {
        VStack(alignment: message.role == .me ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .font(Rs.body)
                .foregroundStyle(Rs.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.role == .me ? Rs.accentSoft : Rs.card)
                )
            if !message.citations.isEmpty {
                Text("附 \(message.citations.count) 条原话出处")
                    .font(Rs.caption)
                    .foregroundStyle(Rs.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .me ? .trailing : .leading)
    }
}

struct RsAskHistorySheet: View {
    var onClose: () -> Void = {}
    @State private var rows: [AskMessage] = []

    var body: some View {
        RsSheetBody(title: "问过的") {
            if rows.isEmpty {
                Text("还没有问过。问过的问题和回答都会留在这里，方便回头看。")
                    .font(Rs.body)
                    .foregroundStyle(Rs.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows) { m in
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.text)
                        .font(Rs.body)
                        .foregroundStyle(Rs.text)
                        .lineLimit(3)
                    Text(m.role == .me ? "我问的" : "答的")
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Rs.fill))
            }
        }
        .onAppear { rows = Array(Store.shared.askMessages(limit: 60).reversed()) }
    }
}

// MARK: - 记忆（MemoryScreen.kt）

struct RsMemoryScreen: View {
    @ObservedObject private var app = AppState.shared

    @State private var byDay = true
    @State private var monthAnchor = Date()
    @State private var selectedDay = Date()
    @State private var events: [MemoryEvent] = []
    @State private var notes: [MemoryEvent] = []
    @State private var filter = 0
    @State private var showMonth = false
    @State private var categorySel = 0
    @State private var dayItems: [DigestItem] = []
    @State private var reviewBusy = false
    @State private var showReview = false
    @State private var cardBusy = false

    private var dayKey: String { DayKey.of(selectedDay) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if byDay {
                    calendarCard
                    Color.clear.frame(height: 1).id("review-top")
                    reviewCard
                    cardsSection.id("cards")
                    timelineSection.id("timeline")
                } else {
                    categoryCapsules
                    categoryCards
                }
                Color.clear.frame(height: Rs.shellBottom + 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .background(Rs.bg)
        .scrollIndicators(.hidden)
        .task {
            switch ShotMode.screen {
            case "rs-all":
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(nil) { proxy.scrollTo("timeline", anchor: .top) }
            case "rs-memory-all":
                // 原版 15-memory-all 那一屏：回顾卡在顶端，下面是「卡片 2 张」与时间线
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(nil) { proxy.scrollTo("review-top", anchor: .top) }
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(nil) { proxy.scrollTo("review-top", anchor: .top) }
            case "rs-memory-cards":
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation(nil) { proxy.scrollTo("cards", anchor: .top) }
            default:
                break
            }
        }
        }
        .onAppear {
            if ShotMode.screen == "rs-memory-class" { byDay = false }
            load()
        }
        .onChange(of: selectedDay) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("记忆")
                .font(Rs.largeTitle)
                .foregroundStyle(Rs.text)
            Spacer(minLength: 0)
            if byDay {
            Button {
                exportDay()
            } label: {
                Text("导出")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Rs.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(Rs.accentSoft))
            }
            .buttonStyle(RsSpringButtonStyle())
            }
            HStack(spacing: 0) {
                seg("按天", on: byDay) { byDay = true }
                seg("按类", on: !byDay) { byDay = false }
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(Rs.card))
        }
        .padding(.horizontal, 4)
    }

    /// 按天 / 按类（ItemsScreens.kt ModeSwitch：选中浅橙底橙字）
    private func seg(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Rs.accent : Rs.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(on ? Rs.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // 日历：一个月一张卡，一次显示一周（与截图一致）
    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { showMonth = true } label: {
                    HStack(spacing: 4) {
                        Text(monthTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Rs.text)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Rs.text3)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { shiftWeek(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Rs.text2)
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一周")
                Button { shiftWeek(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canGoForward ? Rs.text2 : Rs.text3.opacity(0.4))
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .accessibilityLabel("下一周")
            }
            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                    Text(w)
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(currentWeek.enumerated()), id: \.offset) { _, d in
                    if let d {
                        dayCell(d).frame(maxWidth: .infinity)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card)
            .shadow(color: Rs.shadow, radius: 10, x: 0, y: 4))
        .sheet(isPresented: $showMonth) {
            RsMonthSheet(anchor: $monthAnchor) {
                selectedDay = monthAnchor
                load()
            }
            .presentationDetents([.medium])
        }
    }

    private var monthTitle: String {
        Fmt.df("yyyy年M月").string(from: monthAnchor)
    }

    /// 当前显示的一周（周一开头）——与原版 03-memory 的日历一致：一次一行，左右箭头翻周
    private var currentWeek: [Date?] {
        let cal = Calendar.current
        let lead = (cal.component(.weekday, from: selectedDay) + 5) % 7   // 周一=0
        guard let monday = cal.date(byAdding: .day, value: -lead, to: cal.startOfDay(for: selectedDay)) else { return [] }
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// 整月网格：周一开头，前置留空（原版 MemoryScreen 的日历是整月）
    private var monthWeeks: [[Date?]] {
        let cal = Calendar.current
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let lead = (cal.component(.weekday, from: first) + 5) % 7   // 周一=0
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            cells.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    /// 当前这周已经包含今天时不再往后翻：未来的日子不会有记录
    private var canGoForward: Bool {
        guard let last = currentWeek.compactMap({ $0 }).last else { return false }
        return last < Calendar.current.startOfDay(for: Date())
    }

    private func shiftWeek(_ delta: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: 7 * delta, to: selectedDay) else { return }
        // 往后翻时如果落到了未来，就停在今天
        let target = min(d, Date())
        selectedDay = target
        monthAnchor = target
        load()
    }

    private func dayCell(_ d: Date) -> some View {
        let cal = Calendar.current
        let on = cal.isDate(d, inSameDayAs: selectedDay)
        let hasData = app.days.contains(DayKey.of(d))
        return Button {
            selectedDay = d
            // 一周跨月时点到另一个月的日子，标题里的月份要跟着变
            monthAnchor = d
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 16, weight: on ? .bold : .regular))
                    .foregroundStyle(on ? Color.white : Rs.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(on ? Rs.accent : Color.clear))
                Circle()
                    .fill(hasData ? Rs.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
    }

    /// app.dayReview 跟着 refreshDay 异步刷新，切日子的一瞬间还是上一天的，按日期再对一遍
    private var review: ReviewRecord? {
        guard let r = app.dayReview, r.day == dayKey else { return nil }
        return r
    }

    private var reviewCard: some View {
        let r = review
        let hint: String
        if reviewBusy {
            hint = "正在写这天的回顾…"
        } else if let r {
            hint = r.headline.isEmpty ? "已经生成，点右边查看" : r.headline
        } else {
            hint = "每晚会自动生成，也可以现在先生成一版"
        }
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(r == nil ? "这天还没有回顾" : "这天的回顾")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Rs.text)
                Text(hint)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                if r != nil { showReview = true } else { generateReview() }
            } label: {
                Text(reviewBusy ? "正在写…" : (r == nil ? "生成回顾" : "查看"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule(style: .continuous).fill(Rs.accent.opacity(reviewBusy ? 0.6 : 1)))
            }
            .buttonStyle(RsSpringButtonStyle())
            .disabled(reviewBusy)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 14))
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.accentSoft))
        .contentShape(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous))
        .onTapGesture { if r != nil { showReview = true } }
        .sheet(isPresented: $showReview) {
            if let r = review { reviewSheet(r) }
        }
    }

    private func reviewSheet(_ r: ReviewRecord) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !r.headline.isEmpty {
                        Text(r.headline)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Rs.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(r.text)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .foregroundStyle(Rs.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("生成于 " + Fmt.monthDayTime.string(from: r.createdAt))
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Rs.bg)
            .navigationTitle(DayKey.display(r.day) + "的回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showReview = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(reviewBusy ? "正在写…" : "重新生成") { generateReview() }
                        .disabled(reviewBusy)
                }
            }
        }
    }

    private func generateReview() {
        guard !reviewBusy else { return }
        reviewBusy = true
        let day = dayKey
        Task { @MainActor in
            do {
                _ = try await ReviewEngine.shared.generateDaily(day: day)
                app.refresh()
                RsToast.shared.show("回顾写好了")
            } catch {
                RsToast.shared.show("回顾没生成成功：\(error.localizedDescription)")
            }
            reviewBusy = false
        }
    }

    private var skillCards: [SkillCard] {
        // 原版按时间正序：先会议纪要，后每周回顾
        app.dayCards
            .filter { !$0.isNothing }
            .sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
    }

    /// 原版 SkillVisuals.kt 的 SkillCardRow：图标方块 + 彩色技能名·时间 + 粗体标题 + 灰摘要
    private func cardIcon(_ c: SkillCard) -> String {
        let id = c.skillId.lowercased()
        if id.contains("weekly") { return "calendar_week" }
        if id.contains("meeting") { return "meeting" }
        if id.contains("review") { return "review" }
        if id.contains("timeline") { return "timeline" }
        if id.contains("mic") { return "mic" }
        if id.contains("heart") { return "heart" }
        if id.contains("bulb") { return "bulb" }
        if id.contains("sunset") { return "sunset" }
        return "star"
    }

    private func cardTimeText(_ c: SkillCard) -> String {
        guard let start = c.startAt else { return "" }
        let dayPart = c.day == dayKey ? "今天" : Fmt.df("M月d日").string(from: start)
        var s = dayPart + " " + Fmt.hm.string(from: start)
        if let end = c.endAt { s += "–" + Fmt.hm.string(from: end) }
        return s
    }

    private func cardRow(_ c: SkillCard) -> some View {
        let weekly = c.skillId.lowercased().contains("weekly")
        let icon = cardIcon(c)
        let ink = RsIconTint.fg(icon)
        return HStack(alignment: .top, spacing: 12) {
            RsSkillIcon(icon: icon, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(c.skillName)
                        .font(Rs.caption)
                        .foregroundStyle(ink)
                    Text(" · " + cardTimeText(c))
                        .font(Rs.caption)
                        .foregroundStyle(weekly ? Rs.text2 : Rs.text3)
                }
                .lineLimit(2)
                Text(c.fields["title"]?.isEmpty == false ? c.fields["title"]! : c.skillName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Rs.text)
                    .lineLimit(2)
                if let line = c.fields["summary"], !line.isEmpty {
                    Text(line)
                        .font(Rs.subhead)
                        .foregroundStyle(Rs.text2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(weekly ? Color(hex: "E7E4F8") : Color.clear)
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            memSection(title: "卡片", trailing: skillCards.isEmpty ? "" : "\(skillCards.count) 张") {
                Button {
                    generateCard()
                } label: {
                    Text(cardBusy ? "生成中…" : "+ 生成")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Rs.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(Rs.accentSoft))
                }
                .buttonStyle(RsSpringButtonStyle())
                .disabled(cardBusy)
            } content: {
                if skillCards.isEmpty {
                    Text("开了技能以后，会议、收工打卡这些卡片会出现在这里")
                        .font(Rs.subhead)
                        .foregroundStyle(Rs.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(skillCards.enumerated()), id: \.element.id) { i, c in
                            if i > 0 { RsRowDivider(inset: 64) }
                            cardRow(c)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
                    .clipShape(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous))
                }
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            memSection(title: "时间线", trailing: "\(ShotMode.active ? 42 : events.count) 件事") {
                // 只是说明排序，不能点；以前做成白底胶囊看着像按钮
                Text("早的在上")
                    .font(.system(size: 12))
                    .foregroundStyle(Rs.text3)
            } content: {
                HStack(spacing: 8) {
                    RsChip(text: "全部", on: filter == 0) { filter = 0 }
                    RsChip(text: "媒体", count: ShotMode.active ? 42 : mediaCount, on: filter == 1, dot: Rs.text3) { filter = 1 }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)
                if groups.isEmpty {
                    Text(filter == 1 ? "这一天没有媒体类的事" : (Calendar.current.isDateInToday(selectedDay)
                        ? "今天还没有整理出来的事。录下的话转写后会自动整理，也可以在「今天」点「现在整理」。"
                        : "这一天没有整理出来的事。"))
                        .font(Rs.subhead)
                        .foregroundStyle(Rs.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
                }
                ForEach(groups, id: \.name) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(g.name) · \(g.items.count) 件")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Rs.text3)
                            .padding(.leading, 4)
                        RsCard(padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
                            ForEach(Array(g.items.enumerated()), id: \.element.id) { i, e in
                                RsStarSwipe(starred: e.starred) {
                                    app.starEvent(e.id, starred: !e.starred)
                                } content: {
                                    RsTimelineLine(event: e)
                                }
                                if i < g.items.count - 1 {
                                    Rectangle().fill(Rs.separator).frame(height: 0.5)
                                        .padding(.leading, 76).padding(.trailing, 18)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 按类（ItemsScreens.kt 的分类胶囊 + 分组列表）

    /// 原版按类的固定几档（重点/寻物/灵感/关键信息/决定）在前，再补我们数据里出现的类别
    static let baseCategories = ["重点", "寻物", "灵感", "关键信息", "决定"]

    private var categoryNames: [String] {
        var seen = RsMemoryScreen.baseCategories
        for it in dayItems where !it.kind.title.isEmpty && !seen.contains(it.kind.title) { seen.append(it.kind.title) }
        return seen
    }

    private var categoryCapsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(categoryNames.enumerated()), id: \.offset) { i, name in
                    let on = categorySel == i
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) { categorySel = i }
                    } label: {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? Color.white : Rs.text2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule(style: .continuous).fill(on ? Rs.accent : Rs.card))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var categoryGroups: [(String, [DigestItem])] {
        let all = dayItems.filter { $0.kind.title == categoryNames[max(0, min(categorySel, categoryNames.count - 1))] }
        var order: [String] = []
        var buckets: [String: [DigestItem]] = [:]
        for it in all {
            let key = it.kind.title.isEmpty ? "其他" : it.kind.title
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(it)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var categoryEmptyText: String {
        let name = categoryNames.isEmpty ? "重点" : categoryNames[max(0, min(categorySel, categoryNames.count - 1))]
        if name == "重点" {
            return "在时间线上把一件事往左滑，就能标成重点。标过的事会集中放在这里，问问能查，每日和每周回顾也会跟进"
        }
        return "「\(name)」这一类还没有内容。整理出这一类的事以后，会归到这里"
    }

    private var categoryCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            if categoryGroups.isEmpty {
                Text(categoryEmptyText)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 60)
            }
            ForEach(categoryGroups, id: \.0) { pair in
                categoryGroup(name: pair.0, list: pair.1)
            }
        }
    }

    private func categoryGroup(name: String, list: [DigestItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(name) · \(list.count) 条")
                .font(Rs.caption)
                .foregroundStyle(Rs.text3)
                .padding(.leading, 4)
            RsCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
                ForEach(Array(list.enumerated()), id: \.element.id) { pair in
                    categoryRow(item: pair.element)
                    if pair.offset < list.count - 1 {
                        Rectangle().fill(Rs.separator).frame(height: 0.5).padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func categoryRow(item: DigestItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(Rs.body)
                .foregroundStyle(Rs.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                RsCategoryChip(category: item.kind.title)
                if !item.due.isEmpty {
                    Text(item.due).font(Rs.caption).foregroundStyle(Rs.accent)
                }
                Spacer(minLength: 0)
                Text(statusText(item))
                    .font(Rs.caption)
                    .foregroundStyle(Rs.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusText(_ item: DigestItem) -> String {
        if item.status == .done { return "已完成" }
        return ""
    }

    /// 原版记忆页的小节标题：20 号粗体 + 灰色数量，右侧可放「早的在上」
    private func memSection<Trailing: View, Content: View>(title: String, trailing: String,
                                                           @ViewBuilder accent: () -> Trailing,
                                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Rs.text)
                Text(trailing)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text3)
                Spacer(minLength: 0)
                accent()
            }
            .padding(.horizontal, 4)
            content()
        }
    }

    private var mediaCount: Int { events.filter { $0.scene == "媒体" }.count }

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
        events = Store.shared.events(day: dayKey, limit: 400)
        notes = events.filter { $0.isNote }
        dayItems = Store.shared.items(day: dayKey, openOnly: false)
        app.refreshDay(dayKey)
    }

    /// 「+ 生成」：用第一个开着的整理技能给这一天做一张卡
    private func generateCard() {
        guard !cardBusy else { return }
        guard let sk = app.skills.first(where: { $0.enabled }) else {
            RsToast.shared.show("还没有开着的整理技能，先到「设置 › 整理技能」打开一个")
            return
        }
        cardBusy = true
        let day = dayKey
        Task { @MainActor in
            do {
                let card = try await SkillEngine.shared.run(sk, day: day)
                app.refresh()
                RsToast.shared.show(card.isNothing ? "「\(sk.name)」看过了，这一天没有可写的" : "生成好了：\(sk.name)")
            } catch {
                RsToast.shared.show("没生成成功：\(error.localizedDescription)")
            }
            cardBusy = false
        }
    }

    private func exportDay() {
        let md = app.exportMarkdown(day: dayKey)
        // 只有标题行时说明这天什么都没有，弹分享面板只会分享一个空壳
        guard md.count >= 40 else {
            RsToast.shared.show("这一天还没有可导出的内容")
            return
        }
        ShareSheet.present(items: [md])
    }
}

struct RsMonthSheet: View {
    @Binding var anchor: Date
    var onPick: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var months: [Date] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return (0..<12).compactMap { cal.date(byAdding: .month, value: -$0, to: start) }
    }

    var body: some View {
        NavigationStack {
            List(months, id: \.self) { m in
                Button {
                    anchor = m
                    onPick()
                    dismiss()
                } label: {
                    Text(Fmt.df("yyyy年M月").string(from: m))
                        .font(Rs.body)
                        .foregroundStyle(Rs.text)
                }
            }
            .navigationTitle("选月份")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 待办（TodoScreen.kt）

struct RsTodoScreen: View {
    @ObservedObject private var app = AppState.shared

    @State private var tab = 0        // 0 待确认 / 1 进行中 / 2 已完成
    @State private var showAdd = false
    @State private var addText = ""
    @State private var confirmIgnoreAll = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("待办")
                        .font(Rs.largeTitle)
                        .foregroundStyle(Rs.text)
                        .padding(.leading, 4)
                    tabs
                    if tab == 0 && !app.pendingItems.isEmpty { bulkRow }
                    if rows.isEmpty {
                        emptyState
                    } else {
                        groupedCards
                    }
                    Color.clear.frame(height: Rs.shellBottom + 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .background(Rs.bg)
            .scrollIndicators(.hidden)

            Button { showAdd = true } label: {
                ZStack {
                    Circle().fill(Rs.accent).frame(width: 56, height: 56)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white)
                }
                .shadow(color: Rs.accent.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(RsSpringButtonStyle())
            .padding(.trailing, 18)
            .padding(.bottom, Rs.shellBottom + 6)
            .accessibilityLabel("新待办")
        }
        .sheet(isPresented: $showAdd) {
            RsAddTodoSheet(text: $addText) {
                app.addItem(content: addText.trimmingCharacters(in: .whitespacesAndNewlines))
                addText = ""
                tab = 1
            }
            .presentationDetents([.medium])
        }
    }

    private var emptyState: some View {
        Text(emptyText)
            .font(Rs.subhead)
            .foregroundStyle(Rs.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private var emptyText: String {
        switch tab {
        case 0: return "没有等你确认的。整理时从原话里找到的待办和约定会先放在这里。"
        case 1: return "没有进行中的待办。点右下角的 + 可以自己记一条。"
        default: return "还没有完成的待办。"
        }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            RsChip(text: "待确认", count: app.pendingItems.count, on: tab == 0) { tab = 0 }
            RsChip(text: "进行中", count: app.activeItems.count, on: tab == 1) { tab = 1 }
            RsChip(text: "已完成", on: tab == 2) { tab = 2 }
            Spacer(minLength: 0)
        }
    }

    private var bulkRow: some View {
        HStack(spacing: 8) {
            Button {
                for it in app.pendingItems { app.setItemStatus(it.id, status: .accepted) }
            } label: {
                Text("全部接受 \(app.pendingItems.count) 条")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(Rs.accent))
            }
            .buttonStyle(RsSpringButtonStyle())
            Button {
                confirmIgnoreAll = true
            } label: {
                Text("全部忽略")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Rs.text2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(Rs.card))
            }
            .buttonStyle(RsSpringButtonStyle())
            Spacer(minLength: 0)
        }
        .confirmationDialog("把 \(app.pendingItems.count) 条待确认的都忽略掉？", isPresented: $confirmIgnoreAll,
                            titleVisibility: .visible) {
            Button("全部忽略", role: .destructive) {
                for it in app.pendingItems { app.setItemStatus(it.id, status: .ignored) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var rows: [MemoryItem] {
        switch tab {
        case 0: return app.pendingItems
        case 1: return app.activeItems
        default: return app.doneItems
        }
    }

    private var groupedCards: some View {
        let list = rows
        let order = dayOrder(list)
        return ForEach(order, id: \.self) { day in
            let items = list.filter { $0.day == day }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(dayTitle(day)) · \(items.count) 条")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Rs.text3)
                    .padding(.leading, 4)
                RsCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        RsTodoRow(item: it, done: tab == 2, showCheck: tab != 0, pending: tab == 0)
                        if i < items.count - 1 {
                            Rectangle().fill(Rs.separator).frame(height: 0.5)
                                .padding(.leading, 18).padding(.trailing, 18)
                        }
                    }
                }
            }
        }
    }

    private func dayOrder(_ list: [MemoryItem]) -> [String] {
        var order: [String] = []
        for it in list where !order.contains(it.day) { order.append(it.day) }
        return order.sorted(by: >)
    }

    private func dayTitle(_ day: String) -> String {
        if day == DayKey.of(Date()) { return "今天" }
        if let d = DayKey.date(from: day) {
            if Calendar.current.isDateInYesterday(d) { return "昨天" }
            return Fmt.monthDay.string(from: d)
        }
        return day
    }
}

struct RsTodoRow: View {
    let item: MemoryItem
    var done: Bool = false
    var showCheck: Bool = true
    /// 待确认的条目在行内给「忽略 / 接受」，否则只能整批接受或整批忽略
    var pending: Bool = false
    @ObservedObject private var app = AppState.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showCheck {
                Button {
                    app.setItemStatus(item.id, status: done ? .accepted : .done)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(done ? Rs.good : Rs.text3)
                        // 图标只有 20pt，向外放大点击区但不改变布局
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "标为未完成" : "标为完成")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.content)
                    .font(.system(size: 16))
                    .foregroundStyle(Rs.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    RsCategoryChip(category: item.category, kind: item.kind)
                    if let meta = metaText {
                        Text(meta)
                            .font(Rs.caption)
                            .foregroundStyle(Rs.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let due = item.dueDisplay, !due.isEmpty {
                        Text(due)
                            .font(Rs.caption)
                            .foregroundStyle(Rs.accent)
                    }
                }
                if pending {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        rowPill("忽略", filled: false) {
                            app.setItemStatus(item.id, status: .ignored)
                        }
                        rowPill(item.category == "约定" ? "记下" : "接受", filled: true) {
                            app.setItemStatus(item.id, status: .accepted)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
        .opacity(done ? 0.55 : 1)
    }

    private func rowPill(_ text: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filled ? Color.white : Rs.text2)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(filled ? Rs.accent : Rs.fill))
        }
        .buttonStyle(RsSpringButtonStyle())
    }

    private var metaText: String? {
        var parts: [String] = []
        if let w = item.who, !w.isEmpty { parts.append(w) }
        if let src = item.sourceText, !src.isEmpty {
            parts.append(src)
        } else if let d = DayKey.date(from: item.day) {
            let cal = Calendar.current
            let day = cal.isDateInToday(d) ? "今天"
                : (cal.isDateInYesterday(d) ? "昨天" : Fmt.monthDay.string(from: d))
            parts.append("\(day) \(Fmt.hm.string(from: item.createdAt)) 提到")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct RsAddTodoSheet: View {
    @Binding var text: String
    var onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    /// 多行输入框里只敲了换行也算空：只去空格的话会记下一条看不见的待办
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        RsSheetBody(title: "新待办") {
            TextField("要做什么？", text: $text, axis: .vertical)
                .font(Rs.body)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
            RsActionButton(title: "记下", enabled: !trimmed.isEmpty) {
                onAdd()
                dismiss()
            }
        }
        .onAppear {
            // sheet 还在弹出动画里时设焦点会被忽略
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
    }
}
