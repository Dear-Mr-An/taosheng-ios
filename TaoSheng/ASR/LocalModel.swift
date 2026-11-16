import Foundation
import CryptoKit
import AVFoundation

/// 本地 SenseVoice 模型的下载与校验。
///
/// Android 原版是下 `.tar.bz2` 再解包；iOS 没有系统 tar/bz2，改成直接下模型与
/// tokens 两个文件，字节数与 SHA-256 和原版 `LocalModels.cpu` 完全一致，
/// 校验通过才换进正式目录，失败不覆盖旧文件。
///
/// 这里不加 `@MainActor`：转写队列会在后台线程问「模型好了没」，
/// 界面状态统一由 `setPhase` 切回主线程写。
final class LocalModelStore: ObservableObject {
    static let shared = LocalModelStore()

    /// HuggingFace 直链实测 200 且长度对得上（239 233 841 B / 315 894 B）；
    /// hf-mirror 目前对这两个文件是 308 跳回原站（没有真正镜像），所以放第二个兜底，
    /// URLSession 会自己跟随 308，国内网络下多试一次也不亏。
    static let modelSources = [
        "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx",
        "https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx"
    ]
    static let tokensSources = [
        "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt",
        "https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt"
    ]

    @Published private(set) var phase: LocalModelRules.Phase = .absent

    private let fm = FileManager.default
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var running = false

    // MARK: 路径

    /// 转写队列在后台线程判断「能不能离网转写」，所以这层只用文件系统
    static var modelDir: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("asr-models/sense-voice", isDirectory: true)
    }

    static var modelFile: URL { modelDir.appendingPathComponent("model.int8.onnx") }
    static var tokensFile: URL { modelDir.appendingPathComponent("tokens.txt") }

    static var readyOnDisk: Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelDir.appendingPathComponent(".verified").path) else { return false }
        let m = (try? fm.attributesOfItem(atPath: modelFile.path)[.size] as? Int64) ?? 0
        let t = (try? fm.attributesOfItem(atPath: tokensFile.path)[.size] as? Int64) ?? 0
        return LocalModelRules.isComplete(modelBytes: m, tokensBytes: t)
    }

    var directory: URL {
        let d = Self.modelDir
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    var modelURL: URL { Self.modelFile }
    var tokensURL: URL { Self.tokensFile }
    private var verifiedMark: URL { directory.appendingPathComponent(".verified") }

    var isReady: Bool { Self.readyOnDisk }

    private func fileSize(_ url: URL) -> Int64 {
        (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func setPhase(_ p: LocalModelRules.Phase) {
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
            return
        }
        if running { return }
        setPhase(.absent)
    }

    // MARK: 下载

    func start() {
        guard !running else { return }
        if isReady { setPhase(.ready); return }
        let free = freeDiskSpace()
        guard LocalModelRules.enoughSpace(free: free) else {
            setPhase(.failed("空间不够，至少留 300 MB（现在 \(LocalModelRules.sizeText(free))）"))
            return
        }
        running = true
        setPhase(.downloading(received: 0, total: Int64(LocalModelRules.modelBytes)))
        Task.detached(priority: .utility) { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        _ = directory
        if fileSize(tokensURL) < LocalModelRules.tokensRange.lowerBound {
            if let reason = await downloadTokens() {
                running = false
                setPhase(.failed(reason))
                return
            }
        }
        if fileSize(modelURL) == Int64(LocalModelRules.modelBytes), verify(at: modelURL) {
            writeMark()
            running = false
            setPhase(.ready)
            return
        }
        try? fm.removeItem(at: modelURL)

        let tmp = fm.temporaryDirectory.appendingPathComponent("sense-voice-\(UUID().uuidString).onnx.part")
        if let reason = await downloadModel(to: tmp) {
            try? fm.removeItem(at: tmp)
            running = false
            setPhase(.failed(reason))
            return
        }
        setPhase(.verifying)
        guard verify(at: tmp) else {
            try? fm.removeItem(at: tmp)
            running = false
            setPhase(.failed("文件校验不通过，请重试"))
            return
        }
        do {
            try? fm.removeItem(at: modelURL)
            try fm.moveItem(at: tmp, to: modelURL)
            writeMark()
            running = false
            setPhase(.ready)
        } catch {
            running = false
            setPhase(.failed(error.localizedDescription))
        }
    }

    private func writeMark() {
        try? LocalModelRules.modelSHA256.write(to: verifiedMark, atomically: true, encoding: .utf8)
    }

    func cancel() {
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
        setPhase(.absent)
    }

    // MARK: 下载两个文件

    private func downloadTokens() async -> String? {
        for url in Self.tokensSources {
            guard let u = URL(string: url) else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: u)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                guard LocalModelRules.tokensRange.contains(Int64(data.count)) else { continue }
                try data.write(to: tokensURL)
                return nil
            } catch {
                continue
            }
        }
        return "tokens.txt 没下下来，检查网络后重试"
    }

    private func downloadModel(to target: URL) async -> String? {
        for url in Self.modelSources {
            guard let u = URL(string: url) else { continue }
            let reason = await downloadOne(u, to: target)
            if reason == nil, fileSize(target) == Int64(LocalModelRules.modelBytes) { return nil }
            if reason == "已取消" { return reason }
        }
        return "模型没下完，检查网络后重试"
    }

    private func downloadOne(_ url: URL, to target: URL) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 60 * 30
            let delegate = DownloadDelegate(
                target: target,
                progress: { [weak self] received, total in
                    let totalBytes = total > 0 ? total : Int64(LocalModelRules.modelBytes)
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
        guard fileSize(url) == Int64(LocalModelRules.modelBytes) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return digest == LocalModelRules.modelSHA256
    }

    private func freeDiskSpace() -> Int64 {
        let v = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

/// 下载回调只在这里转成「进度 / 结果」，不直接碰界面状态
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let target: URL
    private let progress: (Int64, Int64) -> Void
    private let finish: (String?) -> Void
    private var done = false

    init(target: URL, progress: @escaping (Int64, Int64) -> Void, finish: @escaping (String?) -> Void) {
        self.target = target
        self.progress = progress
        self.finish = finish
    }

    private func complete(_ reason: String?) {
        guard !done else { return }
        done = true
        finish(reason)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            complete("服务器返回 \( (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1)")
            return
        }
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
            complete(nil)
        } catch {
            complete(error.localizedDescription)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        complete(ns.code == NSURLErrorCancelled ? "已取消" : error.localizedDescription)
    }
}
