import Foundation
import Speech
import AVFoundation

/// 轻量语音输入：按住说话，松手出文字。
/// 只用于「添加待办」这类短句输入，不做切片、不落盘。
final class QuickSpeech: ObservableObject {
    static let shared = QuickSpeech()

    @Published private(set) var running = false
    @Published private(set) var text = ""
    @Published private(set) var level: Double = 0
    @Published private(set) var hint: String?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var starting = false

    private init() {}

    // MARK: - 开始

    func start() async {
        guard !running, !starting else { return }
        starting = true
        defer { starting = false }

        guard await Self.ensureSpeechAuth() else {
            await MainActor.run { self.hint = "没有语音识别权限，去 设置 → 涛声 打开" }
            return
        }
        guard await Self.ensureMicAuth() else {
            await MainActor.run { self.hint = "没有麦克风权限，去 设置 → 涛声 打开" }
            return
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), rec.isAvailable else {
            await MainActor.run { self.hint = "这台设备的语音识别暂时不可用" }
            return
        }

        await MainActor.run {
            self.text = ""
            self.hint = nil
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }

            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                req.append(buf)
                self?.measure(buf)
            }

            self.engine = engine
            self.request = req

            engine.prepare()
            try engine.start()

            task = rec.recognitionTask(with: req) { [weak self] result, _ in
                guard let self = self, let r = result else { return }
                let s = r.bestTranscription.formattedString
                DispatchQueue.main.async { self.text = s }
            }

            await MainActor.run { self.running = true }
        } catch {
            stop()
            await MainActor.run { self.hint = "录音打不开：\(error.localizedDescription)" }
        }
    }

    // MARK: - 停止

    @discardableResult
    func stop() -> String {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        running = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 内部

    private func measure(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData?[0] else { return }
        let n = Int(buf.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n {
            let v = ch[i]
            sum += v * v
        }
        let rms = sqrt(sum / Float(n))
        let v = Double(min(1, rms * 14))
        DispatchQueue.main.async { self.level = v }
    }

    static func ensureSpeechAuth() async -> Bool {
        let st = SFSpeechRecognizer.authorizationStatus()
        if st == .authorized { return true }
        if st == .denied || st == .restricted { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                c.resume(returning: SFSpeechRecognizer.authorizationStatus() == .authorized)
            }
        }
    }

    static func ensureMicAuth() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .granted { return true }
        if session.recordPermission == .denied { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            session.requestRecordPermission { ok in c.resume(returning: ok) }
        }
    }
}
