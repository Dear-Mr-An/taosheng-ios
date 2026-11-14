import SwiftUI

/// 「转写与原话」：只看转写状态和今天的原话。
/// 整理相关的大模型、整理时机在 `LLMSettingsView`，两页分开，原话再多也挤不掉整理设置。
struct TranscribeOverviewView: View {
    @EnvironmentObject var settings: Settings
    @ObservedObject private var queue = TranscribeQueue.shared

    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exporting = false
    @State private var showImport = false
    @State private var showKeepDays = false
    @State private var stats = Stats()
    @State private var showTranscribe = false
    @State private var todaySegments: [Segment] = []
    @State private var purgeTip = ""

    private struct Stats {
        var todayMinutes: Double = 0
        var monthMinutes: Double = 0
        var bytes: Int64 = 0
        var total: Int = 0
        var done: Int = 0
    }

    /// 卡片里只列最近 3 段，其余进原话页
    private static let previewLimit = 3

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.sp3) {
                statusCard
                rawLinesCard
            }
            .padding(Theme.sp4)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tabBarClearance()
        .navigationTitle("转写与原话")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTranscribe) {
            TranscribeSettingsSheet()
                .environmentObject(settings)
        }
        .onAppear { reload() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
        .sheet(isPresented: Binding(get: { exportURL != nil },
                                    set: { if !$0 { exportURL = nil } })) {
            if let u = exportURL { ShareSheet(items: [u]) }
        }
        .sheet(isPresented: $showKeepDays) {
            keepDaysSheet
        }
        .fileImporter(isPresented: $showImport,
                      allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task {
                    let msg = await ImportEngine.shared.importFiles(urls)
                    await MainActor.run { exportError = msg; reload() }
                }
            }
        }
        .alert("提示", isPresented: Binding(get: { exportError != nil },
                                            set: { if !$0 { exportError = nil } })) {
            Button("好") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(queue.pendingCount > 0 ? Theme.warn : (settings.asrReady ? Theme.ok : Theme.dim2))
                    .frame(width: 9, height: 9)
                    .offset(y: -1)
                Text(statusTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 0)
                Button { showTranscribe = true } label: {
                    Text("转写设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            Text(statusLine)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.dim)
                .padding(.top, 6)

            HStack(spacing: 10) {
                Button {
                    queue.transcribeNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { reload() }
                } label: {
                    Text(queue.busy ? "转写中…" : "现在转写")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(queue.busy || !settings.asrReady)

                Button { showImport = true } label: {
                    Text("导入录音")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.accentSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)

            Divider().overlay(Theme.lineSoft).padding(.vertical, 12)

            statRow("云端转写", cloudLine) { exportError = cloudDetail }
            Divider().overlay(Theme.lineSoft)
            statRow("原声", audioLine) { showKeepDays = true }
            Divider().overlay(Theme.lineSoft)
            statRow("录音包", exporting ? "正在打包…" : "打包导出原始录音") { exportAudio() }

            HStack {
                Text("录音原话")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)
                Spacer()
                Text("\(stats.total) 段 · 已转 \(stats.done)")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text2)
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var statusTitle: String {
        if queue.busy { return "正在转写" }
        if !settings.asrReady { return "转写尚未就绪" }
        if queue.pendingCount > 0 { return "还有 \(queue.pendingCount) 段待转写" }
        return "都转完了"
    }

    private var statusLine: String {
        if !settings.asrReady { return settings.asrReadyHint }
        var parts: [String] = []
        if let last = queue.lastRunAt {
            parts.append("上次 \(Self.timeText(last))")
        } else {
            parts.append("还没转过")
        }
        if let next = queue.nextRunAt {
            let m = max(1, Int(next.timeIntervalSinceNow / 60))
            parts.append("约 \(m) 分钟后下一轮")
        } else {
            parts.append("有新的原话就自动转")
        }
        return parts.joined(separator: " · ")
    }

    private var cloudLine: String {
        let today = Self.minutesText(stats.todayMinutes)
        let month = Self.minutesText(stats.monthMinutes)
        if stats.monthMinutes <= 0 { return "今天 0 分 · 30 天 0 分" }
        return "今天 \(today) · 30 天 \(month) · ≈¥\(Self.cost(stats.monthMinutes))"
    }

    private var cloudDetail: String {
        "云端转写按分钟计费，豆包录音文件识别约 ¥0.8/小时。\n今天 \(Self.minutesText(stats.todayMinutes))，近 30 天 \(Self.minutesText(stats.monthMinutes))，估算 ¥\(Self.cost(stats.monthMinutes))。\n只有转写时才会把录音发出去。"
    }

    private var audioLine: String {
        "\(settings.keepAudioDays) 天 · 重点长期保留 · \(ByteText.short(stats.bytes))"
    }

    private func statRow(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)
                    .frame(width: 58, alignment: .leading)
                Text(value)
                    .font(.system(size: 13.5))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.dim2)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 今天的原话（最多 3 段）

    private var rawLinesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天的原话")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(todaySegments.count) 段")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dim)
            }

            if todaySegments.isEmpty {
                Text("今天还没有录到原话。回「今天」页点「开始聆听」。")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 最新的在前：卡片空间有限，只放最新 3 段，其余进原话页
                ForEach(Array(todaySegments.prefix(Self.previewLimit).enumerated()), id: \.element.id) { _, s in
                    SegmentRow(seg: s,
                               starred: Store.shared.isStarred(id: s.id),
                               onPlay: { SegmentPlayer.shared.toggle(segment: s) },
                               onStar: {
                                   Store.shared.setStar(id: s.id, starred: !Store.shared.isStarred(id: s.id))
                                   Task { await reloadAsync() }
                               })
                }
                NavigationLink {
                    RawLinesView(day: DayKey.of(Date()))
                } label: {
                    HStack(spacing: 4) {
                        Text(todaySegments.count > Self.previewLimit
                             ? "看全部 \(todaySegments.count) 段"
                             : "打开原话页")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .tapTarget(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    // MARK: 工具

    private var keepDaysSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("原声保留 \(settings.keepAudioDays) 天")
                    .font(.system(size: 18, weight: .semibold))
                Stepper("保留天数", value: $settings.keepAudioDays, in: 1...365)
                Text("标了重点的录音长期保留。现在占用 \(ByteText.short(stats.bytes))。")
                    .font(.system(size: 12)).foregroundColor(Theme.dim)
                Button {
                    Task {
                        let n = await AppState.shared.purgeOldAudio()
                        await MainActor.run {
                            reload()
                            purgeTip = n > 0 ? "已清理 \(n) 段原声，转写文字和整理结果都还在" : "没有需要清理的原声"
                        }
                    }
                } label: {
                    Text("立即清理过期录音")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if !purgeTip.isEmpty {
                    Text(purgeTip)
                        .font(.system(size: Theme.fsSmall))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("原声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { showKeepDays = false } } }
        }
    }

    private func reload() {
        Task { await reloadAsync() }
    }

    /// 6 次查询全部放到后台：以前每 5 秒在主线程同步跑一遍，停留在这页会持续掉帧
    private func reloadAsync() async {
        struct Snap { let today: Double; let month: Double; let bytes: Int64; let total: Int; let done: Int; let segs: [Segment] }
        let snap = await Task.detached(priority: .utility) { () -> Snap in
            let p = Store.shared.todayTranscribeProgress()
            return Snap(today: Store.shared.transcribedMinutes(days: 0),
                        month: Store.shared.transcribedMinutes(days: 30),
                        bytes: Store.shared.audioBytes(),
                        total: p.total,
                        done: p.done,
                        segs: Store.shared.segments(day: DayKey.of(Date()), limit: 200))
        }.value
        stats = Stats(todayMinutes: snap.today, monthMinutes: snap.month, bytes: snap.bytes, total: snap.total, done: snap.done)
        todaySegments = snap.segs
        queue.refreshPending()
    }

    private func exportAudio() {
        guard !exporting else { return }
        exportError = nil
        exporting = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                do { return .success(try AudioExport.zipAudio()) }
                catch { return .failure(error) }
            }.value
            await MainActor.run {
                exporting = false
                switch outcome {
                case .success(let u): exportURL = u
                case .failure(let e): exportError = e.localizedDescription
                }
            }
        }
    }

    private static func minutesText(_ m: Double) -> String {
        if m < 1 { return "\(Int((m * 60).rounded())) 秒" }
        if m < 60 { return "\(Int(m.rounded())) 分" }
        return String(format: "%.1f 小时", m / 60)
    }

    private static func cost(_ minutes: Double) -> String {
        // 豆包录音文件识别极速版约 ¥0.8/小时
        String(format: "%.2f", minutes / 60 * 0.8)
    }

    private static func timeText(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? Fmt.df("'今天' HH:mm").string(from: d)
            : Fmt.monthDayTime.string(from: d)
    }
}
