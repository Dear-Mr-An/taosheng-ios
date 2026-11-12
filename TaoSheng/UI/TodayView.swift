import SwiftUI

struct TodayView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var digest = DigestEngine.shared
    @ObservedObject private var settings = Settings.shared

    @State private var heroCollapsed = false
    @State private var showShare = false
    @State private var toast: String?
    @State private var showTimeline = false

    private var today: String { DayKey.of(Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                heroCard
                rhythmCard
                timelineCard
                Color.clear.frame(height: 78)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [app.exportMarkdown(day: today)])
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
                let md = app.exportMarkdown(day: today)
                if md.count < 40 { toast = "这一天还没有可导出的内容" } else { showShare = true }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.text2)
                    .frame(width: 38, height: 38)
                    .background(Theme.card)
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
            HStack(spacing: 8) {
                ForEach(CaptureMode.allCases) { m in
                    Button {
                        switchMode(m)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: m.symbol)
                                .font(.system(size: 11, weight: .medium))
                            Text(m.title)
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundColor(settings.captureMode == m ? Theme.accent : Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(settings.captureMode == m ? Color.white : Color.white.opacity(0.18))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
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
        if wasRunning {
            capture.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                capture.start()
            }
        }
    }

    private var heroNote: String {
        if let e = capture.lastError, !e.isEmpty { return e }
        if let e = digest.lastError, !e.isEmpty { return e }
        if settings.effectiveLLM.key.isEmpty {
            return "填好大模型密钥后，转写出的原话会自动整理成一件件事"
        }
        if app.todayEvents.isEmpty {
            return "录到人声 → 转写成原话 → 说完约 10 分钟后整理成一件件事"
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

            LevelBars(level: min(1.0, app.todaySeconds / 3600.0), count: 32, color: Theme.accent.opacity(0.7))
                .frame(height: 34)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间线 · \(app.todayEvents.count) 件事")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if app.todayEvents.count > 6 {
                    Button { showTimeline = true } label: {
                        Text("全部").font(.system(size: 12.5)).foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if app.todayEvents.isEmpty {
                EmptyHint(text: "这一天还没有整理出事件")
            } else {
                ForEach(app.todayEvents.prefix(6)) { e in
                    EventRow(event: e, onStar: {
                        app.starEvent(e.id, starred: !e.starred)
                    }, onTap: { showTimeline = true })
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .sheet(isPresented: $showTimeline) {
            NavigationStack { TimelineFullView(day: today) }
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
        let t = digest.lastRunAt ?? Store.shared.reviews(limit: 1).first?.createdAt
        guard let t = t else { return "还没整理过" }
        let m = Int(Date().timeIntervalSince(t) / 60)
        if m < 1 { return "刚刚整理过" }
        if m < 60 { return "\(m) 分钟前整理过" }
        return "\(m / 60) 小时前整理过"
    }

    private var weekdayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: Date())
    }

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
    @ObservedObject private var app = AppState.shared
    @State private var earlyFirst = true

    private var events: [MemoryEvent] {
        let list = Store.shared.events(day: day, limit: 500)
        return earlyFirst ? list : list.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(events.count) 件事")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.dim)
                    Spacer()
                    Button {
                        earlyFirst.toggle()
                    } label: {
                        Text(earlyFirst ? "↓ 早的在上" : "↑ 晚的在上")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ForEach(events) { e in
                    EventRow(event: e, onStar: {
                        app.starEvent(e.id, starred: !e.starred)
                    })
                    .padding(.horizontal, 16)
                }
                if events.isEmpty { EmptyHint(text: "这一天还没有整理出事件") }
                Color.clear.frame(height: 40)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(day)
        .navigationBarTitleDisplayMode(.inline)
    }
}
