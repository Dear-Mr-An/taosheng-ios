import Foundation
import AVFoundation

/// 把录下来的 m4a/caf 转成 SenseVoice 要的 16 kHz 单声道 Float32。
enum AudioPCM {
    struct Unsupported: LocalizedError {
        var errorDescription: String? { "这段音频打不开或者格式不支持" }
    }

    /// 只读一段：声纹只要每段几秒钟，没必要为了取 8 个 3 秒窗把整段 5 分钟的 PCM 全读进来
    /// （16 kHz 单声道 float32，5 分钟就是 19 MB，再复制一份就是 38 MB，真机上很容易被系统杀掉）。
    static func mono16kSlice(_ url: URL, at seconds: Double, length sliceSeconds: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let sr = inFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, seconds) * sr)
        guard startFrame < file.length else { throw TranscribeError.empty }
        let want = AVAudioFrameCount(max(1, min(sliceSeconds * sr, Double(file.length - startFrame))))
        file.framePosition = startFrame
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: want) else {
            throw Unsupported()
        }
        try file.read(into: inBuf)
        if abs(sr - 16_000) < 0.5, inFormat.channelCount == 1, let data = inBuf.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: data, count: Int(inBuf.frameLength)))
        }
        return try convertToMono16k(inBuf, from: inFormat)
    }

    static func mono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { throw TranscribeError.empty }
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
            throw Unsupported()
        }
        try file.read(into: inBuf)

        // 已经是 16k 单声道就不用过转换器了，省一层重采样误差
        if abs(inFormat.sampleRate - 16_000) < 0.5, inFormat.channelCount == 1,
           let data = inBuf.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: data, count: Int(inBuf.frameLength)))
        }

        return try convertToMono16k(inBuf, from: inFormat)
    }

    /// 重采样 + 混单声道。输入必须是已经读好的整块数据。
    private static func convertToMono16k(_ inBuf: AVAudioPCMBuffer, from inFormat: AVAudioFormat) throws -> [Float] {
        let frames = inBuf.frameLength
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw Unsupported()
        }
        let ratio = 16_000.0 / inFormat.sampleRate
        let outCap = AVAudioFrameCount(Double(frames) * ratio) + 4_096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCap) else {
            throw Unsupported()
        }
        var served = false
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if served {
                status.pointee = .endOfStream
                return nil
            }
            served = true
            status.pointee = .haveData
            return inBuf
        }
        if let error { throw error }
        guard let data = outBuf.floatChannelData?[0], outBuf.frameLength > 0 else {
            throw TranscribeError.empty
        }
        return Array(UnsafeBufferPointer(start: data, count: Int(outBuf.frameLength)))
    }
}

#if canImport(SherpaOnnx)
import SherpaOnnx

/// 本地 SenseVoice：模型就绪后整段离网识别。
///
/// 只做「整段文件 → 文字」，不做流式；录音那边的分段逻辑不变，
/// 每段还是走 TranscribeQueue 排队，只是不再需要网络。
final class SenseVoiceTranscriber: Transcriber {
    private let recognizer: SherpaOnnxOfflineRecognizer

    init?(modelURL: URL, tokensURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelURL.path), fm.fileExists(atPath: tokensURL.path) else {
            return nil
        }
        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: sherpaOnnxOfflineModelConfig(
                tokens: tokensURL.path,
                debug: 0,
                senseVoice: sherpaOnnxOfflineSenseVoiceModelConfig(
                    model: modelURL.path,
                    useInverseTextNormalization: true
                )
            )
        )
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    func transcribe(fileURL: URL) async throws -> TranscriptResult {
        let samples = try AudioPCM.mono16k(fileURL)
        guard !samples.isEmpty else { throw TranscribeError.empty }
        // 识别是纯 CPU 活，直接在本线程跑：转写队列本来就在后台任务里，
        // 也避免把 recognizer 这个非 Sendable 的对象塞进 detached 任务。
        let text = recognizer.decode(samples: samples, sampleRate: 16_000).text
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TranscribeError.empty }
        return TranscriptResult(text: clean)
    }
}
#endif
