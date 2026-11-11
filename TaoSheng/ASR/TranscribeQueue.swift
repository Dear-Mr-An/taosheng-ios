import Foundation
import Combine

/// 转写队列：定时扫「已录音未转写」的段，串行送给转写服务，结果写回数据库。
final class TranscribeQueue: ObservableObject {
    static let shared = TranscribeQueue()

    @Published private(set) var busy = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastMessage: String?

    private var timer: Timer?
    private var working = false

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
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
        guard !working else { return }
        working = true
        busy = true

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
            let batch = Store.shared.pendingSegments(limit: 6)
            for seg in batch {
                if Task.isCancelled { return }
                let url = Store.audioDir.appendingPathComponent(seg.fileName)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                    continue
                }
                do {
                    let text = try await transcriber.transcribe(fileURL: url)
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.isEmpty {
                        // 静音段：标记完成但无文字，稍后由清理逻辑删除音频
                        Store.shared.updateTranscript(id: seg.id, transcript: "", state: .transcribed)
                    } else {
                        Store.shared.updateTranscript(id: seg.id, transcript: cleaned, state: .transcribed)
                    }
                    await MainActor.run { self.lastMessage = "已转写 \(seg.timeText) 的 \(Int(seg.duration)) 秒" }
                } catch {
                    Store.shared.updateTranscript(id: seg.id, transcript: "", state: .failed)
                    await MainActor.run { self.lastMessage = error.localizedDescription }
                    NSLog("涛声: 转写失败 \(error)")
                    // 一次失败就先歇一会，避免刷爆接口
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    func refreshPending() {
        let n = Store.shared.pendingSegments(limit: 999).count
        DispatchQueue.main.async { self.pendingCount = n }
    }

    /// 用户手动触发一次
    func transcribeNow() {
        working = false
        tick()
    }
}

extension Notification.Name {
    static let taoshengDataChanged = Notification.Name("taosheng.data.changed")
}
