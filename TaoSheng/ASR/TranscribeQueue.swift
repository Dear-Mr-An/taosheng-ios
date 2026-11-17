import Foundation
import Combine

/// 转写队列：定时扫「已录音未转写」的段，串行送给转写服务，结果写回数据库。
/// 转写完顺手做热词纠错 + 声纹认人。
///
/// 状态（busy / pendingCount / lastMessage / failCount）全部在主线程序列化读写；
/// 数据库查询、音频读取、网络请求一律丢到后台，避免主线程卡顿。
@MainActor
final class TranscribeQueue: ObservableObject {
    // 单例本身无状态，谁都能拿到；它的可变状态仍然只在主线程读写
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

    /// 一轮最多循环多少次（每次 8 段）。正常一天几十段，40 轮足够；
    /// 设上限只是防止「一直转写失败又被反复捞出来」时死循环。
    nonisolated private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in TranscribeQueue.shared.tick() }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// manual = 手动点「现在转写」：跳过开关与间隔。会话不再有自己的「实时档」，
    /// 一切按设置里的「多久转写一次」走，转完一段就交给 DigestEngine 按需整理。
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
        // 只在 WiFi 下转写：蜂窝/热点时不传，等连上 WiFi 再补。
        // 本机识别（Apple Speech）不上传，离线也照跑，不受这条限制。
        let offlineOK = !ASRRules.needsNetwork(kind: s.asrKind.rawValue)
        guard manual || offlineOK || NetWatcher.shared.canUpload else {
            refreshPending()
            return
        }
        // 间隔由「多久转写一次」决定
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
            // 这一轮有没有转到新文字：有就顺手让整理跟上（设置里选「转写完就整理」时）
            var produced = false
            defer {
                let hadNewText = produced
                Task { @MainActor in
                    self.working = false
                    self.busy = false
                    self.refreshPending()
                    NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
                    DigestEngine.shared.afterTranscribeRound(newText: hadNewText)
                }
            }

            guard let transcriber = TranscriberFactory.make() else { return }

            // 一直转到队列清空：以前一轮只处理 8 段，开会一下午攒下几十段时
            // 用户要等好几轮才能看到文字。现在同一次唤醒里连续处理。
            for _ in 0 ..< 40 {
                if Task.isCancelled { return }

                let pending = Store.shared.pendingSegments(limit: 999)
                // 失败 3 次的段不再自动重试（手动「现在转写」会清空计数）
                let blocked = await MainActor.run {
                    Set(self.failCount.filter { $0.value >= 3 }.keys)
                }
                let batch = Array(
                    pending.lazy
                        .filter { !blocked.contains($0.id) }
                        .prefix(8)
                )
                if batch.isEmpty { return }

                var didWork = false
                for seg in batch {
                    if Task.isCancelled { return }
                    let url = Store.audioDir.appendingPathComponent(seg.fileName)
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        // 音频文件被系统清理或用户删掉了：直接判死，不要每次唤醒都重试
                        Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                        await MainActor.run { self.failCount[seg.id] = 3 }
                        didWork = true
                        continue
                    }
                    do {
                        let result = try await transcriber.transcribe(fileURL: url)
                        var cleaned = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            cleaned = HotwordFix.apply(cleaned)
                        }
                        Store.shared.updateTranscript(id: seg.id, transcript: cleaned, state: .transcribed)
                        if !cleaned.isEmpty { produced = true }

                        // 使用录制时保存的模式，切换当前模式不改变旧录音的分人策略。
                        if !cleaned.isEmpty && Settings.shared.speakerSplitOn && seg.captureMode.separateSpeakers {
                            await TranscribeQueue.identifySpeaker(segmentId: seg.id, url: url)
                        }

                        // 环境音（本地启发式，只在打开时算）
                        if Settings.shared.envSoundOn, let tag = EnvSound.analyze(url: url) {
                            Store.shared.setEnvTag(segmentId: seg.id, tag: tag)
                        }
                        await MainActor.run { self.lastMessage = "已转写 \(seg.timeText) 的 \(Int(seg.duration)) 秒" }
                        await MainActor.run { _ = self.failCount.removeValue(forKey: seg.id) }
                        didWork = true
                    } catch {
                        Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                        await MainActor.run { self.failCount[seg.id, default: 0] += 1 }
                        await MainActor.run { self.lastMessage = error.localizedDescription }
                        NSLog("涛声: 转写失败 \(error)")
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        didWork = true
                    }
                }
                if !didWork { return }
            }
        }
    }

    /// 声纹比对：先认熟人；认不出就按未知说话人簇给「说话人 1 / 2 / 3 …」，
    /// 新声音自动开一个新簇，这样多人会议里每个人都能拿到稳定的编号。
    /// 簇不再按天分桶：原版（Android `SpeakerIdentity`）的人物库是全局的，
    /// 按天分桶会让同一个人每天重新变成「说话人 1」，跨天对不上。
    nonisolated static func identifySpeaker(segmentId: String, url: URL) async {
        // 太短的段天空纹并不可靠：背景噪声、半个字都会被算成一个人。
        guard let seg = Store.shared.segment(id: segmentId), seg.duration >= 1.5 else { return }
        guard let v = Voiceprint.vector(from: url) else { return }
        let clusterKey = "all"

        let samples = Store.shared.allVoiceSamples()
        if !samples.isEmpty, let m = Voiceprint.match(v, samples: samples),
           let p = Store.shared.persons().first(where: { $0.id == m.personId }) {
            Store.shared.setSpeaker(id: segmentId, speaker: p.name)
            return
        }

        var bestNo = 0
        // 初值 -1：相似度全为负时也要能选出「最像的那个已有人」，否则每段都新开簇、编号爆炸
        var bestScore = -1.0
        for c in Store.shared.clusters(day: clusterKey) where c.vector.count == v.count {
            let score = Voiceprint.cosine(v, c.vector)
            if score > bestScore { bestScore = score; bestNo = c.no }
        }
        if bestNo > 0 && bestScore >= Voiceprint.clusterThreshold(for: v) {
            Store.shared.setSpeaker(id: segmentId, speaker: "说话人\(bestNo)")
            Store.shared.updateCluster(day: clusterKey, no: bestNo, vector: v)
        } else {
            let no = Store.shared.nextClusterNo(day: clusterKey)
            Store.shared.insertCluster(day: clusterKey, no: no, vector: v)
            Store.shared.setSpeaker(id: segmentId, speaker: "说话人\(no)")
        }
    }

    /// 待转写数量：数据库查询丢后台，回主线程只改一个 Int
    nonisolated func refreshPending() {
        DispatchQueue.global(qos: .utility).async {
            let n = Store.shared.pendingSegments(limit: 999).count
            Task { @MainActor in
                let q = TranscribeQueue.shared
                if q.pendingCount != n { q.pendingCount = n }
            }
        }
    }

    /// 用户手动触发一次：清掉失败计数，之前 3 次失败被判死的段也重试
    func transcribeNow() {
        failCount.removeAll()
        lastRun = .distantPast
        tick(manual: true)
    }

    /// 下一轮大约什么时候开始；没有待转写内容、或现在压根传不出去（没网 / 只等 WiFi）时为 nil，
    /// 界面就不会写出「约 0 分钟后下一轮」这种自己都不会发生的时刻。
    var nextRunAt: Date? {
        let offlineOK = !ASRRules.needsNetwork(kind: Settings.shared.asrKind.rawValue)
        guard pendingCount > 0, offlineOK || NetWatcher.shared.canUpload else { return nil }
        let base = lastRunAt ?? Date()
        let interval = Double(max(1, Settings.shared.transcribeIntervalMin)) * 60
        let next = base.addingTimeInterval(interval)
        return next > Date() ? next : Date()
    }
}
