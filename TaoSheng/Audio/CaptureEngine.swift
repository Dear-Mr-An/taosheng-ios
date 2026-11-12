import Foundation
import Combine
import AVFoundation

/// 采集引擎：AVAudioEngine 常驻 tap → 能量 VAD 判断人声 → 有人的片段落成 wav 文件。
/// 后台靠 Info.plist 的 audio 后台模式 + 常驻音频会话维持（自签安装下可用）。
final class CaptureEngine: ObservableObject {
    static let shared = CaptureEngine()

    @Published private(set) var isRunning = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var level: Double = 0          // 0...1，给 UI 的波形
    @Published private(set) var isSpeaking = false
    @Published private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var segmentStart: Date?
    private var lastVoiceAt: Date?
    private var silentFrames = 0
    private var wroteAnyVoice = false
    private var isStarting = false
    private var suspendedForVoice = false
    private var generation: UInt64 = 0

    private let queue = DispatchQueue(label: "app.taosheng.capture")
    // 只在 queue 上访问；停止时先排空旧回调再结算最后一段。
    private var acceptingBuffers = false
    private var bufferGeneration: UInt64 = 0
    private var recordingMode: CaptureMode = .daily
    private var minimumDuration: Double = 2

    /// 落盘参数：16kHz / 16bit / 单声道 PCM WAV —— 云转写（豆包、Whisper）都认这个。
    /// 硬件原始格式是 48kHz float32，直接按它写 WAV 会变成 IEEE float，很多服务拒收。
    private let fileSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    /// AVAudioFile 的写入格式（由文件对象给出，通常是 float32），转换目标以它为准。
    private var writeFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterRate: Double = 0
    private var converterChannels: AVAudioChannelCount = 0

    var onSegmentSaved: ((Segment) -> Void)?

    private init() {}

