import SwiftUI

struct TodayView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var capture: CaptureEngine
    @EnvironmentObject var digest: DigestEngine
    @EnvironmentObject var settings: Settings

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: Date())
    }

    private var weekText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var totalTalk: String {
        let s = Int(app.todaySegments.reduce(0) { $0 + $1.duration })
        if s < 60 { return "\(s)秒" }
        let m = s / 60
        if m < 60 { return "\(m)分钟" }
        return "\(m / 60)小时\(m % 60)分"
    }

    private var digestAgo: String {
        guard let t = digest.lastRunAt else { return "还没整理过" }
        let m = Int(Date().timeIntervalSince(t) / 60)
        if m < 1 { return "刚刚整理过" }
        if m < 60 { return "\(m)分钟前整理过" }
        return "\(m / 60)小时前整理过"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                heroCard
                rhythmCard
                timelineCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: - 头部
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今天 · \(weekText)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
                Text(dateText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Button {
                if let url = writeExport() {
                    shareURL = url
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @State private var shareURL: URL?

    // MARK: - 正在聆听
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .opacity(capture.isRunning ? 1 : 0.45)
                Text(capture.isRunning ? "正在聆听" : "点这里开始聆听")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                if capture.isRunning {
                    LevelBars(level: capture.level, count: 14, color: .white)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(totalTalk)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                VStack(spacing: 1) {
                    Text("\(app.todaySegments.count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("今天说话")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.82))
                }
                VStack(spacing: 1) {
                    Text("\(app.openItems.count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("待确认")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 1)

            HStack(spacing: 10) {
                Text(digestAgo)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button {
                    digest.digest(day: DayKey.of(Date()))
                } label: {
                    HStack(spacing: 4) {
                        if digest.running {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                        }
                        Text(digest.running ? "整理中" : "现在整理")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text(settings.llmReady ? "模型已就绪" : "未配模型")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(16)
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.28), radius: 14, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { toggleCapture() }
    }

    // MARK: - 今日节律
    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日节律")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if capture.isRunning {
                    Text(capture.isSpeaking ? "有人在说话" : "环境安静")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }

            HStack(spacing: 0) {
                StatCell(value: shortDur(app.mySeconds), label: "我说了", color: Theme.accent)
                StatCell(value: shortDur(app.otherSeconds), label: "别人说了", color: Theme.blue)
                StatCell(value: "\(app.peopleCount)", label: "人聊过", color: Theme.purple)
                StatCell(value: "\(app.todayItems.count)", label: "件事", color: Theme.ok)
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<28, id: \.self) { i in
                    let h = barHeight(i)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent.opacity(0.18 + 0.5 * h))
                        .frame(height: max(4, h * 42))
                }
            }
            .frame(height: 44, alignment: .bottom)
        }
        .card()
    }

    private func barHeight(_ i: Int) -> Double {
        let base = Double((i * 53) % 17) / 17.0
        let live = capture.isRunning ? capture.level : 0
        return min(1.0, 0.15 + base * 0.6 + live * 0.9)
    }

    // MARK: - 时间线
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("时间线 · \(app.todayItems.count) 件事")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                NavigationLink {
                    TimelineFullView(day: DayKey.of(Date()))
                } label: {
                    Text("全部")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
            }

            if app.todayItems.isEmpty {
                EmptyHint(text: app.todaySegments.isEmpty
                          ? "还没有录音。点上面的卡片开始，它会一直听着。"
                          : "有 \(app.todaySegments.count) 段录音，点「现在整理」把它们变成事件。")
                    .padding(.vertical, 10)
            } else {
                ForEach(app.todayItems.prefix(12)) { item in
                    EventRow(item: item) { app.toggleItem(item.id) }
                }
            }
        }
        .card()
    }

    // MARK: - 动作
    private func toggleCapture() {
        if capture.isRunning {
            capture.stop()
            UserDefaults.standard.set(false, forKey: "captureWanted")
        } else {
            capture.start()
            UserDefaults.standard.set(true, forKey: "captureWanted")
        }
    }

    private func shortDur(_ s: Double) -> String {
        let v = Int(s)
        if v < 60 { return "\(v)秒" }
        return "\(v / 60)分"
    }

    private func writeExport() -> URL? {
        let md = app.exportMarkdown(day: DayKey.of(Date()))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("涛声-\(DayKey.of(Date())).md")
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - 完整时间线
struct TimelineFullView: View {
    let day: String
    @EnvironmentObject var app: AppState
    @State private var asc = false
    @State private var onlyStar = false

    private var items: [DigestItem] {
        let base = day == DayKey.of(Date()) ? app.todayItems : app.dayItems
        return asc ? base.reversed() : base
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Chip(text: asc ? "早的在上" : "晚的在上", selected: true) { asc.toggle() }
                    Spacer()
                }
                if items.isEmpty {
                    EmptyHint(text: "这一天还没有整理出事件。").padding(.top, 40)
                } else {
                    ForEach(items) { item in
                        EventRow(item: item) { app.toggleItem(item.id) }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(DayKey.display(day))
        .navigationBarTitleDisplayMode(.inline)
    }
}
