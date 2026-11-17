import Foundation

/// 人声检测的纯规则（可单测）：切窗、前滚、最短人声、回落阈值。
///
/// 对齐原版 Android：
/// - `shared/.../audio/StreamingVad.kt`：512 新样本一窗（32 ms），走 Silero 概率；
/// - `shared/.../capture/CaptureTuning.kt`：`PRE_ROLL_SAMPLES = 1 s`、
///   `MIN_SPEECH_SAMPLES = 1 s`、`RMS_GATE = 0.002`（低于它连推理都不跑）；
/// - `shared/.../capture/SpeechSegmenter.kt`：人声不足 1 s 的段不保留。
public enum VadRules {

    /// Silero v6 在 16 kHz 下的固定窗口：512 样本。
    public static let window = 512

    /// 段首前滚：1 秒。原版就是这么补的，否则第一个字常常被切掉。
    public static let preRollSamples = 16_000

    /// 一段至少要有的真人声（1 秒），否则当噪音丢掉。
    public static let minVoicedSamples = 16_000

    /// 低于这个 RMS（约 -54 dBFS）直接当安静，不跑推理。原版 `CaptureTuning.RMS_GATE`。
    public static let rmsGate = 0.002

    /// 把任意长度的样本按 512 切成整窗，剩下的尾巴留到下一批（不改动输入）。
    public static func chunk(_ samples: [Float], carry: inout [Float], window: Int = VadRules.window) -> [[Float]] {
        guard window > 0 else { return [] }
        if !carry.isEmpty {
            var joined = carry
            joined.append(contentsOf: samples)
            carry = []
            return chunk(joined, carry: &carry, window: window)
        }
        var out: [[Float]] = []
        var index = 0
        while index + window <= samples.count {
            out.append(Array(samples[index..<(index + window)]))
            index += window
        }
        if index < samples.count { carry = Array(samples[index...]) }
        return out
    }

    /// 这一批要不要当「有人说话」：
    /// - 有 VAD 结果就以它为准（Silero 概率过阈值）；
    /// - 没有 VAD（模型缺失/模拟器）时退回能量阈值，但音量低于 `rmsGate` 一律不算。
    public static func isSpeech(rms: Double, energyThreshold: Double, vad: Bool?) -> Bool {
        if let vad { return vad }
        return rms >= max(rmsGate, energyThreshold)
    }

    /// 前滚环形缓冲只需要保留最后 1 秒。
    public static func trimmedPreRoll(_ samples: [Float], limit: Int = VadRules.preRollSamples) -> [Float] {
        guard samples.count > limit else { return samples }
        return Array(samples[(samples.count - limit)...])
    }

    /// 段结束时判断：真人声够 1 秒才留下。
    public static func kept(voicedSamples: Int, force: Bool) -> Bool {
        force || voicedSamples >= minVoicedSamples
    }
}
