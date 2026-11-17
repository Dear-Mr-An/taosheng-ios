import Foundation
#if canImport(SherpaOnnx)
import SherpaOnnx
#endif

/// Silero VAD 的 Swift 封装：喂 16 kHz 单声道浮点样本，回答「这一批里有没有人说话」。
///
/// 与原版 Android 用的是同一份模型（`silero_vad.onnx`，2.2 MB，随包带着），
/// 但推理走 sherpa-onnx 的 C 接口（原版直接调 ONNX Runtime）。
/// 原版实现见 `src/app/src/main/java/app/resound/audio/SileroVad.kt` 与
/// `src/shared/src/commonMain/kotlin/app/resound/audio/StreamingVad.kt`。
final class VadGate {

    /// Silero 的概率阈值，与原版 `CaptureTuning.SPEECH_THRESHOLD` 一致。
    static let speechThreshold: Float = 0.5

    /// 是否真的把模型加载起来了。false 时调用方要回落到能量阈值。
    let available: Bool

    #if canImport(SherpaOnnx)
    private let vad: SherpaOnnxVoiceActivityDetectorWrapper?
    #else
    private let vad: AnyObject? = nil
    #endif
    private var carry: [Float] = []

    init?(bundle: Bundle = .main) {
        #if canImport(SherpaOnnx)
        guard let path = bundle.path(forResource: "silero_vad", ofType: "onnx") else {
            NSLog("涛声: 包里没有 silero_vad.onnx，人声检测回落到能量阈值")
            return nil
        }
        var config = sherpaOnnxVadModelConfig(
            sileroVad: sherpaOnnxSileroVadModelConfig(
                model: path,
                threshold: VadGate.speechThreshold,
                // 静音收回快一点：分段还是由 CaptureEngine 按模式的停顿时长决定，
                // 这里只要「停下来了」这一位，不参与切段。
                minSilenceDuration: 0.15,
                minSpeechDuration: 0.05,
                windowSize: 512,
                // sherpa 内部到点会自动切一刀，取 55 秒足够长；缓冲 60 秒。
                maxSpeechDuration: 55
            ),
            sampleRate: 16_000,
            numThreads: 1,
            provider: "cpu",
            debug: 0
        )
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 60)
        available = true
        #else
        NSLog("涛声: 没有 sherpa-onnx，人声检测回落到能量阈值")
        return nil
        #endif
    }

    /// 喂一批 16 kHz 单声道样本；返回这批里是否出现过人声。
    func acceptsSpeech(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        #if canImport(SherpaOnnx)
        guard let vad else { return false }
        var heard = false
        for window in VadRules.chunk(samples, carry: &carry) {
            vad.acceptWaveform(samples: window)
            if vad.isSpeechDetected() { heard = true }
            // 内部已完成的段必须弹掉，否则长时间录音会把内存堆满。
            while !vad.isEmpty() { vad.pop() }
        }
        return heard
        #else
        return false
        #endif
    }

    /// 换段/停采集时清掉跨块状态。
    func reset() {
        carry.removeAll()
        #if canImport(SherpaOnnx)
        vad?.reset()
        #endif
    }
}
