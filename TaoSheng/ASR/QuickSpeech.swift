import Foundation
import Combine
import Speech
import AVFoundation

/// 短语音独占麦克风；权限等待、识别回调及取消均绑定同一会话。
@MainActor
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
    private var sessionState = VoiceSessionState()
    private var ownsAudioSession = false
    private var resumeCapture = false
    private var activeToken: UInt64?
    private var finishContinuation: CheckedContinuation<String, Never>?
    private var finishTimeout: Task<Void, Never>?

    private init() {}

    func start() async {
        guard !Task.isCancelled, !running, !starting, finishContinuation == nil else { return }
        let token = sessionState.begin()
        activeToken = token
        starting = true
        text = ""
        hint = nil
        defer { if sessionState.isCurrent(token) { starting = false } }

        let speechAllowed = await Self.ensureSpeechAuth()
        guard sessionState.isCurrent(token), !Task.isCancelled else { return }
        guard speechAllowed else {
            hint = "没有语音识别权限，去 设置 → 涛声 打开"
            return
        }
        let micAllowed = await Self.ensureMicAuth()
        guard sessionState.isCurrent(token), !Task.isCancelled else { return }
        guard micAllowed else {
            hint = "没有麦克风权限，去 设置 → 涛声 打开"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            hint = "这台设备的语音识别暂时不可用"
            return
        }

        // 在授权完成后才暂停全天收音，权限失败不会影响原采集。
        resumeCapture = CaptureEngine.shared.isRunning || UserDefaults.standard.bool(forKey: "captureWanted")
        CaptureEngine.shared.suspendForVoiceInput()
        SegmentPlayer.shared.stop()
        do {
            let session = AVAudioSession.sharedInstance()
            ownsAudioSession = true
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "QuickSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可用的麦克风"])
            }
            self.engine = engine
            self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += channel[i] * channel[i] }
                let value = Double(min(1, sqrt(sum / Float(buffer.frameLength)) * 14))
                Task { @MainActor [weak self] in
                    guard let self, self.sessionState.isCurrent(token) else { return }
                    self.level = value
                }
            }
            engine.prepare()
            try engine.start()
            running = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let recognized = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.sessionState.isCurrent(token) else { return }
                    if let recognized { self.text = recognized }
                    if failed || final {
                        if failed && self.text.isEmpty { self.hint = "语音识别中断，请重试" }
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
            hint = "录音打不开：\(error.localizedDescription)"
        }
    }

    /// 松手停止收音，但让识别器收完尾字；最终回调或超时后才提交草稿。
    func finish() async -> String {
        guard running, let token = activeToken, sessionState.isCurrent(token), !Task.isCancelled else {
            return stop()
        }
        guard finishContinuation == nil else { return "" }
        stopMicrophone()
        request?.endAudio()
        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            finishTimeout = Task { @MainActor [weak self] in
                // 松手后识别器还要把最后几个字收完，1.5 秒经常截掉半句
                do { try await Task.sleep(nanoseconds: 2_200_000_000) }
                catch { return }
                guard let self, self.sessionState.isCurrent(token) else { return }
                self.stop()
            }
        }
    }

    private func stopMicrophone() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        level = 0
    }

    @discardableResult
    func stop(discardText: Bool = false) -> String {
        sessionState.cancel()
        activeToken = nil
        starting = false
        finishTimeout?.cancel()
        finishTimeout = nil
        stopMicrophone()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        running = false
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
            let shouldResume = resumeCapture && UserDefaults.standard.bool(forKey: "captureWanted")
            resumeCapture = false
            CaptureEngine.shared.resumeAfterVoiceInput(shouldResume: shouldResume)
        }
        if discardText { text = ""; hint = nil }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(returning: result)
        return result
    }

    static func ensureSpeechAuth() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func ensureMicAuth() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .granted { return true }
        if session.recordPermission == .denied { return false }
        return await withCheckedContinuation { continuation in
            session.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
