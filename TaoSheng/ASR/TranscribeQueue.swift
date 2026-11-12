import Foundation
import Combine

/// 转写队列：定时扫「已录音未转写」的段，串行送给转写服务，结果写回数据库。
/// 转写完顺手做热词纠错 + 声纹认人。
final class TranscribeQueue: ObservableObject {
    static let shared = TranscribeQueue()

    @Published private(set) var busy = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastMessage: String?
    /// 上一轮转写开始的时间，界面用它算「约 N 分钟后下一轮」
    @Published private(set) var lastRunAt: Date?

    private var timer: Timer?
    private var working = false
    private var lastRun = Date.distantPast
    /// 同一段连续失败 3 次就不再自动重试，免得 Key 填错时一直烧请求
    private var failCount: [String: Int] = [:]

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick(manual: Bool = false) {
        let s = Settings.shared
        // 手动点「现在转写」时不受「自动转写」开关和间隔限制，
        // 否则关掉自动转写后按钮点了毫无反应，用户以为卡死。
        guard manual || s.autoTranscribe else {
            refreshPending()
            return
        }
        guard s.asrReady else {
            refreshPending()
            return
        }
        // 只在 WiFi 下转写：蜂窝/热点时不传，等连上 WiFi 再补
        guard manual || NetWatcher.shared.canUpload else {
            refreshPending()
            return
        }
        // 间隔由「多久转写一次」决定；实时档就是每 60 秒看一次
        let interval = Double(max(1, s.transcribeIntervalMin)) * 60
        guard manual || Date().timeIntervalSince(lastRun) >= interval else {
            refreshPending()
            return
        }
        guard !working else { return }
        working = true
        busy = true
        lastRun = Date()
        lastRunAt = Date()

        Task.detached(priority: .utility) {
            defer {
                Task { @MainActor in
                    self.working = false
                    self.busy = false
                    self.refreshPending()
                    NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
                }
            }

            guard let transcriber = TranscriberFactory.make() else { return }
            // Store 按最早录音排序并先 LIMIT；若只取 8 条再过滤失败项，
            // 队头 8 条都耗尽重试时，后续录音永远进不了转写批次。
            let batch = await MainActor.run {
                Array(Store.shared.pendingSegments(limit: Int.max)
                    .lazy.filter { (self.failCount[$0.id] ?? 0) < 3 }.prefix(8))
            }
            for seg in batch {
                if Task.isCancelled { return }
                let url = Store.audioDir.appendingPathComponent(seg.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                    continue
                }
                do {
                    let raw = try await transcriber.transcribe(fileURL: url)
                    var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        cleaned = HotwordFix.apply(cleaned)
                    }
                    Store.shared.updateTranscript(id: seg.id, transcript: cleaned, state: .transcribed)

                    // 使用录制时保存的模式，切换当前模式不改变旧录音的分人策略。
                    if !cleaned.isEmpty && Settings.shared.speakerSplitOn && seg.captureMode.separateSpeakers {
                        await TranscribeQueue.identifySpeaker(segmentId: seg.id, url: url)
                    }

                    // 环境音（本地启发式，只在打开时算）
                    if Settings.shared.envSoundOn, let tag = EnvSound.analyze(url: url) {
                        Store.shared.setEnvTag(segmentId: seg.id, tag: tag)
                    }
                    await MainActor.run { self.lastMessage = "已转写 \(seg.timeText) 的 \(Int(seg.duration)) 秒" }
                    _ = await MainActor.run { self.failCount.removeValue(forKey: seg.id) }
                } catch {
                    Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                    await MainActor.run { self.failCount[seg.id, default: 0] += 1 }
                    await MainActor.run { self.lastMessage = error.localizedDescription }
                    NSLog("涛声: 转写失败 \(error)")
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    /// 声纹比对：命中就写 speaker，没命中留空（用户可长按指定）
    static func identifySpeaker(segmentId: String, url: URL) async {
        let samples = Store.shared.allVoiceSamples()
        guard !samples.isEmpty else { return }
        guard let v = Voiceprint.vector(from: url) else { return }
        if let m = Voiceprint.match(v, samples: samples) {
            let persons = Store.shared.persons()
            if let p = persons.first(where: { $0.id == m.personId }) {
                Store.shared.setSpeaker(id: segmentId, speaker: p.name)
            }
        }
    }

    private func pendingCountImmediate() -> Bool {
        !Store.shared.pendingSegments(limit: 1).isEmpty
    }

    func refreshPending() {
        let n = Store.shared.pendingSegments(limit: 999).count
        DispatchQueue.main.async { self.pendingCount = n }
    }

    /// 用户手动触发一次：清掉失败计数，之前 3 次失败被判死的段也重试
    func transcribeNow() {
        failCount.removeAll()
        lastRun = .distantPast
        tick(manual: true)
    }

    /// 下一轮大约什么时候开始；没有待转写内容时为 nil
    var nextRunAt: Date? {
        guard pendingCount > 0 else { return nil }
        let base = lastRunAt ?? Date()
        let interval = Double(max(1, Settings.shared.transcribeIntervalMin)) * 60
        let next = base.addingTimeInterval(interval)
        return next > Date() ? next : Date()
    }
}
