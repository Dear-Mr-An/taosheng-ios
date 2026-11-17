import Foundation
import Combine
import CryptoKit

/// CAM++ 声纹模型的下载与校验（复用 0.8.3 SenseVoice 那套下载、校验、进度）。
///
/// 模型不随包带：28 MB 的权重放在运行时下载，和原版 Android 用的是同一份文件，
/// 字节数与 SHA-256 完全一致。没下载时 Voiceprint 回落到本机 48 维粗特征。
///
/// 不加 `@MainActor`：转写队列会在后台线程问「模型好了没」，
/// 界面状态统一由 `setPhase` 切回主线程写。
final class SpeakerModelStore: ObservableObject {
    static let shared = SpeakerModelStore()

    /// 与原版同源：HuggingFace 优先，hf-mirror 兜底（国内网络多试一次不亏）
    static let sources = [
        "https://huggingface.co/csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx",
        "https://hf-mirror.com/csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
    ]

    @Published private(set) var phase: SpeakerModelRules.Phase = .absent

    private let fm = FileManager.default
    private var task: URLSessionDownloadTask?
    /// 每次开始/取消/删除都 +1：旧的下载任务回来时凭这个数字判断自己是不是过期了，
    /// 否则「下载中就点了删除」，慢一步的 run() 还会把模型写回磁盘。
    private var generation = 0
    private var session: URLSession?
    private var running = false

    // MARK: 路径

    /// 转写与认人都在后台线程判断「有没有模型」，所以这层只用文件系统
    static var modelDir: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("voiceprint/campplus", isDirectory: true)
    }

    static var modelFile: URL { modelDir.appendingPathComponent("campplus.onnx") }

    static var readyOnDisk: Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelDir.appendingPathComponent(".verified").path) else { return false }
        let bytes = (try? fm.attributesOfItem(atPath: modelFile.path)[.size] as? Int64) ?? 0
        return SpeakerModelRules.isComplete(bytes: bytes)
    }

    var directory: URL {
        let d = Self.modelDir
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private var verifiedMark: URL { directory.appendingPathComponent(".verified") }
    var isReady: Bool { Self.readyOnDisk }

    private func fileSize(_ url: URL) -> Int64 {
        (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func setPhase(_ p: SpeakerModelRules.Phase) {
        if Thread.isMainThread {
            phase = p
        } else {
            DispatchQueue.main.async { self.phase = p }
        }
    }

    // MARK: 状态

    func refresh() {
        if isReady {
            setPhase(.ready)
            VoiceprintMigration.rebuildIfNeeded()
            return
        }
        if running { return }
        // 上次的失败原因留着：重进页面不该把「为什么没下成」清掉，
        // 用户再点一次「重试」才会重新开始。
        if case .failed = phase { return }
        setPhase(.absent)
    }

    // MARK: 下载

    func start() {
        guard !running else { return }
        if isReady { setPhase(.ready); return }
        let free = freeDiskSpace()
        guard SpeakerModelRules.enoughSpace(free: free) else {
            setPhase(.failed("空间不够，至少留 70 MB（现在 \(SpeakerModelRules.sizeText(free))）"))
            return
        }
        running = true
        generation += 1
        let gen = generation
        setPhase(.downloading(received: 0, total: Int64(SpeakerModelRules.modelBytes)))
        Task.detached(priority: .utility) { [weak self] in
            await self?.run(gen: gen)
        }
    }

    private func run(gen: Int) async {
        guard gen == generation else { return }
        _ = directory
        if SpeakerModelRules.isComplete(bytes: fileSize(Self.modelFile)), verify(at: Self.modelFile) {
            writeMark()
            running = false
            setPhase(.ready)
            VoiceprintMigration.rebuildIfNeeded()
            return
        }
        try? fm.removeItem(at: Self.modelFile)

        let tmp = fm.temporaryDirectory.appendingPathComponent("campplus-\(UUID().uuidString).onnx.part")
        if let reason = await downloadModel(to: tmp) {
            try? fm.removeItem(at: tmp)
            running = false
            setPhase(.failed(reason))
            return
        }
        guard gen == generation else {
            try? fm.removeItem(at: tmp)
            return
        }
        setPhase(.verifying)
        guard verify(at: tmp) else {
            try? fm.removeItem(at: tmp)
            running = false
            setPhase(.failed("文件校验不通过，请重试"))
            return
        }
        guard gen == generation else {
            try? fm.removeItem(at: tmp)
            return
        }
        do {
            try? fm.removeItem(at: Self.modelFile)
            try fm.moveItem(at: tmp, to: Self.modelFile)
            writeMark()
            running = false
            setPhase(.ready)
            VoiceprintMigration.rebuildIfNeeded()
        } catch {
            running = false
            setPhase(.failed(error.localizedDescription))
        }
    }

    private func writeMark() {
        try? SpeakerModelRules.modelSHA256.write(to: verifiedMark, atomically: true, encoding: .utf8)
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        running = false
        setPhase(isReady ? .ready : .absent)
    }

    func delete() {
        cancel()
        try? fm.removeItem(at: directory)
        // 权重不释放会一直占着 28 MB；维度换回去以后，旧的 192 维簇也已经比不了。
        Voiceprint.releaseEngine()
        Store.shared.clearStaleClusters(keepingDim: SpeakerModelRules.fallbackDim)
        setPhase(.absent)
    }

    // MARK: 下载

    private func downloadModel(to target: URL) async -> String? {
        for url in Self.sources {
            guard let u = URL(string: url) else { continue }
            let reason = await downloadOne(u, to: target)
            if reason == nil, fileSize(target) == Int64(SpeakerModelRules.modelBytes) { return nil }
            if reason == "已取消" { return reason }
        }
        return "模型没下完，检查网络后重试"
    }

    private func downloadOne(_ url: URL, to target: URL) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 60 * 10
            let delegate = ModelDownloadDelegate(
                target: target,
                progress: { [weak self] received, total in
                    let totalBytes = total > 0 ? total : Int64(SpeakerModelRules.modelBytes)
                    self?.setPhase(.downloading(received: received, total: totalBytes))
                },
                finish: { result in cont.resume(returning: result) }
            )
            let s = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
            self.session = s
            let t = s.downloadTask(with: url)
            self.task = t
            t.resume()
        }
    }

    // MARK: 校验

    private func verify(at url: URL) -> Bool {
        guard fileSize(url) == Int64(SpeakerModelRules.modelBytes) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return digest == SpeakerModelRules.modelSHA256
    }

    private func freeDiskSpace() -> Int64 {
        let v = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
