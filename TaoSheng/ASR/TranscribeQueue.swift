import Foundation
import Combine

/// 转写队列：定时扫「已录音未转写」的段，串行送给转写服务，结果写回数据库。
/// 转写完顺手做热词纠错 + 声纹认人。
final class TranscribeQueue: ObservableObject {
    static let shared = TranscribeQueue()

    @Published private(set) var busy = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastMessage: String?

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

    func tick() {
        let s = Settings.shared
        guard s.autoTranscribe, s.asrReady else {
            refreshPending()
            return
        }
        let interval = Double(max(s.transcribeIntervalMin, 1)) * 60
        // 严格按用户设的间隔跑，不再「有待转写就每 30 秒一轮」
        guard Date().timeIntervalSince(lastRun) >= interval else {
            refreshPending()
            return
        }
        guard !working else { return }
        working = true
        busy = true
        lastRun = Date()

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
            let batch = Store.shared.pendingSegments(limit: 8)
                .filter { (self.failCount[$0.id] ?? 0) < 3 }
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

                    // 声纹认人
                    if !cleaned.isEmpty {
                        await TranscribeQueue.identifySpeaker(segmentId: seg.id, url: url)
                    }
                    await MainActor.run { self.lastMessage = "已转写 \(seg.timeText) 的 \(Int(seg.duration)) 秒" }
                    self.failCount.removeValue(forKey: seg.id)
                } catch {
                    Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                    self.failCount[seg.id, default: 0] += 1
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

    /// 用户手动触发一次
    func transcribeNow() {
        lastRun = .distantPast
        tick()
    }
}