    /// 是否处于「夜里不录」时段
    static func inSilenceWindow() -> Bool {
        let s = Settings.shared
        guard s.silenceWindowOn else { return false }
        let a = s.silenceStartHour, b = s.silenceEndHour
        if a == b { return false }
        let h = Calendar.current.component(.hour, from: Date())
        if a < b { return h >= a && h < b }
        return h >= a || h < b
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning, !isStarting, !suspendedForVoice else { return }
        if CaptureEngine.inSilenceWindow() {
            let s = Settings.shared
            lastError = "现在是停录时段（\(s.silenceStartHour) 点 — \(s.silenceEndHour) 点），可在 设置 → 录音与后台 里改。"
            return
        }
        lastError = nil
        isStarting = true
        generation &+= 1
        let token = generation
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async {
                guard self.generation == token, !self.suspendedForVoice else { return }
                self.isStarting = false
                guard ok else {
                    self.lastError = "没有麦克风权限，请到 设置 → 涛声 打开。"
                    return
                }
                self.startSessionAndEngine()
            }
        }
    }

    private func startSessionAndEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: [])

            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                lastError = "没有可用的麦克风输入。"
                return
            }

            let mode = Settings.shared.captureMode
            let threshold = mode.sensitivity(Settings.shared.sensitivity)
            let minimum = Settings.shared.minSegment
            let bufferToken = queue.sync { () -> UInt64 in
                self.acceptingBuffers = true
                self.bufferGeneration &+= 1
                self.recordingMode = mode
                self.minimumDuration = minimum
                self.lastVoiceAt = nil
                return self.bufferGeneration
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.handle(buffer: buffer, format: format, mode: mode, threshold: threshold, token: bufferToken)
            }

            engine.prepare()
            try engine.start()
            isRunning = true
            startedAt = Date()
            lastError = nil
            NSLog("涛声: 采集已启动 \(format.sampleRate)Hz \(format.channelCount)ch")
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            queue.sync { self.acceptingBuffers = false; self.closeSegment(force: true) }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            lastError = "启动录音失败：\(error.localizedDescription)"
            NSLog("涛声: 启动失败 \(error)")
        }
    }

    func stop() {
        generation &+= 1
        isStarting = false
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.sync {
            self.acceptingBuffers = false
            self.closeSegment(force: true)
            self.converter = nil
            self.writeFormat = nil
            self.lastVoiceAt = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
        startedAt = nil
        isSpeaking = false
        level = 0
    }

    func suspendForVoiceInput() {
        suspendedForVoice = true
        stop()
    }

    func resumeAfterVoiceInput(shouldResume: Bool) {
        suspendedForVoice = false
        if shouldResume { start() }
    }

    // MARK: - 音频回调（实时线程）

    private func handle(buffer: AVAudioPCMBuffer, format: AVAudioFormat, mode: CaptureMode, threshold: Double, token: UInt64) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }

        var sum: Double = 0
        for i in 0..<n {
            let v = Double(ch[i])
            sum += v * v
        }
        let rms = sqrt(sum / Double(n))
        // tap 的 buffer 由系统复用，跨队列前复制样本，不能保留回调内存直接异步写。
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for i in 0..<source.count {
            guard let src = source[i].mData, let dst = target[i].mData else { return }
            memcpy(dst, src, Int(source[i].mDataByteSize))
        }
        let now = Date()
        let work: () -> Void = { [weak self] in
            guard let self, self.acceptingBuffers, self.bufferGeneration == token else { return }
            let speaking = rms > threshold
            if speaking {
                self.lastVoiceAt = now
                self.wroteAnyVoice = true
            }
            let isSpeaking = self.lastVoiceAt.map { now.timeIntervalSince($0) <= mode.silenceGap } ?? false
            DispatchQueue.main.async {
                guard self.isRunning, self.bufferGeneration == token else { return }
                self.level = min(1.0, Double(rms) * 12)
                self.isSpeaking = isSpeaking
            }

            // 开始一段
            if self.file == nil && speaking {
                self.openSegment(format: format, at: now)
            }

            // 写入
            if let f = self.file {
                do {
                    if let out = self.prepareForWrite(copy) {
                        try f.write(from: out)
                    }
                } catch {
                    NSLog("涛声: 写音频失败 \(error)")
                }
            }

            // 结束条件
            if self.file != nil {
                let started = self.segmentStart ?? now
                let long = now.timeIntervalSince(started) >= mode.maxSegment
                let quiet = (self.lastVoiceAt.map { now.timeIntervalSince($0) > mode.silenceGap } ?? false)
                let tooShort = now.timeIntervalSince(started) < self.minimumDuration
                if long || (quiet && !tooShort) {
                    self.closeSegment(force: false)
                }
            }
        }
        queue.async(execute: work)
    }

    // MARK: - 段落文件

    /// 把硬件格式的 buffer 转成落盘格式（16k/16bit/mono）。转换器复用，避免每块重建丢历史。
    private func prepareForWrite(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target = writeFormat else { return buffer }
        let inFmt = buffer.format
        if inFmt.sampleRate == target.sampleRate && inFmt.channelCount == target.channelCount {
            return buffer
        }
        if converter == nil || converterRate != inFmt.sampleRate || converterChannels != inFmt.channelCount {
            converter = AVAudioConverter(from: inFmt, to: target)
            converterRate = inFmt.sampleRate
            converterChannels = inFmt.channelCount
        }
        guard let conv = converter else { return buffer }

        let ratio = target.sampleRate / inFmt.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var supplied = false
        var err: NSError?
        let input: AVAudioConverterInputBlock = { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        let result = conv.convert(to: out, error: &err, withInputFrom: input)
        if result == .error || err != nil || out.frameLength == 0 { return nil }
        return out
    }

    private func openSegment(format: AVAudioFormat, at date: Date) {
        let name = "\(DayKey.of(date))-\(UUID().uuidString).wav"
        let url = Store.audioDir.appendingPathComponent(name)
        do {
            let f = try AVAudioFile(forWriting: url, settings: fileSettings)
            writeFormat = f.processingFormat
            file = f
            fileURL = url
            segmentStart = date
            wroteAnyVoice = true
            NSLog("涛声: 新段 \(name)")
        } catch {
            NSLog("涛声: 建文件失败 \(error)")
        }
    }

    private func closeSegment(force: Bool) {
        guard file != nil, let url = fileURL, let start = segmentStart else { return }
        file = nil
        fileURL = nil
        segmentStart = nil
        let end = Date()
        let duration = end.timeIntervalSince(start)
        // AVAudioFile 在释放时 flush 文件头，先释放再读大小
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard duration >= minimumDuration, wroteAnyVoice || force else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        // 外放（视频/音乐）时不转写，直接丢掉这一段
        if Settings.shared.skipWhenOutput, AVAudioSession.sharedInstance().isOtherAudioPlaying {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if CaptureEngine.inSilenceWindow() {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let seg = Segment(
            id: shortID(),
            startedAt: start,
            endedAt: end,
            duration: duration,
            fileName: url.lastPathComponent,
            byteSize: size,
            transcript: "",
            speaker: "",
            state: .recorded,
            day: DayKey.of(start),
            createdAt: end,
            captureModeRaw: recordingMode.rawValue
        )
        Store.shared.insert(seg)
        DispatchQueue.main.async {
            self.onSegmentSaved?(seg)
            AppState.shared.refresh()
            NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
        }
    }
}
