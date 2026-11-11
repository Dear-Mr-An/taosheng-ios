import Foundation
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

    private let queue = DispatchQueue(label: "app.taosheng.capture")

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

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async {
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
                lastError = "没有可用的麦克风输入。"
                return
            }

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.handle(buffer: buffer, format: format)
            }

            engine.prepare()
            try engine.start()
            isRunning = true
            startedAt = Date()
            lastError = nil
            NSLog("涛声: 采集已启动 \(format.sampleRate)Hz \(format.channelCount)ch")
        } catch {
            lastError = "启动录音失败：\(error.localizedDescription)"
            NSLog("涛声: 启动失败 \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        closeSegment(force: true)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
        startedAt = nil
        isSpeaking = false
        level = 0
    }

    // MARK: - 音频回调（实时线程）

    private func handle(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }

        var sum: Double = 0
        for i in 0..<n {
            let v = Double(ch[i])
            sum += v * v
        }
        let rms = sqrt(sum / Double(n))
        let s = Settings.shared
        let threshold = s.sensitivity

        let now = Date()
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.level = min(1.0, Double(rms) * 12)
            }

            let speaking = rms > threshold
            if speaking {
                self.lastVoiceAt = now
                self.wroteAnyVoice = true
                DispatchQueue.main.async { self.isSpeaking = true }
            } else if let last = self.lastVoiceAt, now.timeIntervalSince(last) > s.silenceGap {
                DispatchQueue.main.async { self.isSpeaking = false }
            }

            // 开始一段
            if self.file == nil && speaking {
                self.openSegment(format: format, at: now)
            }

            // 写入
            if let f = self.file {
                do {
                    if let out = self.prepareForWrite(buffer) {
                        try f.write(from: out)
                    }
                } catch {
                    NSLog("涛声: 写音频失败 \(error)")
                }
            }

            // 结束条件
            if self.file != nil {
                let started = self.segmentStart ?? now
                let long = now.timeIntervalSince(started) >= s.maxSegment
                let quiet = (self.lastVoiceAt.map { now.timeIntervalSince($0) > s.silenceGap } ?? false)
                let tooShort = now.timeIntervalSince(started) < s.minSegment
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
        let name = "\(DayKey.of(date))-\(Int(date.timeIntervalSince1970)).wav"
        let url = Store.audioDir.appendingPathComponent(name)
        do {
            let f = try AVAudioFile(forWriting: url, settings: fileSettings)
            writeFormat = f.processingFormat
            file = f
            fileURL = url
            segmentStart = date
            wroteAnyVoice = false
            NSLog("涛声: 新段 \(name)")
        } catch {
            NSLog("涛声: 建文件失败 \(error)")
        }
    }

    private func closeSegment(force: Bool) {
        guard let f = file, let url = fileURL, let start = segmentStart else { return }
        var held: AVAudioFile? = f
        file = nil
        fileURL = nil
        segmentStart = nil
        let end = Date()
        let duration = end.timeIntervalSince(start)
        // AVAudioFile 在释放时 flush 文件头，先释放再读大小
        held = nil
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard duration >= Settings.shared.minSegment, wroteAnyVoice || force else {
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
            createdAt: end
        )
        Store.shared.insert(seg)
        DispatchQueue.main.async {
            self.onSegmentSaved?(seg)
        }
    }
}
