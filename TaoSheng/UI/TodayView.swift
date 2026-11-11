import SwiftUI

struct TodayView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var capture: CaptureEngine
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var digest: DigestEngine
    @EnvironmentObject var queue: TranscribeQueue

    @State private var showSettingsHint = false

    private var today: String { DayKey.of(Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    captureCard
                    if let e = capture.lastError {
                        Text(e)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    digestCard
                    timelineSection
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("今天")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Circle().fill(capture.isRunning ? Theme.ok : Theme.dim)
                            .frame(width: 7, height: 7)
                        Text(capture.isRunning ? "在听" : "已停")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .refreshable { app.refresh() }
        }
    }

    // MARK: - 采集卡

    private var captureCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Date(), format: .dateTime.month().day().weekday(.wide))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                    Text(capture.isRunning
                         ? (capture.isSpeaking ? "有人在说话，正在录" : "安静，等着")
                         : "没有在录")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(hm(app.stats.seconds))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("今日人声")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }
            }

            LevelBars(level: capture.level, active: capture.isRunning)

            HStack(spacing: 10) {
                Button {
                    if capture.isRunning {
                        capture.stop()
                        UserDefaults.standard.set(false, forKey: "captureWanted")
                    } else {
                        capture.start()
                        UserDefaults.standard.set(true, forKey: "captureWanted")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: capture.isRunning ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 18))
                        Text(capture.isRunning ? "停止收音" : "开始收音")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(capture.isRunning ? Theme.cardHi : Theme.accent)
                    .foregroundStyle(capture.isRunning ? Theme.text : Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if app.stats.pending > 0 {
                    Button {
                        queue.transcribeNow()
                    } label: {
                        VStack(spacing: 1) {
                            Text("\(app.stats.pending)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("待转写")
                                .font(.system(size: 9))
                        }
                        .frame(width: 62)
                        .padding(.vertical, 8)
                        .background(Theme.accentSoft)
                        .foregroundStyle(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(padding: 16)
    }

    // MARK: - 整理卡

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI 整理")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
                if digest.running {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        digest.digest(day: today)
                    } label: {
                        Text(app.todayItems.isEmpty ? "整理今天" : "重新整理")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !app.todaySummary.isEmpty {
                Text(app.todaySummary)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if app.todayItems.isEmpty {
                Text(settings.llmReady
                     ? "还没整理。今天说的话会在整理后变成事件、待办和约定。"
                     : "先在设置里填好整理模型（比如 DeepSeek），这里就能把原话变成待办和约定。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let preview = app.todayItems.filter { $0.kind != .event }.prefix(4)
                if preview.isEmpty {
                    Text("今天只有事件记录，没有待办。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                } else {
                    ForEach(Array(preview)) { item in
                        ItemRow(item: item) { app.toggleItem(item) }
                        if item.id != preview.last?.id { Divider().overlay(Theme.line) }
                    }
                }
                if let err = digest.lastError {
                    Text(err).font(.system(size: 11)).foregroundStyle(Theme.bad)
                }
            }
        }
        .card(padding: 14)
    }

    // MARK: - 时间线

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "时间线", trailing: "\(app.todaySegments.count) 段")

            if app.todaySegments.isEmpty {
                EmptyHint(symbol: "waveform.slash",
                          title: "今天还没有录到人声",
                          detail: "打开上面的「开始收音」，把手机放在身边就行。\n只有有人说话时才录，安静时不耗电。")
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(app.todaySegments) { seg in
                        SegmentRow(segment: seg)
                        if seg.id != app.todaySegments.last?.id {
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .card(padding: 12)
            }
        }
    }

    private func hm(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)秒" }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)时\(m)分" : "\(m)分"
    }
}
